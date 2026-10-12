//
//  ScannedLine.swift
//  PreOpCheck
//
//  One line of recognised text and where it sits on the page, in Vision's
//  normalised coordinates (0 to 1, y pointing up). The page-level rules
//  (allergy section, privacy blur, medication context) all need to reason
//  about a line's neighbours, so they share this one shape.
//

import CoreGraphics

struct ScannedLine {
    let text: String
    let box: CGRect
}

// Two small judgements the page rules keep needing. They live here so the
// rules agree on what "same row" and "has a value" mean.

extension CGRect {
    /// Two boxes on the same printed row: centres within about half a line.
    /// Tables come out of recognition as one box per cell, so a drug name
    /// and its dose, or an MRN and a birth date, are neighbours, not one line.
    func sharesRow(with other: CGRect) -> Bool {
        abs(midY - other.midY) < max(height, other.height) * 0.6
    }
}

extension String {
    /// "Allergies: Penicillin (rash)" has one; "Allergies:" and the column
    /// header "Ordering Provider :" (the sort arrow read as a colon) do not.
    var hasValueAfterColon: Bool {
        guard let colon = firstIndex(of: ":") else { return false }
        return self[index(after: colon)...].contains { !$0.isWhitespace }
    }
}
