//
//  MedicationLineCues.swift
//  PreOpCheck
//
//  Cheap tests for "does this line look like a medication entry?" used by the
//  scanner when deciding what to mark on screen. Two shapes turn up:
//
//    Printed list:  "Lisinopril 10 mg tablet, once daily"       dose on the line
//    Epic table:    "Acetaminophen (Tylenol)"                   title line
//                   "acetaminophen 500 mg tablet"               detail line under it
//
//  The FDA product list the scanner uses for red markers contains products
//  literally named "Allergies", "Full", "Cool" and "Classic", so a name in
//  that list is only marked red when the line has medication context: a
//  dose or form word on it, or a detail line directly underneath.
//

import CoreGraphics
import Foundation

enum MedicationLineCues {

    /// Strengths and forms. Any one of these on a line is a dose cue.
    static let doseWords: Set<String> = [
        "mg", "mcg", "g", "ml", "unit", "units", "iu", "meq", "tablet", "tablets", "capsule",
        "capsules", "spray", "sprays", "puff", "puffs", "patch", "solution", "suspension",
        "injection", "inhaler", "actuation", "drops", "cream", "ointment", "chewable", "syrup",
        "lozenge"
    ]

    static func hasDoseWord(_ text: String) -> Bool {
        let words = Set(DrugMatcher.normalize(text).split(separator: " ").map(String.init))
        return !words.isDisjoint(with: doseWords)
    }

    /// Epic prints a detail line under each drug: lowercase, with a strength
    /// and a form ("acetaminophen 500 mg tablet"). Both cues are required, so
    /// a one-line printed list that happens to be lowercase is not affected.
    static func looksLikeDetailLine(_ text: String) -> Bool {
        text.first?.isLowercase == true && hasDoseWord(text)
    }

    /// True when `line` sits directly under one of `lines`: within about one
    /// and a half line heights. Vision's y axis points up, so "below" means
    /// a smaller y.
    static func isDirectlyBelow(_ line: CGRect, _ lines: [CGRect]) -> Bool {
        lines.contains { above in
            let gap = above.minY - line.maxY
            return gap > -line.height * 0.3 && gap < line.height * 1.5
        }
    }

    /// A dose cue on the line itself, or on the line directly under it.
    static func hasMedicationContext(text: String, box: CGRect, in lines: [ScannedLine]) -> Bool {
        if hasDoseWord(text) { return true }
        return lines.contains { isDirectlyBelow($0.box, [box]) && hasDoseWord($0.text) }
    }
}
