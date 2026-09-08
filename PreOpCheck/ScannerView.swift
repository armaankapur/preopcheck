//
//  ScannerView.swift
//  Stanford Preoperative Medication
//
//  Two changes in this revision:
//
//  1. SECTION AWARENESS. The matcher previously matched drug names anywhere
//     inside the guide box, including under an "Allergies" heading. On a test
//     document listing "Codeine - nausea and vomiting" as an allergy, codeine
//     was reported as an active medication. That is wrong in a clinically
//     dangerous direction. Text at or below a recognized allergy heading is
//     now excluded before matching.
//
//  2. LAYOUT. All chrome is now positioned in viewDidLayoutSubviews against
//     the safe area rather than hardcoded in viewDidLoad, so spacing is
//     consistent and adapts across devices. The guide box sizes itself to the
//     space left between the top indicator and the bottom controls instead of
//     being a fixed fraction of screen height.
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
                if m.matchKind > existing.matchKind { best[m.id] = m }
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

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let cameraQueue = DispatchQueue(label: "com.stanford.preop.camera")

    private let state = ScanState()

    // Chrome
    private var guideRect: CGRect = .zero
    private let guideLayer = CALayer()
    private let cornerLayer = CAShapeLayer()
    private let lockChip = UIView()
    private let lockIcon = UIImageView(image: UIImage(systemName: "lock.fill"))
    private let lockText = UILabel()
    private let instructionLabel = UILabel()
    private let countLabel = UILabel()
    private let shutterRing = UIView()
    private let shutter = UIButton(type: .custom)

    private var lastReportedCount = -1

    private var frameGeneration = 0
    private let generationLock = NSLock()

    private var lastProcessTime = Date.distantPast
    private let minFrameInterval: TimeInterval = 0.3

    private let stanfordRed = UIColor(red: 0.549, green: 0.082, blue: 0.082, alpha: 1)

    // Layout constants, one place.
    private enum L {
        static let chipHeight: CGFloat = 28
        static let chipTopGap: CGFloat = 54     // below the safe area / nav bar
        static let gutter: CGFloat = 22         // vertical rhythm
        static let labelHeight: CGFloat = 36
        static let countHeight: CGFloat = 36
        static let countWidth: CGFloat = 236
        static let shutterDiameter: CGFloat = 68
        static let ringDiameter: CGFloat = 82
        static let shutterBottomGap: CGFloat = 34
        static let guideWidthFraction: CGFloat = 0.88
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        buildChrome()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        layoutChrome()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraQueue.async { [weak self] in self?.captureSession.stopRunning() }
    }

    // MARK: Camera

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
        output.setSampleBufferDelegate(self, queue: cameraQueue)
        if captureSession.canAddOutput(output) { captureSession.addOutput(output) }

        if let connection = output.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        captureSession.commitConfiguration()

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        cameraQueue.async { [weak self] in self?.captureSession.startRunning() }
    }

    // MARK: Coordinates

    private func guideRectInVisionSpace() -> CGRect {
        guard let preview = previewLayer, guideRect != .zero else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let meta = preview.metadataOutputRectConverted(fromLayerRect: guideRect)
        return CGRect(x: meta.minX, y: 1 - meta.maxY, width: meta.width, height: meta.height)
    }

    // MARK: Capture output

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) > minFrameInterval else { return }
        lastProcessTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        generationLock.lock()
        frameGeneration += 1
        let generation = frameGeneration
        generationLock.unlock()

        let roi = guideRectInVisionSpace()

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

    // MARK: Section exclusion

    /// Headings that mark the start of a non-medication section. Anything at or
    /// below one of these is not an active medication list.
    private static let excludedSectionHeadings = [
        "allerg",              // ALLERGIES, ALLERGIES AND ADVERSE REACTIONS
        "adverse reaction",
        "intolerance",
        "contraindication",
        "discontinued",
        "inactive medication",
        "past medication"
    ]

    /// Returns the Vision-space y coordinate of the topmost excluded heading,
    /// or nil if none is present. Vision's y increases upward, so anything with
    /// a lower y than this sits visually below the heading.
    ///
    /// Limitation worth knowing: this assumes the allergy block appears below
    /// the medication table, which is the standard layout in every EHR printout
    /// I have seen. A document that puts allergies above the med list would
    /// have its medications excluded. If that turns up in practice, the fix is
    /// to bound the excluded band at the next section heading rather than
    /// running it to the bottom of the page.
    private func exclusionBoundary(in observations: [VNRecognizedTextObservation],
                                   roi: CGRect) -> CGFloat? {
        var boundary: CGFloat?

        for obs in observations {
            guard roi.intersects(obs.boundingBox) else { continue }
            guard let text = obs.topCandidates(1).first?.string else { continue }

            let lower = text.lowercased()
            let isHeading = ScannerViewController.excludedSectionHeadings.contains {
                lower.contains($0)
            }
            guard isHeading else { continue }

            // Take the highest one on the page, so a later heading cannot
            // reopen a section an earlier one closed.
            let y = obs.boundingBox.maxY
            if boundary == nil || y > boundary! { boundary = y }
        }
        return boundary
    }

    // MARK: Recognition handling

    private func handle(observations: [VNRecognizedTextObservation],
                        roi: CGRect,
                        generation: Int) {

        generationLock.lock()
        let isCurrent = generation == frameGeneration
        generationLock.unlock()
        guard isCurrent else { return }

        let boundary = exclusionBoundary(in: observations, roi: roi)
        var frameMatches: [String: DrugMatch] = [:]

        for obs in observations {
            guard roi.intersects(obs.boundingBox) else { continue }

            // Skip the heading itself and everything visually below it.
            if let boundary, obs.boundingBox.midY <= boundary { continue }

            guard let candidate = obs.topCandidates(1).first else { continue }

            let tokens = candidate.string
                .split(separator: " ")
                .map { OCRToken(text: String($0),
                                box: obs.boundingBox,
                                ocrConfidence: candidate.confidence) }

            for match in DrugMatcher.shared.match(tokens) {
                if let existing = frameMatches[match.id] {
                    frameMatches[match.id] = match.matchKind > existing.matchKind ? match : existing
                } else {
                    frameMatches[match.id] = match
                }
            }
        }

        // Non-drug text is never retained. There is no discard step because it
        // never leaves this function.
        state.record(Array(frameMatches.values))
        let stableCount = state.stableMatches().count

        DispatchQueue.main.async { [weak self] in
            self?.updateCount(stableCount)
        }
    }

    // MARK: Capture

    @objc private func captureNow() {
        let matches = state.stableMatches()

        guard !matches.isEmpty else {
            let alert = UIAlertController(
                title: "No medications detected",
                message: "Hold the camera steady and make sure the medication list fills the box.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        cameraQueue.async { [weak self] in self?.captureSession.stopRunning() }
        delegate?.didDetectMedications(matches)
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
        lockText.font = .systemFont(ofSize: 12, weight: .medium)
        lockChip.addSubview(lockText)

        // Instruction
        instructionLabel.text = "Fill the box with the medication list"
        instructionLabel.textColor = .white
        instructionLabel.font = .systemFont(ofSize: 15, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        instructionLabel.layer.cornerRadius = L.labelHeight / 2
        instructionLabel.layer.masksToBounds = true
        view.addSubview(instructionLabel)

        // Count
        countLabel.text = "0 medications detected"
        countLabel.textColor = .white
        countLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        countLabel.textAlignment = .center
        countLabel.backgroundColor = stanfordRed.withAlphaComponent(0.92)
        countLabel.layer.cornerRadius = L.countHeight / 2
        countLabel.layer.masksToBounds = true
        view.addSubview(countLabel)

        // Shutter
        shutterRing.layer.cornerRadius = L.ringDiameter / 2
        shutterRing.layer.borderColor = UIColor.white.cgColor
        shutterRing.layer.borderWidth = 3.5
        shutterRing.isUserInteractionEnabled = false
        view.addSubview(shutterRing)

        shutter.layer.cornerRadius = L.shutterDiameter / 2
        shutter.backgroundColor = .white
        shutter.accessibilityLabel = "Capture and analyze"
        shutter.addTarget(self, action: #selector(shutterDown), for: .touchDown)
        shutter.addTarget(self, action: #selector(shutterUp),
                          for: [.touchUpInside, .touchUpOutside, .touchCancel])
        shutter.addTarget(self, action: #selector(captureNow), for: .touchUpInside)
        view.addSubview(shutter)
    }

    // MARK: Chrome layout

    /// Everything is positioned from the safe area outward, in a single pass,
    /// so the spacing is consistent and the guide box takes whatever vertical
    /// room is left rather than a fixed fraction of the screen.
    private func layoutChrome() {
        let w = view.bounds.width
        let h = view.bounds.height
        let safeTop = view.safeAreaInsets.top
        let safeBottom = view.safeAreaInsets.bottom

        // Bottom up: shutter, count, instruction.
        let shutterCenterY = h - safeBottom - L.shutterBottomGap - L.ringDiameter / 2
        shutterRing.frame = CGRect(x: (w - L.ringDiameter) / 2,
                                   y: shutterCenterY - L.ringDiameter / 2,
                                   width: L.ringDiameter, height: L.ringDiameter)
        shutter.frame = CGRect(x: (w - L.shutterDiameter) / 2,
                               y: shutterCenterY - L.shutterDiameter / 2,
                               width: L.shutterDiameter, height: L.shutterDiameter)

        let countY = shutterRing.frame.minY - L.gutter - L.countHeight
        countLabel.frame = CGRect(x: (w - L.countWidth) / 2, y: countY,
                                  width: L.countWidth, height: L.countHeight)

        let instructionWidth = w - 48
        let instructionY = countY - 12 - L.labelHeight
        instructionLabel.frame = CGRect(x: (w - instructionWidth) / 2, y: instructionY,
                                        width: instructionWidth, height: L.labelHeight)

        // Top down: privacy chip.
        lockText.sizeToFit()
        let chipWidth = 12 + 12 + 7 + lockText.bounds.width + 14
        let chipY = safeTop + L.chipTopGap
        lockChip.frame = CGRect(x: (w - chipWidth) / 2, y: chipY,
                                width: chipWidth, height: L.chipHeight)
        lockIcon.frame = CGRect(x: 12, y: (L.chipHeight - 14) / 2, width: 12, height: 14)
        lockText.frame = CGRect(x: 12 + 12 + 7, y: 0,
                                width: lockText.bounds.width, height: L.chipHeight)

        // The guide box fills what's left between the two.
        let guideWidth = w * L.guideWidthFraction
        let guideTop = lockChip.frame.maxY + L.gutter
        let guideBottom = instructionY - L.gutter
        guideRect = CGRect(x: (w - guideWidth) / 2,
                           y: guideTop,
                           width: guideWidth,
                           height: max(160, guideBottom - guideTop))

        guideLayer.frame = guideRect
        cornerLayer.path = cornerPath(in: guideRect).cgPath
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

    // MARK: Shutter feedback

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
