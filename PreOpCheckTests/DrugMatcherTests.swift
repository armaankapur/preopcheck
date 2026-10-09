//
//  DrugMatcherTests.swift
//  PreOpCheckTests
//
//  Guards the matcher against mapping one vitamin onto another. "vitamin d3"
//  used to fuzzy-match vitamin C or E because they sit within the edit
//  distance bound; a trailing variant tag now blocks that, while exact,
//  brand and genuine OCR-slip matches keep working.
//

import Testing
import CoreGraphics
@testable import PreOpCheck

struct DrugMatcherVariantTests {

    /// Runs text through the matcher the same way manual entry does.
    private func match(_ text: String) -> [DrugMatch] {
        let tokens = text.split(separator: " ")
            .map { OCRToken(text: String($0), box: .zero, ocrConfidence: 1) }
        return DrugMatcher.shared.match(tokens)
    }

    @Test("Other vitamins never resolve to vitamin C",
          arguments: ["vitamin d", "vitamin d3", "vitamin b12"])
    func otherVitaminsDoNotMatchVitaminC(_ text: String) {
        #expect(!match(text).contains { $0.id == "vitaminc" },
                "\(text) must not resolve to vitamin C")
    }

    @Test("Vitamin D3 comes out unrecognised rather than as another vitamin")
    func vitaminD3IsUnrecognised() {
        #expect(match("vitamin d3").isEmpty)
    }

    @Test("Vitamin C still matches exactly, by brand, and with a one-letter OCR slip",
          arguments: ["vitamin c", "ascorbic acid", "vitamln c"])
    func vitaminCStillMatches(_ text: String) {
        #expect(match(text).contains { $0.id == "vitaminc" },
                "\(text) should resolve to vitamin C")
    }

    @Test("Exact and brand matches keep the exact kind")
    func exactKindUnchanged() {
        #expect(match("vitamin c").first { $0.id == "vitaminc" }?.matchKind == .exact)
        #expect(match("ascorbic acid").first { $0.id == "vitaminc" }?.matchKind == .exact)
    }

    @Test("An OCR slip in the long word is a fuzzy match flagged for verification")
    func ocrSlipIsFlaggedFuzzy() {
        let m = match("vitamln c").first { $0.id == "vitaminc" }
        #expect(m?.matchKind == .fuzzy)
        #expect(m?.needsVerification == true)
    }

    @Test("The variant rule itself", arguments: [
        ("vitamin d3", "vitamin c", true),
        ("vitamin d", "vitamin e", true),
        ("vitamin b12", "vitamin c", true),
        ("vitamln c", "vitamin c", false),    // slip is in the long word
        ("lisinopri1", "lisinopril", false),  // single word, rule does not apply
        ("vitamin c", "vitamin c", false)     // identical
    ])
    func variantRule(_ c: (String, String, Bool)) {
        #expect(DrugMatcher.differsOnlyInVariantTag(c.0, c.1) == c.2,
                "\(c.0) vs \(c.1)")
    }
}
