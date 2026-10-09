//
//  SectionExclusionTests.swift
//  PreOpCheckTests
//
//  Allergy lines must never reach the drug matcher, and medication lines
//  must always reach it, on both page layouts the app meets: the printed
//  visit summary (allergies at the bottom) and Epic's Medications screen
//  (allergies in the header, above the table). The Epic cases are the ones
//  the old "everything below the heading" rule got wrong.
//

import Testing
import CoreGraphics
@testable import PreOpCheck

struct SectionExclusionTests {

    /// A line one text-height tall whose top edge sits at `y` (Vision space,
    /// y up). `x` separates cells that share a row.
    private func line(_ text: String, y: CGFloat, x: CGFloat = 0.1) -> ScannedLine {
        ScannedLine(text: text, box: CGRect(x: x, y: y - 0.03, width: 0.4, height: 0.03))
    }

    private func excluded(_ text: String, in page: [ScannedLine]) -> Bool {
        let bands = SectionExclusion.bands(in: page)
        let target = page.first { $0.text == text }!
        return SectionExclusion.isExcluded(target.box, by: bands)
    }

    @Test("Printed summary: allergies at the bottom are excluded, medications above are not")
    func printedSummary() {
        let page = [
            line("Current Medications", y: 0.90),
            line("Lisinopril 10 mg tablet, once daily", y: 0.85),
            line("Omeprazole 20 mg capsule, every morning", y: 0.80),
            line("Allergies", y: 0.50),
            line("Codeine - nausea and vomiting", y: 0.45),
            line("Penicillin - rash", y: 0.40)
        ]
        #expect(!excluded("Lisinopril 10 mg tablet, once daily", in: page))
        #expect(!excluded("Omeprazole 20 mg capsule, every morning", in: page))
        #expect(excluded("Codeine - nausea and vomiting", in: page))
        #expect(excluded("Penicillin - rash", in: page))
    }

    @Test("Epic screen: the allergy field and tab at the top do not swallow the table")
    func epicMedicationsScreen() {
        let page = [
            line("Doe, John", y: 0.95),
            line("Allergies: Penicillin (rash)", y: 0.95, x: 0.6),
            line("Code Status: Full Code", y: 0.92, x: 0.6),
            line("Summary", y: 0.85, x: 0.05),
            line("Medications", y: 0.85, x: 0.35),
            line("Allergies", y: 0.85, x: 0.55),
            line("Medications", y: 0.78),
            line("Acetaminophen (Tylenol)", y: 0.70),
            line("acetaminophen 500 mg tablet", y: 0.67),
            line("Amlodipine (Norvasc)", y: 0.62),
            line("Vitamin D3", y: 0.20)
        ]
        #expect(excluded("Allergies: Penicillin (rash)", in: page))
        #expect(!excluded("Acetaminophen (Tylenol)", in: page))
        #expect(!excluded("acetaminophen 500 mg tablet", in: page))
        #expect(!excluded("Amlodipine (Norvasc)", in: page))
        #expect(!excluded("Vitamin D3", in: page))
    }

    @Test("Epic header split by colour: a bare 'Allergies:' still only covers the header")
    func epicHeaderSplitIntoTwoObservations() {
        let page = [
            line("Allergies:", y: 0.95, x: 0.6),
            line("Penicillin (rash)", y: 0.95, x: 0.75),
            line("Medications", y: 0.78),
            line("Losartan (Cozaar)", y: 0.70)
        ]
        #expect(excluded("Penicillin (rash)", in: page))
        #expect(!excluded("Losartan (Cozaar)", in: page))
    }

    @Test("An allergy section above the list ends at the medication heading")
    func allergySectionAboveList() {
        let page = [
            line("ALLERGIES AND ADVERSE REACTIONS", y: 0.90),
            line("Penicillin - rash", y: 0.85),
            line("Current Medications", y: 0.70),
            line("Metformin 500 mg tablet", y: 0.65)
        ]
        #expect(excluded("Penicillin - rash", in: page))
        #expect(!excluded("Metformin 500 mg tablet", in: page))
    }

    @Test("Medication headings", arguments: [
        ("Current Medications", true),
        ("Medications", true),
        ("Home Medications", true),
        ("Active", true),
        ("Inactive Medications", false),
        ("Discontinued Medications", false),
        ("Take this medication with food", false),
        ("Lisinopril 10 mg tablet, once daily", false)
    ])
    func medicationHeadings(_ c: (String, Bool)) {
        #expect(SectionExclusion.isMedicationHeading(c.0) == c.1, "\(c.0)")
    }

    @Test("Inline fields versus headings", arguments: [
        ("Allergies: Penicillin (rash)", true),
        ("Allergies:", false),
        ("Allergies", false),
        ("ALLERGIES AND ADVERSE REACTIONS", false)
    ])
    func inlineFields(_ c: (String, Bool)) {
        #expect(SectionExclusion.isInlineField(c.0) == c.1, "\(c.0)")
    }
}
