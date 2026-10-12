//
//  MedicationLineCuesTests.swift
//  PreOpCheckTests
//
//  A word from the FDA product list only earns a red marker on a line that
//  looks like a medication entry. These pin down the two real shapes (a
//  printed one-liner with the dose on it, an Epic title with its detail line
//  underneath) and the headings and table labels that must never qualify.
//

import Testing
import CoreGraphics
@testable import PreOpCheck

struct MedicationLineCuesTests {

    private func line(_ text: String, y: CGFloat) -> ScannedLine {
        ScannedLine(text: text, box: CGRect(x: 0.1, y: y - 0.03, width: 0.4, height: 0.03))
    }

    private func hasContext(_ text: String, in page: [ScannedLine]) -> Bool {
        let target = page.first { $0.text == text }!
        return MedicationLineCues.hasMedicationContext(text: text, box: target.box, in: page)
    }

    @Test("Epic: a title line qualifies through the detail line under it; headings do not")
    func epicTable() {
        let page = [
            line("Allergies: Penicillin (rash)", y: 0.95),
            line("Allergies", y: 0.85),
            line("Medications", y: 0.78),
            line("Acetaminophen (Tylenol)", y: 0.70),
            line("acetaminophen 500 mg tablet", y: 0.67),
            line("Vitamin D3", y: 0.40),
            line("cholecalciferol 1,000 unit tablet", y: 0.37),
            line("Code Status: Full Code", y: 0.20)
        ]
        #expect(hasContext("Acetaminophen (Tylenol)", in: page))
        #expect(hasContext("acetaminophen 500 mg tablet", in: page))
        #expect(hasContext("Vitamin D3", in: page))
        #expect(!hasContext("Allergies", in: page))
        #expect(!hasContext("Allergies: Penicillin (rash)", in: page))
        #expect(!hasContext("Medications", in: page))
        #expect(!hasContext("Code Status: Full Code", in: page))
    }

    @Test("Printed list: the dose on the line is enough; a heading two lines above a dose is not")
    func printedList() {
        let page = [
            line("Current Medications", y: 0.90),
            line("Lisinopril 10 mg tablet, once daily", y: 0.80),
            line("Albuterol HFA 2 puffs every 4 hours as needed", y: 0.75),
            line("Allergies", y: 0.50),
            line("Codeine - nausea and vomiting", y: 0.45)
        ]
        #expect(hasContext("Lisinopril 10 mg tablet, once daily", in: page))
        #expect(hasContext("Albuterol HFA 2 puffs every 4 hours as needed", in: page))
        #expect(!hasContext("Current Medications", in: page))
        #expect(!hasContext("Allergies", in: page))
        #expect(!hasContext("Codeine - nausea and vomiting", in: page))
    }

    @Test("Table with a Dose column: the dose cell on the same row is context")
    func doseColumn() {
        func cell(_ text: String, y: CGFloat, x: CGFloat) -> ScannedLine {
            ScannedLine(text: text, box: CGRect(x: x, y: y - 0.03, width: 0.15, height: 0.03))
        }
        let page = [
            cell("Medication", y: 0.80, x: 0.1), cell("Dose", y: 0.80, x: 0.4), cell("Frequency", y: 0.80, x: 0.6),
            cell("Acetaminophen", y: 0.70, x: 0.1), cell("500 mg", y: 0.70, x: 0.4), cell("q6h PRN", y: 0.70, x: 0.6),
            cell("Vitamin D3", y: 0.60, x: 0.1), cell("1,000 units", y: 0.60, x: 0.4), cell("Daily", y: 0.60, x: 0.6),
            cell("Reconciled", y: 0.50, x: 0.1)
        ]
        #expect(hasContext("Acetaminophen", in: page))
        #expect(hasContext("Vitamin D3", in: page))
        #expect(!hasContext("Medication", in: page))
        #expect(!hasContext("Reconciled", in: page))
    }

    @Test("Detail lines", arguments: [
        ("acetaminophen 500 mg tablet", true),
        ("albuterol 90 mcg/actuation inhaler", true),
        ("fluticasone 50 mcg/actuation nasal spray", true),
        ("Acetaminophen (Tylenol)", false),      // title case
        ("once daily", false)                    // lowercase but no dose
    ])
    func detailLines(_ c: (String, Bool)) {
        #expect(MedicationLineCues.looksLikeDetailLine(c.0) == c.1, "\(c.0)")
    }
}
