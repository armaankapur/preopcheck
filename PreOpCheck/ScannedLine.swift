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
