//
//  PatientIdentity.swift
//  PreOpCheck
//
//  Decides whether one line of recognised text identifies the patient (name,
//  date of birth, record number, and the like) so the scanner can blur it on
//  screen. Pure text in, yes/no out: nothing is kept.
//
//  The rules are deliberately loose. Blurring a heading by mistake costs
//  nothing; leaving a name visible is the failure that matters. Drug lines
//  are exempted by the caller, which knows what matched, so a drug the name
//  tagger mistakes for a person is never blurred.
//

import CoreGraphics
import Foundation
import NaturalLanguage

enum PatientIdentity {

    /// Words EHR printouts put in front of identifying details. Matched as
    /// whole words, so "dosage" does not trip "age".
    static let labelWords: Set<String> = [
        "patient", "name", "dob", "birthdate", "mrn", "sex", "gender", "age",
        "acct", "account", "encounter", "csn", "address", "phone", "guardian",
        "parent", "provider", "physician", "pcp"
    ]

    /// Labels that span more than one word.
    static let labelPhrases = ["date of birth", "birth date", "medical record", "record number"]

    /// Words that mean a line is about the institution, not a person, so the
    /// name tagger does not blur "Lucile Packard Children's Hospital".
    static let organisationWords: Set<String> = [
        "hospital", "health", "healthcare", "clinic", "medical", "center", "centre",
        "university", "pharmacy", "department", "anesthesia", "anesthesiology", "summary"
    ]

    /// Letters after a comma that mean the name is a clinician's, not the
    /// patient's ("Smith, MD" in Epic's Ordering Provider column). Those
    /// stay visible, otherwise every row of the table grows a blur bar.
    static let credentials: Set<String> = [
        "md", "do", "np", "pa", "pac", "rn", "pharmd", "phd", "dds", "dmd",
        "crna", "aprn", "fnp", "pnp", "lvn", "lpn", "cnm", "msn", "bsn"
    ]

    // Record numbers and phone numbers: a long run of digits, or 3-3-4.
    private static let longNumberRegex = try! NSRegularExpression(
        pattern: #"\d{6,}|\b\d{3}[-. ]\d{3}[-. ]\d{4}\b"#)

    // An age the way charts print it: "58 y.o.", "11 yo", "11 y/o".
    private static let ageRegex = try! NSRegularExpression(
        pattern: #"\b\d{1,3}\s*y\.?\s*/?\s*o\.?(\s|$)"#, options: [.caseInsensitive])

    // "SAMPLE, JANE Q", "Nguyen, An", "Garcia-Lopez, Sofia M." The name
    // tagger misses this surname-first form, which is how Epic prints names.
    private static let surnameFirstRegex = try! NSRegularExpression(
        pattern: #"^\s*[A-Z][A-Za-z'’\-]+,\s*([A-Z][A-Za-z'’\-]+)(\s+[A-Z][A-Za-z'’\-]*\.?)*\s*$"#)

    // "Jane Q. Sample" anywhere in a line, as footers print it. The period
    // after the initial is required: "Vitamin D Supplement" has the same
    // shape without it.
    private static let initialledNameRegex = try! NSRegularExpression(
        pattern: #"\b[A-Z][a-z]+ [A-Z]\. [A-Z][a-z]+\b"#)

    // Dates in the forms printouts use: 03/14/2015, 2015-03-14, Mar 14, 2015.
    private static let dateRegex = try! NSRegularExpression(
        pattern: #"\b\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}\b|\b\d{4}-\d{2}-\d{2}\b|"#
               + #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}\b"#,
        options: [.caseInsensitive])

    static func containsDate(_ text: String) -> Bool {
        dateRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// The boxes of every line on the page that should be blurred.
    ///
    /// Beyond `isIdentityLine`, a bare date is included when it shares a row
    /// with an identifying line. Vision splits Epic's header into separate
    /// pieces ("MRN: 12345678", "58 y.o.", "01/01/1967"), and the birth date
    /// alone would otherwise stay visible. A start date on a medication row
    /// has no identifying neighbour, so it stays clear.
    static func identityLines(in lines: [ScannedLine]) -> [CGRect] {
        let identity = lines.filter { isIdentityLine($0.text) }
        let datesBesideIdentity = lines.filter { line in
            containsDate(line.text)
                && !isIdentityLine(line.text)
                && identity.contains { sharesRow($0.box, line.box) }
        }
        return (identity + datesBesideIdentity).map(\.box)
    }

    /// Two boxes on the same printed row: centres within about half a line.
    static func sharesRow(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.midY - b.midY) < max(a.height, b.height) * 0.6
    }

    /// True when the line carries something that identifies the patient.
    ///
    /// A bare date is deliberately not enough here. Epic prints a start date
    /// on every medication row, and blurring the whole column looked chaotic.
    /// A date of birth is caught by its label, by the record number or age on
    /// its line, or by `identityLines(in:)` when it sits beside one of those.
    static func isIdentityLine(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        if longNumberRegex.firstMatch(in: text, range: range) != nil { return true }
        if ageRegex.firstMatch(in: text, range: range) != nil { return true }
        if initialledNameRegex.firstMatch(in: text, range: range) != nil { return true }

        let lower = text.lowercased()
        let words = lower.split { !$0.isLetter }.map(String.init)
        let wordSet = Set(words)

        // A label alone ("Patient Medication List") is a heading. A label with
        // a colon or a number after it is a value.
        let hasLabel = !wordSet.isDisjoint(with: labelWords)
            || labelPhrases.contains { lower.contains($0) }
        let hasValue = text.contains(":") || text.contains { $0.isNumber }
        if hasLabel && hasValue { return true }

        if let match = surnameFirstRegex.firstMatch(in: text, range: range),
           let afterComma = Range(match.range(at: 1), in: text) {
            let first = text[afterComma].lowercased().filter { $0.isLetter }
            if !credentials.contains(first) { return true }
        }

        // The name tagger only sees short lines: a name sits on its own line
        // or beside a label, never inside a sentence of directions.
        guard words.count <= 6, wordSet.isDisjoint(with: organisationWords) else { return false }
        return containsPersonalName(text)
    }

    // NLTagger is not documented as thread-safe, and the scanner and the
    // tests can call this from different queues, so one tagger behind a lock.
    private static let taggerLock = NSLock()
    private static let tagger = NLTagger(tagSchemes: [.nameType])

    private static func containsPersonalName(_ text: String) -> Bool {
        taggerLock.lock(); defer { taggerLock.unlock() }
        tagger.string = text
        var found = false
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, _ in
            found = tag == .personalName
            return !found
        }
        return found
    }
}
