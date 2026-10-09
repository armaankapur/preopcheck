//
//  SectionExclusion.swift
//  PreOpCheck
//
//  Which parts of a scanned page are NOT the medication list. Text under an
//  "Allergies" (or similar) heading is kept away from the drug matcher, so
//  "Codeine - nausea" is never reported as an active medication.
//
//  Two layouts are handled:
//  - Printed visit summaries put allergies after the medications. The
//    excluded band runs from the heading to the bottom of the page.
//  - Epic's Medications screen puts "Allergies: Penicillin (rash)" and an
//    "Allergies" tab at the top, above the table. A heading with a value on
//    the same line excludes only itself, and a band ends at the next
//    medication heading, so the table below is still read.
//
//  Coordinates are Vision's: normalised, y pointing up, so "below" means a
//  smaller y.
//

import CoreGraphics
import Foundation

enum SectionExclusion {

    /// Headings that start a section which is not an active medication list.
    static let excludedHeadings = [
        "allerg",              // ALLERGIES, ALLERGIES AND ADVERSE REACTIONS
        "adverse reaction",
        "intolerance",
        "contraindication",
        "discontinued",
        "inactive medication",
        "past medication"
    ]

    /// Short headings that start a medication list and so end an excluded
    /// band. `excludedHeadings` is checked first, so "Inactive Medications"
    /// is not mistaken for one.
    static let medicationHeadings = ["medication", "prescription", "meds", "active"]

    /// A vertical slice of the page to ignore, from `top` down to `bottom`.
    struct Band: Equatable {
        let top: CGFloat
        let bottom: CGFloat

        func contains(_ y: CGFloat) -> Bool {
            y <= top && y > bottom
        }
    }

    /// The parts of the page to ignore, given every line in the guide box.
    static func bands(in lines: [ScannedLine]) -> [Band] {
        let topFirst = lines.sorted { $0.box.maxY > $1.box.maxY }
        var bands: [Band] = []

        for (i, line) in topFirst.enumerated() where isExcludedHeading(line.text) {
            if isInlineField(line.text) {
                // "Allergies: Penicillin (rash)" is a field, not a section.
                bands.append(Band(top: line.box.maxY, bottom: line.box.minY))
                continue
            }
            // A section runs to the next medication heading below it, or to
            // the bottom of the page when there is none.
            let nextMedicationHeading = topFirst[(i + 1)...].first { isMedicationHeading($0.text) }
            bands.append(Band(top: line.box.maxY, bottom: nextMedicationHeading?.box.maxY ?? -1))
        }
        return bands
    }

    static func isExcluded(_ box: CGRect, by bands: [Band]) -> Bool {
        bands.contains { $0.contains(box.midY) }
    }

    // MARK: Line classification

    static func isExcludedHeading(_ text: String) -> Bool {
        let lower = text.lowercased()
        return excludedHeadings.contains { lower.contains($0) }
    }

    static func isMedicationHeading(_ text: String) -> Bool {
        guard !isExcludedHeading(text) else { return false }
        let lower = text.lowercased()
        let words = lower.split { !$0.isLetter }.map(String.init)
        // Headings are short. "Take this medication with food" is a sentence.
        guard (1...4).contains(words.count) else { return false }
        // Whole words only, so "Inactive" does not pass as "active".
        // A prefix match lets "medication" cover "medications".
        return words.contains { word in medicationHeadings.contains { word.hasPrefix($0) } }
    }

    /// "Allergies: Penicillin (rash)" has its value on the same line, so it
    /// cannot be the start of a section. A bare "ALLERGIES:" is a heading.
    static func isInlineField(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        return text[text.index(after: colon)...].contains { !$0.isWhitespace }
    }
}
