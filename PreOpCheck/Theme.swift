//
//  Theme.swift
//  PreOpCheck
//
//  Created by Timo on 4/27/26.
//
import SwiftUI
import UIKit

extension Color {
    static let stanford = Color(hex: "#8C1515")
    static let stanfordGrey = Color(hex: "#4D4F53")
    static let stanfordLight = Color(hex: "#F4F4F4")

    /// The single green used for every tappable action button in the app
    /// (scan, capture, proceed, analyze, save, confirm).
    static let actionGreen = Color(hex: "#1E8E3E")

    // Fixed text colors. These do not adapt to dark mode, because the app
    // draws explicit white cards everywhere. Using .primary and .secondary
    // gave light grey text on a hardcoded white card.
    static let inkPrimary   = Color(red: 0.09, green: 0.09, blue: 0.11)
    static let inkSecondary = Color(red: 0.30, green: 0.30, blue: 0.33)
    static let inkTertiary  = Color(red: 0.43, green: 0.43, blue: 0.46)
}

extension UIColor {
    /// UIKit twin of `Color.actionGreen`, for the camera chrome.
    static let actionGreen = UIColor(red: 0x1E / 255, green: 0x8E / 255, blue: 0x3E / 255, alpha: 1)

    /// Tint laid over the blur that hides patient details on the scanner, so
    /// the bar reads as deliberately covered rather than out of focus.
    static let redactionTint = UIColor.black.withAlphaComponent(0.12)
}

// MARK: - Typography

/// One place to scale the whole app's type. Every font in the app goes
/// through `Font.app(_:_:)` or `UIFont.app(_:weight:)`, so a single constant
/// changes everything consistently.
enum AppType {
    /// Base sizes in the views are the original design sizes; this multiplier
    /// is applied on top of them.
    static let scale: CGFloat = 1.12

    static func scaled(_ size: CGFloat) -> CGFloat {
        (size * scale).rounded()
    }
}

extension Font {
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: AppType.scaled(size), weight: weight)
    }
}

extension UIFont {
    static func app(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: AppType.scaled(size), weight: weight)
    }
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
