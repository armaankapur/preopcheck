//
//  Theme.swift
//  PreOpCheck
//
//  Created by Timo on 4/27/26.
//
import SwiftUI

extension Color {
    static let stanford = Color(hex: "#8C1515")
    static let stanfordGrey = Color(hex: "#4D4F53")
    static let stanfordLight = Color(hex: "#F4F4F4")

    // Fixed text colors. These do not adapt to dark mode, because the app
    // draws explicit white cards everywhere. Using .primary and .secondary
    // gave light grey text on a hardcoded white card.
    static let inkPrimary   = Color(red: 0.09, green: 0.09, blue: 0.11)
    static let inkSecondary = Color(red: 0.30, green: 0.30, blue: 0.33)
    static let inkTertiary  = Color(red: 0.43, green: 0.43, blue: 0.46)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
