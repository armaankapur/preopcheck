//
//  PatientIdentityTests.swift
//  PreOpCheckTests
//
//  The scanner blurs any line PatientIdentity flags. These pin down what it
//  must catch (names in every form a printout uses, dates, record numbers)
//  and what it must leave alone (medication lines, headings, the hospital).
//

import Testing
@testable import PreOpCheck

struct PatientIdentityTests {

    @Test("Lines that identify the patient are flagged", arguments: [
        "Patient: Jane Q. Sample     DOB: 03/14/2015     MRN: 4821937",
        "SAMPLE, JANE Q",
        "Nguyen, An",
        "Garcia-Lopez, Sofia M.",
        "O'Brien, Siobhan",
        "Jane Q. Sample",
        "Name: SAMPLE, JANE",
        "Patient Name: SAMPLE, JANE Q",
        "DOB: 03/14/2015",
        "Date of Birth 3/14/2015",
        "MRN 4821937",
        "Sex: Female   Age: 11 y.o.",
        "Encounter Date: 10/02/2026",
        "Ordering provider: Dr. Maria Lopez",
        "Phone: 650-555-0199",
        "Printed Oct 9, 2026"
    ])
    func flagsIdentityLines(_ line: String) {
        #expect(PatientIdentity.isIdentityLine(line), "\(line) should be blurred")
    }

    @Test("Medication lines, headings and the institution are left alone", arguments: [
        "Lisinopril 10 mg tablet, once daily",
        "Ibuprofen 400 mg tablet, every 6 hours as needed",
        "Metoprolol succinate 25 mg, once daily",
        "Vitamin D3 1000 IU capsule, once daily",
        "Montelukast (Singulair) 5 mg chewable",
        "Albuterol HFA 90 mcg/actuation inhaler",
        "acetaminophen 500 mg tablet",
        "Take 1 tablet by mouth daily",
        "Current Medications",
        "Patient Medication List",
        "Allergies",
        "Codeine - nausea and vomiting",
        "Penicillin - rash",
        "Stanford Children's Health",
        "Lucile Packard Children's Hospital",
        "Pre-Anesthesia Visit Summary",
        "Page 1 of 2",
        "Discontinue",
        "Describe edits"
    ])
    func leavesMedicationLinesAlone(_ line: String) {
        #expect(!PatientIdentity.isIdentityLine(line), "\(line) should stay visible")
    }
}
