//
//  PatientIdentityTests.swift
//  PreOpCheckTests
//
//  The scanner blurs any line PatientIdentity flags. These pin down what it
//  must catch (names in every form a printout uses, dates, record numbers)
//  and what it must leave alone (medication lines, headings, the hospital).
//

import Testing
import CoreGraphics
@testable import PreOpCheck

struct PatientIdentityTests {

    @Test("Lines that identify the patient are flagged", arguments: [
        // Epic header, as in the screenshot Armaan supplied.
        "Doe, John",
        "MRN: 12345678   58 y.o.   M   01/01/1967   PCP: Smith, MD",
        "58 y.o.",
        // Printed visit summaries.
        "Patient: Jane Q. Sample     DOB: 03/14/2015     MRN: 4821937",
        "SAMPLE, JANE Q",
        "Nguyen, An",
        "Garcia-Lopez, Sofia M.",
        "O'Brien, Siobhan",
        "Jane Q. Sample",
        "Jane Q. Sample     Printed 10/09/2026     Page 1 of 1",
        "Name: SAMPLE, JANE",
        "Patient Name: SAMPLE, JANE Q",
        "DOB: 03/14/2015",
        "Date of Birth 3/14/2015",
        "MRN 4821937",
        "Sex: Female   Age: 11 y.o.",
        "Encounter Date: 10/02/2026",
        "Ordering provider: Dr. Maria Lopez",
        "Phone: 650-555-0199"
    ])
    func flagsIdentityLines(_ line: String) {
        #expect(PatientIdentity.isIdentityLine(line), "\(line) should be blurred")
    }

    @Test("Medication lines, headings and the institution are left alone", arguments: [
        // Epic table cells. Start dates and the provider column stay visible,
        // otherwise every row grows a blur bar.
        "Acetaminophen (Tylenol)",
        "acetaminophen 500 mg tablet",
        "Albuterol HFA (ProAir HFA)",
        "Vitamin D3",
        "cholecalciferol 1,000 unit tablet",
        "01/10/2024",
        "Smith, MD",
        "Every 6 hours as needed",
        "Once daily at bedtime",
        "Type 2 diabetes mellitus",
        "Allergies: Penicillin (rash)",
        "Code Status: Full Code",
        "Preferred Pharmacy: CVS #99999",
        // Printed visit summaries.
        "Lisinopril 10 mg tablet, once daily",
        "Ibuprofen 400 mg tablet, every 6 hours as needed",
        "Metoprolol succinate 25 mg, once daily",
        "Vitamin D3 1000 IU capsule, once daily",
        "Montelukast (Singulair) 5 mg chewable",
        "Albuterol HFA 90 mcg/actuation inhaler",
        "Take 1 tablet by mouth daily",
        "Current Medications",
        "Patient Medication List",
        "Allergies",
        "Codeine - nausea and vomiting",
        "Penicillin - rash",
        "Stanford Children's Health",
        "Lucile Packard Children's Hospital",
        "Pre-Anesthesia Visit Summary",
        "Printed Oct 9, 2026",
        "Page 1 of 2",
        "Discontinue",
        "Describe edits"
    ])
    func leavesMedicationLinesAlone(_ line: String) {
        #expect(!PatientIdentity.isIdentityLine(line), "\(line) should stay visible")
    }

    // MARK: Whole page

    private func cell(_ text: String, y: CGFloat, x: CGFloat) -> ScannedLine {
        ScannedLine(text: text, box: CGRect(x: x, y: y - 0.03, width: 0.15, height: 0.03))
    }

    @Test("Epic header split into cells: the birth date beside the MRN is blurred, row start dates are not")
    func birthDateBesideIdentityIsBlurred() {
        let page = [
            cell("Doe, John", y: 0.97, x: 0.1),
            cell("MRN: 12345678", y: 0.93, x: 0.1),
            cell("58 y.o.", y: 0.93, x: 0.3),
            cell("M", y: 0.93, x: 0.4),
            cell("01/01/1967", y: 0.93, x: 0.5),
            cell("PCP: Smith, MD", y: 0.93, x: 0.7),
            cell("Acetaminophen (Tylenol)", y: 0.70, x: 0.1),
            cell("01/10/2024", y: 0.70, x: 0.6),
            cell("Smith, MD", y: 0.70, x: 0.8)
        ]
        let blurred = PatientIdentity.identityLines(in: page)
        func isBlurred(_ text: String) -> Bool {
            blurred.contains(page.first { $0.text == text }!.box)
        }
        #expect(isBlurred("Doe, John"))
        #expect(isBlurred("MRN: 12345678"))
        #expect(isBlurred("01/01/1967"))
        #expect(!isBlurred("Acetaminophen (Tylenol)"))
        #expect(!isBlurred("01/10/2024"))
        #expect(!isBlurred("Smith, MD"))
    }
}
