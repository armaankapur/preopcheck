//
//  ScannerView.swift
//  Stanford Preoperative Medication
//
//  What this screen does, top to bottom:
//
//  1. SECTION AWARENESS. Text inside an allergy-style section is excluded
//     before matching, so "Codeine - nausea" under ALLERGIES is never
//     reported as an active medication. SectionExclusion decides the bands.
//
//  2. LIVE MARKERS. Green ellipses outline recognised drugs; red ellipses
//     mark drug-looking words that matched nothing, so the clinician can see
//     that something on the page did not scan.
//
//  3. AUTO-CAPTURE. There is no shutter. Once the set of recognised drugs has
//     held steady for a second, the frame freezes and Proceed / Retake appear.
//
//  4. LAYOUT. Chrome is positioned from the safe area in viewDidLayoutSubviews.
//     Portrait stacks controls below the guide box; landscape (iPad) moves them
//     into a right-hand column so the guide box keeps its height.
//
//  5. PRIVACY BLUR. Lines that identify the patient (name, DOB, MRN) are
//     blurred on screen by RedactionOverlayView; PatientIdentity decides which
//     lines those are. Drug lines are never blurred.
//
//  Coordinates: the frames handed to Vision are rotated to match the screen,
//  so a Vision box maps onto the preview with plain aspect-fill arithmetic
//  using the frame's own size. (The preview layer's metadata conversions are
//  relative to the sensor's native orientation and do not line up with
//  rotated frames; using them put every marker in the wrong place.)
//
//  In the Simulator there is no camera, so a built-in sample medication page
//  is fed through the same pipeline. That lets the markers and auto-capture
//  be seen and tuned without a device.
//

import SwiftUI
import AVFoundation
import Vision

// MARK: - SwiftUI wrapper

struct ScannerView: UIViewControllerRepresentable {
    @Binding var scannedMeds: [DrugMatch]
    @Binding var isScanning: Bool

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(scannedMeds: $scannedMeds, isScanning: $isScanning)
    }

    class Coordinator: NSObject, ScannerViewControllerDelegate {
        @Binding var scannedMeds: [DrugMatch]
        @Binding var isScanning: Bool

        init(scannedMeds: Binding<[DrugMatch]>, isScanning: Binding<Bool>) {
            _scannedMeds = scannedMeds
            _isScanning = isScanning
        }

        func didDetectMedications(_ matches: [DrugMatch]) {
            DispatchQueue.main.async {
                self.scannedMeds = matches
                self.isScanning = false
            }
        }
    }
}

protocol ScannerViewControllerDelegate: AnyObject {
    func didDetectMedications(_ matches: [DrugMatch])
}

// MARK: - Scan state (lock-protected)

/// Written on the camera queue, read on the main thread. Keyed on drug.id.
private final class ScanState {
    private let lock = NSLock()
    private var sightings: [String: Int] = [:]
    private var best: [String: DrugMatch] = [:]

    static let stabilityThreshold = 3

    func record(_ matches: [DrugMatch]) {
        lock.lock(); defer { lock.unlock() }
        for m in matches {
            sightings[m.id, default: 0] += 1
            if let existing = best[m.id] {
                // Keep the strongest match kind, but always take the latest
                // boxes so page order reflects the frame that was captured.
                let kind = max(existing.matchKind, m.matchKind)
                let text = m.matchKind > existing.matchKind ? m.matchedText : existing.matchedText
                best[m.id] = DrugMatch(drug: m.drug, matchedText: text,
                                       matchKind: kind, boxes: m.boxes)
            } else {
                best[m.id] = m
            }
        }
    }

    func stableMatches() -> [DrugMatch] {
        lock.lock(); defer { lock.unlock() }
        return sightings
            .filter { $0.value >= ScanState.stabilityThreshold }
            .compactMap { best[$0.key] }
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        sightings.removeAll()
        best.removeAll()
    }
}

// MARK: - View controller

final class ScannerViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    weak var delegate: ScannerViewControllerDelegate?

    // Camera (device only)
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let cameraQueue = DispatchQueue(label: "com.stanford.preop.camera")

    // Simulator stand-in: a sample page shown in place of the camera.
    private var sampleImage: UIImage?
    private var samplePixelBuffer: CVPixelBuffer?
    private var sampleTimer: Timer?
    private let sampleLayer = CALayer()

    private let state = ScanState()

    // Markers over the picture: one layer per drug, keyed by drug id (green)
    // or ingredient (red). A marker fades in once its drug is stable, glides
    // to its new position each frame, and fades out when the drug is lost.
    private let markerHost = CALayer()
    private var markerLayers: [String: CAShapeLayer] = [:]
    private var markerLastSeen: [String: Date] = [:]
    private let markerHold: TimeInterval = 0.7
    private let markerGlide: CFTimeInterval = 0.18

    // Blur bars over patient details, under the markers.
    private let redactionOverlay = RedactionOverlayView()

    /// Pixel size of the frames being recognised (already rotated to match
    /// the screen). Written on the camera queue, read on main under
    /// `generationLock`. Drives the Vision-to-screen mapping.
    private var frameSize: CGSize = .zero

    // Chrome
    private var guideRect: CGRect = .zero
    private let guideLayer = CALayer()
    private let cornerLayer = CAShapeLayer()
    private let lockChip = UIView()
    private let lockIcon = UIImageView(image: UIImage(systemName: "lock.fill"))
    private let lockText = UILabel()
    private let instructionLabel = UILabel()
    private let countLabel = UILabel()
    private let shutter = UIButton(type: .custom)
    private let retakeButton = UIButton(type: .system)

    // Auto-capture: fires once the set of stable drugs has stopped changing.
    private var lastStableIDs: Set<String> = []
    private var lastStableChange = Date()
    private static let autoCaptureDelay: TimeInterval = 1.0

    /// Scanning shows a live count; captured freezes the frame and waits for
    /// the clinician to tap Proceed.
    private enum Phase { case scanning, captured }
    private var phase: Phase = .scanning
    private var capturedMatches: [DrugMatch] = []

    private var lastReportedCount = -1

    private var frameGeneration = 0
    private let generationLock = NSLock()
    /// Guide box in Vision space, refreshed on layout, read on the camera queue.
    private var cachedROI = CGRect(x: 0, y: 0, width: 1, height: 1)

    private var lastProcessTime = Date.distantPast
    private let minFrameInterval: TimeInterval = 0.3

    private let stanfordRed = UIColor(red: 0.549, green: 0.082, blue: 0.082, alpha: 1)

    // Layout constants, one place.
    private enum L {
        static let chipHeight: CGFloat = 28
        static let gutter: CGFloat = 22         // vertical rhythm
        static let labelHeight: CGFloat = 36
        static let countHeight: CGFloat = 36
        static let countWidth: CGFloat = 236
        static let controlsHeight: CGFloat = 58
        static let controlsBottomGap: CGFloat = 34
        static let guideMargin: CGFloat = 12          // box edge to screen edge
        static let navClearance: CGFloat = 50         // room for Cancel / info bar
        static let proceedWidth: CGFloat = 176
        static let proceedCorner: CGFloat = 14
        static let retakeWidth: CGFloat = 84
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildDisplayStack()
        setupFrameSource()
        buildChrome()
        setPhase(.scanning, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for layer in [sampleLayer, markerHost] {
            layer.frame = view.bounds
        }
        redactionOverlay.frame = view.bounds
        previewLayer?.frame = view.bounds
        updateVideoRotation()
        layoutChrome()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopFrames()
    }

    // MARK: Frame source

    /// Camera on a device; the sample page in the Simulator.
    private func setupFrameSource() {
        #if targetEnvironment(simulator)
        setupSamplePage()
        #else
        setupCamera()
        #endif
    }

    private func startFrames() {
        #if targetEnvironment(simulator)
        sampleTimer?.invalidate()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: minFrameInterval, repeats: true) { [weak self] _ in
            guard let self, let buffer = self.samplePixelBuffer else { return }
            self.cameraQueue.async { self.process(pixelBuffer: buffer) }
        }
        #else
        cameraQueue.async { [weak self] in self?.captureSession.startRunning() }
        #endif
    }

    private func stopFrames() {
        #if targetEnvironment(simulator)
        sampleTimer?.invalidate()
        sampleTimer = nil
        #else
        cameraQueue.async { [weak self] in self?.captureSession.stopRunning() }
        #endif
    }

    private func setupCamera() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: cameraQueue)
        if captureSession.canAddOutput(output) { captureSession.addOutput(output) }
        videoOutput = output

        // Rotation is applied per orientation in updateVideoRotation().
        captureSession.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)     // under markers and chrome
        previewLayer = preview

        startFrames()
    }

    /// Keeps the camera frames upright relative to the screen. The session
    /// used to be pinned to portrait, so on an iPad held in landscape the
    /// preview was stretched and Vision received the text sideways, which
    /// is a common reason a list "won't scan". Both the on-screen preview
    /// and the frames sent to Vision get the same rotation, so the guide
    /// box maps onto the frame correctly in every orientation.
    private func updateVideoRotation() {
        guard let orientation = view.window?.windowScene?.interfaceOrientation else { return }
        let angle: CGFloat
        switch orientation {
        case .landscapeRight:     angle = 0
        case .landscapeLeft:      angle = 180
        case .portraitUpsideDown: angle = 270
        default:                  angle = 90
        }
        let connections = [previewLayer?.connection, videoOutput?.connection(with: .video)]
        for connection in connections.compactMap({ $0 })
        where connection.isVideoRotationAngleSupported(angle) && connection.videoRotationAngle != angle {
            connection.videoRotationAngle = angle
        }
    }

    // MARK: Simulator sample page

    /// A made-up medication printout. Rendered once, then fed through the
    /// same recognition path as camera frames.
    private func setupSamplePage() {
        let image = ScannerViewController.renderSamplePage()
        sampleImage = image
        samplePixelBuffer = ScannerViewController.pixelBuffer(from: image)

        sampleLayer.contents = image.cgImage
        sampleLayer.contentsGravity = .resizeAspectFill
        view.layer.insertSublayer(sampleLayer, at: 0)  // under markers and chrome

        startFrames()
    }

    private static func renderSamplePage() -> UIImage {
        let size = CGSize(width: 1242, height: 2208)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            func draw(_ text: String, x: CGFloat = 110, y: CGFloat, size fontSize: CGFloat,
                      bold: Bool = false, color: UIColor = .black) {
                let font = bold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            }

            // Laid out like Epic's Medications tab, which is what the app is
            // tested against: name on its own line, identifiers under it, then
            // a table of title line + lowercase detail line, start date and
            // ordering provider. Allergies sit at the bottom here so the
            // section exclusion does not swallow the table.
            let epicBlue = UIColor(red: 0.13, green: 0.36, blue: 0.69, alpha: 1)
            draw("Stanford Children's Health", y: 120, size: 44, bold: true)
            draw("Doe, John", y: 210, size: 40, bold: true)
            draw("MRN: 12345678     58 y.o.     M     01/01/1967     PCP: Smith, MD", y: 270, size: 28, color: .darkGray)
            draw("Medications", y: 360, size: 40, bold: true, color: epicBlue)

            let rows: [(title: String, detail: String, started: String)] = [
                ("Acetaminophen (Tylenol)",   "acetaminophen 500 mg tablet",               "01/10/2024"),
                ("Amlodipine (Norvasc)",      "amlodipine 5 mg tablet",                    "06/12/2023"),
                ("Atorvastatin (Lipitor)",    "atorvastatin 20 mg tablet",                 "03/01/2023"),
                ("Losartan (Cozaar)",         "losartan 50 mg tablet",                     "02/15/2023"),
                ("Metformin (Glucophage)",    "metformin 500 mg tablet",                   "01/20/2023"),
                ("Omeprazole (Prilosec)",     "omeprazole 20 mg capsule",                  "08/11/2023"),
                ("Sertraline (Zoloft)",       "sertraline 50 mg tablet",                   "11/05/2023"),
                ("Albuterol HFA (ProAir HFA)", "albuterol 90 mcg/actuation inhaler",       "04/22/2024"),
                ("Fluticasone (Flonase)",     "fluticasone 50 mcg/actuation nasal spray",  "03/15/2023"),
                ("Vitamin D3",                "cholecalciferol 1,000 unit tablet",         "01/10/2024")
            ]
            for (i, row) in rows.enumerated() {
                let y = 440 + CGFloat(i) * 104
                draw(row.title, y: y, size: 32, bold: true, color: epicBlue)
                draw(row.detail, y: y + 42, size: 26, color: .darkGray)
                draw(row.started, x: 760, y: y + 8, size: 26)
                draw("Smith, MD", x: 960, y: y + 8, size: 26)
            }

            draw("Allergies", y: 1520, size: 40, bold: true, color: epicBlue)
            draw("Codeine - nausea and vomiting", y: 1590, size: 32)
            draw("Penicillin - rash", y: 1650, size: 32)
            // Footer, the way printouts repeat the name on every page.
            draw("John Q. Doe     Printed 10/09/2026     Page 1 of 1", y: 1760, size: 26, color: .darkGray)
        }
    }

    private static func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true,
                                      kCVPixelBufferCGBitmapContextCompatibilityKey: true]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer) == kCVReturnSuccess,
              let pb = buffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pb),
                                      width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                                | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pb
    }

    // MARK: Coordinates

    /// Where the aspect-filled frame lands inside the view. Both the camera
    /// preview and the Simulator sample use aspect-fill, so this one piece of
    /// arithmetic serves both.
    private func sourceFrame() -> CGRect? {
        generationLock.lock()
        let s = frameSize
        generationLock.unlock()
        guard s.width > 0, s.height > 0 else { return nil }
        let b = view.bounds
        let scale = max(b.width / s.width, b.height / s.height)
        let w = s.width * scale, h = s.height * scale
        return CGRect(x: (b.width - w) / 2, y: (b.height - h) / 2, width: w, height: h)
    }

    /// Vision space is normalised with y pointing up.
    private func visionRect(fromViewRect r: CGRect) -> CGRect {
        guard let f = sourceFrame() else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let x = (r.minX - f.minX) / f.width
        let yTop = (r.minY - f.minY) / f.height
        let w = r.width / f.width, h = r.height / f.height
        return CGRect(x: x, y: 1 - yTop - h, width: w, height: h)
    }

    private func viewRect(fromVisionBox b: CGRect) -> CGRect {
        guard let f = sourceFrame() else { return .zero }
        return CGRect(x: f.minX + b.minX * f.width,
                      y: f.minY + (1 - b.maxY) * f.height,
                      width: b.width * f.width,
                      height: b.height * f.height)
    }

    private func guideRectInVisionSpace() -> CGRect {
        guard guideRect != .zero else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return visionRect(fromViewRect: guideRect)
    }

    // MARK: Capture output

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        process(pixelBuffer: pixelBuffer)
    }

    /// Shared by the camera and the Simulator sample page. Runs on cameraQueue.
    private func process(pixelBuffer: CVPixelBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) > minFrameInterval else { return }
        lastProcessTime = now

        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                          height: CVPixelBufferGetHeight(pixelBuffer))

        generationLock.lock()
        frameGeneration += 1
        let generation = frameGeneration
        let sizeChanged = size != frameSize
        frameSize = size
        let roi = cachedROI
        generationLock.unlock()

        // First frame, or an orientation change: the guide box must be
        // re-mapped against the new frame size before it is used.
        if sizeChanged {
            DispatchQueue.main.async { [weak self] in self?.view.setNeedsLayout() }
        }

        let request = VNRecognizeTextRequest { [weak self] request, _ in
            guard let self,
                  let observations = request.results as? [VNRecognizedTextObservation] else { return }
            self.handle(observations: observations, roi: roi, generation: generation)
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.012

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }

    // MARK: Recognition handling

    private func handle(observations: [VNRecognizedTextObservation],
                        roi: CGRect,
                        generation: Int) {

        generationLock.lock()
        let isCurrent = generation == frameGeneration
        generationLock.unlock()
        guard isCurrent else { return }

        // Every line as text plus box, for the page-level rules below.
        let allLines = observations.compactMap { obs in
            obs.topCandidates(1).first.map { ScannedLine(text: $0.string, box: obs.boundingBox) }
        }
        // Allergy-style sections, worked out from the lines in the guide box.
        let excludedBands = SectionExclusion.bands(in: allLines.filter { roi.intersects($0.box) })

        var frameMatches: [String: DrugMatch] = [:]
        var greenBoxes: [String: CGRect] = [:]          // drug id -> marker box
        var unlisted: [(ingredient: String, box: CGRect)] = []

        // Lines that already carry a marker, used to recognise the detail
        // line printed under a drug name ("acetaminophen 500 mg tablet") so
        // it is not marked a second time. `lastPlainLine` is the most recent
        // line with no drug on it: when a title misreads and only its detail
        // line is recognised, the marker is promoted onto that title line.
        var markedLines: [CGRect] = []
        var lastPlainLine: CGRect?
        var seenUnlisted = Set<String>()

        // Privacy: lines that identify the patient, judged across the whole
        // frame so a header above the guide box counts too. Any that turn out
        // to carry a drug are dropped from this list afterwards.
        let identityLines = PatientIdentity.identityLines(in: allLines)

        // Top of the page first, so "first seen" means "the title line".
        for obs in observations.sorted(by: { $0.boundingBox.maxY > $1.boundingBox.maxY }) {
            guard roi.intersects(obs.boundingBox) else { continue }

            // Skip the allergy heading and the section under it.
            if SectionExclusion.isExcluded(obs.boundingBox, by: excludedBands) { continue }

            guard let candidate = obs.topCandidates(1).first else { continue }

            // One token per word, each with its own box so markers sit on the
            // word rather than the whole line. Falls back to the line box.
            let tokens = candidate.string.split(separator: " ").map { word -> OCRToken in
                let range = word.startIndex..<word.endIndex
                let box = (try? candidate.boundingBox(for: range))?.boundingBox ?? obs.boundingBox
                return OCRToken(text: String(word), box: box, ocrConfidence: candidate.confidence)
            }

            let matches = DrugMatcher.shared.match(tokens)
            for match in matches {
                if let existing = frameMatches[match.id] {
                    frameMatches[match.id] = match.matchKind > existing.matchKind ? match : existing
                } else {
                    frameMatches[match.id] = match
                }
                // First line wins (the title), and the box grows to take in
                // a bracketed brand right after the name.
                if greenBoxes[match.id] == nil {
                    greenBoxes[match.id] = ScannerViewController.titleBox(hitBoxes: match.boxes, in: tokens)
                }
            }
            // A line with a PARC match is done: its brand in brackets, or any
            // other word on it, never gets a red box of its own.
            if !matches.isEmpty {
                markedLines.append(obs.boundingBox)
                continue
            }

            // Red: a known drug (per the lexicon) that PARC has nothing on.
            // One box per line covering name and brand together. A drug whose
            // ingredient was already marked higher up (the detail line under
            // "Vitamin D3" says "cholecalciferol") is skipped.
            // The FDA list has products called "Allergies" and "Full", so a
            // hit only counts on a line that looks like a medication entry.
            let hits = ScannerViewController.unlistedDrugHits(in: tokens)
                .filter { !seenUnlisted.contains($0.ingredient) }
            guard !hits.isEmpty,
                  MedicationLineCues.hasMedicationContext(text: candidate.string,
                                                          box: obs.boundingBox, in: allLines)
            else {
                lastPlainLine = obs.boundingBox
                continue
            }

            let isDetail = MedicationLineCues.looksLikeDetailLine(candidate.string)
            var box = ScannerViewController.titleBox(hitBoxes: hits.map(\.box), in: tokens)
            if isDetail {
                if MedicationLineCues.isDirectlyBelow(obs.boundingBox, markedLines) {
                    continue            // detail line of a drug already marked
                }
                if let title = lastPlainLine,
                   MedicationLineCues.isDirectlyBelow(obs.boundingBox, [title]) {
                    box = title         // title misread: mark the title line instead
                }
            }

            hits.forEach { seenUnlisted.insert($0.ingredient) }
            unlisted.append((hits[0].ingredient, box))
            markedLines.append(obs.boundingBox)
        }

        // Non-drug text is never retained. Only box positions leave this
        // function, for drawing; the words themselves are discarded.
        state.record(Array(frameMatches.values))
        let stableIDs = Set(state.stableMatches().map(\.id))

        // Green: exactly one box per drug, on its title line.
        let green: [(key: String, box: CGRect)] = greenBoxes.map { ($0.key, $0.value) }
        let red: [(key: String, box: CGRect)] = unlisted.map { ("red:" + $0.ingredient, $0.box) }
        let redactions = identityLines.filter { line in
            !markedLines.contains { $0.intersects(line) }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase == .scanning else { return }
            self.updateCount(stableIDs.count)
            self.redactionOverlay.update(with: redactions.map(self.viewRect(fromVisionBox:)))
            self.drawMarkers(green: green, red: red)
            self.checkAutoCapture(stableIDs)
        }
    }

    /// Phrases on one line that the drug lexicon knows, with their ingredient
    /// key and box. Tries multi-word names first, longest span wins. Returns
    /// nothing while no lexicon is bundled.
    private static func unlistedDrugHits(in tokens: [OCRToken]) -> [(ingredient: String, box: CGRect)] {
        let lexicon = DrugLexicon.shared
        guard !lexicon.isEmpty, !tokens.isEmpty else { return [] }

        let norms = tokens.map { DrugMatcher.normalize($0.text) }
        var consumed = Set<Int>()
        var hits: [(ingredient: String, box: CGRect)] = []

        for span in stride(from: min(lexicon.maxWords, tokens.count), through: 1, by: -1) {
            for start in 0...(tokens.count - span) {
                let range = start..<(start + span)
                if range.contains(where: { consumed.contains($0) }) { continue }
                let phrase = norms[range].filter { !$0.isEmpty }.joined(separator: " ")
                guard phrase.count >= 4, let ingredient = lexicon.ingredient(for: phrase) else { continue }
                let union = tokens[range].dropFirst().reduce(tokens[start].box) { $0.union($1.box) }
                hits.append((ingredient, union))
                range.forEach { consumed.insert($0) }
            }
        }
        return hits
    }

    /// The marker box for a drug on one line: the words that matched, plus a
    /// bracketed brand name immediately after them, so "Metformin (Glucophage)"
    /// is boxed as one even when the brand is in neither list.
    private static func titleBox(hitBoxes: [CGRect], in tokens: [OCRToken]) -> CGRect {
        guard var box = hitBoxes.first else { return .zero }
        hitBoxes.dropFirst().forEach { box = box.union($0) }

        guard let last = tokens.lastIndex(where: { hitBoxes.contains($0.box) }) else { return box }
        var i = last + 1
        guard i < tokens.count, tokens[i].text.hasPrefix("(") else { return box }
        while i < tokens.count, i <= last + 3 {
            box = box.union(tokens[i].box)
            if tokens[i].text.hasSuffix(")") { break }
            i += 1
        }
        return box
    }

    // MARK: Markers

    /// One rounded box per drug. Existing markers glide to their new place,
    /// new ones fade in, and markers not seen for `markerHold` fade out.
    /// Each incoming rect already covers every word of its drug.
    private func drawMarkers(green: [(key: String, box: CGRect)], red: [(key: String, box: CGRect)]) {
        let now = Date()

        CATransaction.begin()
        CATransaction.setAnimationDuration(markerGlide)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))

        for (isGreen, items) in [(true, green), (false, red)] {
            for item in items {
                let r = ScannerViewController.markerRect(viewRect(fromVisionBox: item.box))
                let layer = markerLayers[item.key] ?? makeMarker(green: isGreen, at: r)
                markerLayers[item.key] = layer
                markerLastSeen[item.key] = now
                // Animating bounds + position keeps the path static, so the
                // move is a smooth glide rather than a path morph.
                layer.bounds = CGRect(origin: .zero, size: r.size)
                layer.position = CGPoint(x: r.midX, y: r.midY)
                layer.path = UIBezierPath(roundedRect: layer.bounds,
                                          cornerRadius: min(8, r.height / 2)).cgPath
                layer.opacity = 1
            }
        }

        for (key, seen) in markerLastSeen where now.timeIntervalSince(seen) > markerHold {
            if let layer = markerLayers[key] {
                layer.opacity = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + markerGlide) { [weak layer] in
                    layer?.removeFromSuperlayer()
                }
            }
            markerLayers[key] = nil
            markerLastSeen[key] = nil
        }

        CATransaction.commit()
    }

    private func makeMarker(green: Bool, at r: CGRect) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.strokeColor = (green ? UIColor.actionGreen : UIColor.systemRed).cgColor
        layer.fillColor = nil
        layer.lineWidth = green ? 2.5 : 2
        layer.bounds = CGRect(origin: .zero, size: r.size)
        layer.position = CGPoint(x: r.midX, y: r.midY)
        layer.opacity = 0
        markerHost.addSublayer(layer)
        return layer
    }

    private func clearMarkers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        markerLayers.values.forEach { $0.removeFromSuperlayer() }
        markerLayers.removeAll()
        markerLastSeen.removeAll()
        CATransaction.commit()
    }

    /// A little breathing room around the text.
    private static func markerRect(_ r: CGRect) -> CGRect {
        r.insetBy(dx: -r.height * 0.3, dy: -r.height * 0.2)
    }

    // MARK: Auto-capture

    /// Captures on its own once the set of stable drugs has not changed for
    /// `autoCaptureDelay`. Panning across a long list keeps adding drugs,
    /// which keeps resetting the clock, so capture waits for the list to settle.
    private func checkAutoCapture(_ ids: Set<String>) {
        let now = Date()
        if ids != lastStableIDs {
            lastStableIDs = ids
            lastStableChange = now
            return
        }
        guard !ids.isEmpty,
              now.timeIntervalSince(lastStableChange) >= ScannerViewController.autoCaptureDelay
        else { return }
        capture()
    }

    // MARK: Capture

    /// The button is only visible after a capture, where it reads "Proceed".
    @objc private func shutterTapped() {
        guard phase == .captured else { return }
        proceed()
    }

    /// Step one: freeze the frame and keep what was read. Triggered
    /// automatically by `checkAutoCapture`, never by a shutter press.
    private func capture() {
        let matches = state.stableMatches()
        guard !matches.isEmpty, phase == .scanning else { return }

        capturedMatches = matches
        stopFrames()
        setPhase(.captured, animated: true)
    }

    /// Step two: run analysis. The delegate resolves and pushes results.
    private func proceed() {
        guard !capturedMatches.isEmpty else { return }
        delegate?.didDetectMedications(capturedMatches)
    }

    @objc private func retake() {
        capturedMatches = []
        state.reset()
        lastStableIDs = []
        lastStableChange = Date()
        lastReportedCount = -1
        updateCount(0)
        clearMarkers()
        redactionOverlay.clear()
        setPhase(.scanning, animated: true)
        startFrames()
    }

    /// Scanning shows only the live count and markers; capture happens on its
    /// own. Captured shows Proceed and Retake.
    private func setPhase(_ new: Phase, animated: Bool) {
        phase = new
        let captured = new == .captured

        let n = capturedMatches.count
        countLabel.text = captured
            ? (n == 1 ? "1 medication captured" : "\(n) medications captured")
            : "0 medications detected"
        instructionLabel.text = captured
            ? "Tap Proceed to analyze"
            : "Fill the box with the list. Captures automatically."
        shutter.isUserInteractionEnabled = captured
        retakeButton.isUserInteractionEnabled = captured

        let changes = {
            self.shutter.alpha = captured ? 1 : 0
            self.retakeButton.alpha = captured ? 1 : 0
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut], animations: changes)
        } else {
            changes()
        }
    }

    // MARK: Display stack

    /// The picture (camera preview or sample page) is inserted at the bottom
    /// by the frame source; blur bars go above it, markers above those, and
    /// chrome on top.
    private func buildDisplayStack() {
        view.addSubview(redactionOverlay)
        view.layer.addSublayer(markerHost)
    }

    // MARK: Chrome construction

    private func buildChrome() {
        // Guide box
        guideLayer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        guideLayer.borderWidth = 1
        guideLayer.cornerRadius = 14
        view.layer.addSublayer(guideLayer)

        cornerLayer.strokeColor = UIColor.white.cgColor
        cornerLayer.lineWidth = 3
        cornerLayer.fillColor = UIColor.clear.cgColor
        cornerLayer.lineCap = .round
        view.layer.addSublayer(cornerLayer)

        // Privacy chip
        lockChip.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        lockChip.layer.cornerRadius = L.chipHeight / 2
        view.addSubview(lockChip)

        lockIcon.tintColor = .white
        lockIcon.contentMode = .scaleAspectFit
        lockChip.addSubview(lockIcon)

        lockText.text = "On device. Nothing saved."
        lockText.textColor = .white
        lockText.font = .app(12, weight: .medium)
        lockChip.addSubview(lockText)

        // Instruction
        instructionLabel.textColor = .white
        instructionLabel.font = .app(15, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        instructionLabel.layer.cornerRadius = L.labelHeight / 2
        instructionLabel.layer.masksToBounds = true
        view.addSubview(instructionLabel)

        // Count
        countLabel.textColor = .white
        countLabel.font = .app(15, weight: .semibold)
        countLabel.textAlignment = .center
        countLabel.backgroundColor = stanfordRed.withAlphaComponent(0.92)
        countLabel.layer.cornerRadius = L.countHeight / 2
        countLabel.layer.masksToBounds = true
        view.addSubview(countLabel)

        // Proceed, only visible after a capture.
        shutter.layer.cornerRadius = L.proceedCorner
        shutter.backgroundColor = .actionGreen
        shutter.setTitle("Proceed", for: .normal)
        shutter.setTitleColor(.white, for: .normal)
        shutter.titleLabel?.font = .app(17, weight: .semibold)
        shutter.accessibilityLabel = "Proceed to analysis"
        shutter.addTarget(self, action: #selector(shutterDown), for: .touchDown)
        shutter.addTarget(self, action: #selector(shutterUp),
                          for: [.touchUpInside, .touchUpOutside, .touchCancel])
        shutter.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        view.addSubview(shutter)

        // Retake, only visible after a capture.
        retakeButton.setTitle("Retake", for: .normal)
        retakeButton.setTitleColor(.white, for: .normal)
        retakeButton.titleLabel?.font = .app(15, weight: .medium)
        retakeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        retakeButton.layer.cornerRadius = L.proceedCorner
        retakeButton.addTarget(self, action: #selector(retake), for: .touchUpInside)
        view.addSubview(retakeButton)
    }

    // MARK: Chrome layout

    /// Everything is positioned from the safe area outward, in a single pass,
    /// so the spacing is consistent and the guide box takes whatever room is
    /// left rather than a fixed fraction of the screen.
    ///
    /// Portrait stacks the controls under the guide box. Landscape (an iPad
    /// on a desk, typically) moves them into a column on the right so the
    /// guide box can use the full height instead of being squeezed to a
    /// thin strip.
    private func layoutChrome() {
        let w = view.bounds.width
        let h = view.bounds.height
        let safeTop = view.safeAreaInsets.top
        let safeBottom = view.safeAreaInsets.bottom
        let landscape = w > h

        // Privacy chip, top centre in both layouts, sitting just inside the
        // guide box's top edge.
        lockText.sizeToFit()
        let chipWidth = 12 + 12 + 7 + lockText.bounds.width + 14
        let chipY = safeTop + L.navClearance + 10
        lockChip.frame = CGRect(x: (w - chipWidth) / 2, y: chipY,
                                width: chipWidth, height: L.chipHeight)
        lockIcon.frame = CGRect(x: 12, y: (L.chipHeight - 14) / 2, width: 12, height: 14)
        lockText.frame = CGRect(x: 12 + 12 + 7, y: 0,
                                width: lockText.bounds.width, height: L.chipHeight)

        if landscape {
            // Right-hand column: instruction, count, controls, centred vertically.
            let columnWidth = max(L.countWidth, L.proceedWidth + 12 + L.retakeWidth) + 40
            let columnX = w - columnWidth - view.safeAreaInsets.right
            let centerX = columnX + columnWidth / 2
            let centerY = h / 2

            placeControls(centerX: centerX, centerY: centerY)

            let countY = centerY - L.controlsHeight / 2 - L.gutter - L.countHeight
            countLabel.frame = CGRect(x: centerX - L.countWidth / 2, y: countY,
                                      width: L.countWidth, height: L.countHeight)
            let instructionWidth = columnWidth - 24
            instructionLabel.frame = CGRect(x: centerX - instructionWidth / 2,
                                            y: countY - 12 - L.labelHeight,
                                            width: instructionWidth, height: L.labelHeight)

            // Guide box takes the rest: full height under the Cancel bar,
            // with the privacy chip floating inside its top edge.
            let guideLeft = view.safeAreaInsets.left + L.guideMargin
            let guideTop = safeTop + L.navClearance
            let guideBottom = h - safeBottom - L.guideMargin
            guideRect = CGRect(x: guideLeft,
                               y: guideTop,
                               width: columnX - guideLeft - L.guideMargin,
                               height: max(160, guideBottom - guideTop))
        } else {
            // Bottom up: controls, count, instruction.
            let controlsCenterY = h - safeBottom - L.controlsBottomGap - L.controlsHeight / 2
            placeControls(centerX: w / 2, centerY: controlsCenterY)

            let countY = controlsCenterY - L.controlsHeight / 2 - L.gutter - L.countHeight
            countLabel.frame = CGRect(x: (w - L.countWidth) / 2, y: countY,
                                      width: L.countWidth, height: L.countHeight)

            let instructionWidth = w - 48
            let instructionY = countY - 12 - L.labelHeight
            instructionLabel.frame = CGRect(x: (w - instructionWidth) / 2, y: instructionY,
                                            width: instructionWidth, height: L.labelHeight)

            // The guide box is nearly the whole screen: from just under the
            // Cancel bar to just above the instruction, edge to edge. The
            // privacy chip floats inside its top edge.
            let guideTop = safeTop + L.navClearance
            let guideBottom = instructionY - L.guideMargin
            guideRect = CGRect(x: L.guideMargin,
                               y: guideTop,
                               width: w - L.guideMargin * 2,
                               height: max(160, guideBottom - guideTop))
        }

        guideLayer.frame = guideRect
        cornerLayer.path = cornerPath(in: guideRect).cgPath

        let roi = guideRectInVisionSpace()
        generationLock.lock()
        cachedROI = roi
        generationLock.unlock()
    }

    /// Proceed centred on a point, Retake to its left.
    private func placeControls(centerX: CGFloat, centerY: CGFloat) {
        shutter.frame = CGRect(x: centerX - L.proceedWidth / 2,
                               y: centerY - L.controlsHeight / 2,
                               width: L.proceedWidth, height: L.controlsHeight)
        retakeButton.frame = CGRect(x: shutter.frame.minX - 12 - L.retakeWidth,
                                    y: shutter.frame.minY,
                                    width: L.retakeWidth, height: L.controlsHeight)
    }

    // MARK: Count

    private func updateCount(_ n: Int) {
        guard n != lastReportedCount else { return }
        lastReportedCount = n
        countLabel.text = n == 1 ? "1 medication detected" : "\(n) medications detected"

        UIView.animate(withDuration: 0.12, animations: {
            self.countLabel.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
        }, completion: { _ in
            UIView.animate(withDuration: 0.12) { self.countLabel.transform = .identity }
        })
    }

    // MARK: Button feedback

    @objc private func shutterDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.08) {
            sender.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            sender.alpha = 0.75
        }
    }

    @objc private func shutterUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.12) {
            sender.transform = .identity
            sender.alpha = 1
        }
    }

    // MARK: Corners

    private func cornerPath(in r: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let len: CGFloat = 24
        path.move(to: CGPoint(x: r.minX, y: r.minY + len))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX + len, y: r.minY))
        path.move(to: CGPoint(x: r.maxX - len, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + len))
        path.move(to: CGPoint(x: r.maxX, y: r.maxY - len))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX - len, y: r.maxY))
        path.move(to: CGPoint(x: r.minX + len, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - len))
        return path
    }
}
