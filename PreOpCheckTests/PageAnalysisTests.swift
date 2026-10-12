//
//  PageAnalysisTests.swift
//  PreOpCheckTests
//
//  Whole-page checks: a picture of a medication list goes through Apple's
//  text recognition and then PageAnalysis, exactly as a camera frame would,
//  and the test states which drugs must come out green, which red, and
//  which lines must be blurred. Fixture images live in PreOpCheckTests/
//  Fixtures and contain made-up patients only.
//
//  Vision's output can differ slightly between simulator runtimes, so the
//  checks are about the right lines, not pixel-exact boxes.
//

import Testing
import UIKit
import Vision
@testable import PreOpCheck

private final class FixtureBundleToken {}

struct PageAnalysisTests {

    // MARK: Running a picture through the pipeline

    /// A camera frame is at least this wide. Small screenshots are scaled up
    /// to match, because recognition drops 9-pixel text that it reads fine
    /// at camera size; a 746-pixel dashboard lost "Losartan (Cozaar)".
    private static let cameraLikeWidth: CGFloat = 1600

    private func fixture(_ name: String) throws -> CGImage {
        let bundle = Bundle(for: FixtureBundleToken.self)
        let url = try #require(bundle.url(forResource: name, withExtension: "png"),
                               "missing fixture \(name).png")
        let image = try #require(UIImage(contentsOfFile: url.path))
        guard image.size.width < PageAnalysisTests.cameraLikeWidth else {
            return try #require(image.cgImage)
        }
        let scale = PageAnalysisTests.cameraLikeWidth / image.size.width
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let scaled = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return try #require(scaled.cgImage)
    }

    private func analyze(_ image: CGImage) throws -> (analysis: PageAnalysis, lines: [RecognizedLine]) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.012
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let lines = PageAnalysis.lines(from: request.results ?? [])
        return (PageAnalysis.analyze(lines), lines)
    }

    /// Generic names of the green drugs, lowercased.
    private func greenGenerics(_ a: PageAnalysis) -> [String] {
        a.green.compactMap { MedicationDatabase.byID[$0.key]?.generic.lowercased() }
    }

    private func redIngredients(_ a: PageAnalysis) -> Set<String> {
        Set(a.red.map { $0.key.replacingOccurrences(of: "red:", with: "") })
    }

    /// Text of every line whose box is in the blur list.
    private func blurredTexts(_ a: PageAnalysis, _ lines: [RecognizedLine]) -> [String] {
        lines.filter { line in a.redactions.contains(line.box) }.map(\.text)
    }

    // MARK: Epic Medications screen

    @Test("Epic screen: the table is read, PARC drugs green, the rest red")
    func epicScreenMarkers() throws {
        let (a, _) = try analyze(fixture("epic-medications"))
        let green = greenGenerics(a)
        let red = redIngredients(a)

        // Every drug on the screen is either green or red, never missed.
        for drug in ["acetaminophen", "amlodipine", "atorvastatin", "losartan", "metformin",
                     "omeprazole", "sertraline", "albuterol", "fluticasone"] {
            let seen = green.contains { $0.contains(drug) } || red.contains { $0.contains(drug) }
            #expect(seen, "\(drug) should be marked green or red")
        }
        // Vitamin D3 reaches the scanner through its detail line's ingredient.
        #expect(green.contains { $0.contains("vitamin d") } || red.contains("cholecalciferol"),
                "Vitamin D3 should be marked")
        // Plain words that are also FDA product names must not go red.
        #expect(!red.contains("allergies"))
        #expect(!red.contains("full"))
    }

    @Test("Epic screen: only the patient header is blurred")
    func epicScreenBlur() throws {
        let (a, lines) = try analyze(fixture("epic-medications"))
        let blurred = blurredTexts(a, lines)

        #expect(blurred.contains { $0.hasPrefix("Doe, John") })
        #expect(blurred.contains { $0.contains("MRN") })
        #expect(blurred.contains { $0.contains("01/01/1967") })
        // The provider column and the start-date column stay visible.
        #expect(!blurred.contains { $0 == "Smith, MD" }, "clinician cells must not blur")
        #expect(!blurred.contains { $0.contains("/2023") || $0.contains("/2024") },
                "medication start dates must not blur")
        #expect(!blurred.contains("GERD"))
        #expect(a.redactions.allSatisfy { $0.midY > 0.85 },
                "every blurred line should be in the header, got \(blurred)")
    }

    // MARK: Other systems, one test per layout

    /// What a fixture must produce. `drugs` must each be marked green or red.
    /// None of these screens shows a real patient, so nothing may be blurred.
    struct Fixture {
        let name: String
        let drugs: [String]
    }

    static let otherSystems: [Fixture] = [
        // Drugs grouped under indication headings, with a detail side panel.
        Fixture(name: "careview-grouped",
                drugs: ["acetaminophen", "amlodipine", "losartan", "atorvastatin", "metformin"]),
        // Two side-by-side tables; the dose sits in its own column.
        Fixture(name: "medrec-reconciliation",
                drugs: ["acetaminophen", "amlodipine", "atorvastatin", "metformin", "omeprazole",
                        "fluticasone", "sertraline", "albuterol", "losartan", "vitamin d"]),
        // Epic-like table from another vendor, Allergies tab at the top.
        Fixture(name: "healthsuite-table",
                drugs: ["acetaminophen", "amlodipine", "atorvastatin", "losartan", "metformin",
                        "omeprazole", "sertraline", "albuterol", "fluticasone", "vitamin d"])
    ]

    @Test("Other systems: every drug marked, nothing blurred", arguments: otherSystems)
    func otherSystem(_ fixture: Fixture) throws {
        let (a, lines) = try analyze(try self.fixture(fixture.name))
        let green = greenGenerics(a)
        let red = redIngredients(a)
        // Every recognised line goes into the message, so a failure shows
        // exactly what the recogniser read.
        let report = "green \(green.sorted()), red \(red.sorted()), blurred \(blurredTexts(a, lines)). "
            + "Lines read: \(lines.sorted { $0.box.maxY > $1.box.maxY }.map(\.text))"

        func isExpected(_ name: String) -> Bool {
            // Vitamin D3 reaches the red list through its ingredient name.
            fixture.drugs.contains { name.contains($0) } || (name == "cholecalciferol" && fixture.drugs.contains("vitamin d"))
        }
        for drug in fixture.drugs {
            let seen = green.contains { $0.contains(drug) } || red.contains { $0.contains(drug) }
                || (drug == "vitamin d" && red.contains("cholecalciferol"))
            #expect(seen, "\(fixture.name): \(drug) should be marked. \(report)")
        }
        // Nothing else may be marked: no stray red on "Oral", "Active" or "Pain".
        let stray = (green + Array(red)).filter { !isExpected($0) }
        #expect(stray.isEmpty, "\(fixture.name): stray marks \(stray). \(report)")
        #expect(a.redactions.isEmpty, "\(fixture.name): nothing to blur on a training record. \(report)")
    }

    // MARK: Marker boxes

    private func token(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> OCRToken {
        OCRToken(text: text, box: CGRect(x: x, y: y, width: width, height: 0.03), ocrConfidence: 1)
    }

    private func line(_ tokens: [OCRToken]) -> RecognizedLine {
        let box = tokens.dropFirst().reduce(tokens[0].box) { $0.union($1.box) }
        return RecognizedLine(text: tokens.map(\.text).joined(separator: " "), box: box, tokens: tokens)
    }

    @Test("The marker covers the brand in brackets: after a form tag, after a two-word name, or in its own cell")
    func markerCoversBracketedBrand() {
        // "Albuterol HFA (ProAir HFA)|" with a table border stuck to the bracket.
        let albuterol = line([token("Albuterol", x: 0.10, y: 0.80, width: 0.10),
                              token("HFA", x: 0.21, y: 0.80, width: 0.04),
                              token("(ProAir", x: 0.26, y: 0.80, width: 0.07),
                              token("HFA)|", x: 0.34, y: 0.80, width: 0.05)])
        // Two-word name, then the brand.
        let metoprolol = line([token("Metoprolol", x: 0.10, y: 0.70, width: 0.11),
                               token("succinate", x: 0.22, y: 0.70, width: 0.09),
                               token("(Toprol", x: 0.32, y: 0.70, width: 0.07),
                               token("XL)", x: 0.40, y: 0.70, width: 0.04)])
        // Name and brand recognised as two cells on one row, detail line under.
        let acetaminophen = line([token("Acetaminophen", x: 0.10, y: 0.60, width: 0.14)])
        let tylenol = line([token("(Tylenol)", x: 0.25, y: 0.60, width: 0.08)])
        let detail = line([token("acetaminophen", x: 0.10, y: 0.57, width: 0.13),
                           token("500", x: 0.24, y: 0.57, width: 0.03),
                           token("mg", x: 0.28, y: 0.57, width: 0.02),
                           token("tablet", x: 0.31, y: 0.57, width: 0.05)])

        let a = PageAnalysis.analyze([tylenol, albuterol, detail, metoprolol, acetaminophen])

        func greenBox(_ generic: String) -> CGRect? {
            a.green.first { MedicationDatabase.byID[$0.key]?.generic.lowercased().contains(generic) == true }?.box
        }
        #expect(greenBox("albuterol")?.maxX ?? 0 > 0.38, "albuterol box should reach the end of (ProAir HFA)")
        #expect(greenBox("metoprolol")?.maxX ?? 0 > 0.43, "metoprolol box should reach the end of (Toprol XL)")
        let acet = a.red.first { $0.key == "red:acetaminophen" }?.box
        #expect(acet?.minX ?? 1 < 0.11 && acet?.maxX ?? 0 > 0.32,
                "acetaminophen box should span the name and the (Tylenol) cell, got \(String(describing: acet))")
    }

    // MARK: Simulator sample page

    @Test("Sample page: header blurred, allergies ignored, table marked")
    func samplePage() throws {
        let image = try #require(ScannerViewController.renderSamplePage().cgImage)
        let (a, lines) = try analyze(image)
        let blurred = blurredTexts(a, lines)
        let red = redIngredients(a)
        let green = greenGenerics(a)

        #expect(blurred.contains { $0.hasPrefix("Doe, John") })
        #expect(blurred.contains { $0.contains("MRN") })
        let footer = lines.filter { $0.box.midY < 0.25 }.map(\.text)
        // Recognition may drop the space after the initial ("John Q.Doe").
        #expect(blurred.contains { $0.contains("Doe") && $0.contains("Printed") },
                "footer name should blur; footer read as \(footer), blurred \(blurred)")
        #expect(!blurred.contains { $0 == "Smith, MD" })

        // Allergies are never marked, in either colour.
        #expect(!red.contains("codeine") && !green.contains { $0.contains("codeine") })
        #expect(!red.contains("penicillin") && !green.contains { $0.contains("penicillin") })

        // The table is marked.
        #expect(green.count + red.count >= 8, "expected most of the 10 rows marked, got \(green) / \(red)")
    }
}
