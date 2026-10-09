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

    // Dates in the three forms printouts use: 03/14/2015, 2015-03-14, Mar 14, 2015.
    private static let dateRegex = try! NSRegularExpression(
        pattern: #"\b\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}\b|\b\d{4}-\d{2}-\d{2}\b|"#
               + #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}\b"#,
        options: [.caseInsensitive])

    // Record numbers and phone numbers: a long run of digits, or 3-3-4.
    private static let longNumberRegex = try! NSRegularExpression(
        pattern: #"\d{6,}|\b\d{3}[-. ]\d{3}[-. ]\d{4}\b"#)

    // "SAMPLE, JANE Q", "Nguyen, An", "Garcia-Lopez, Sofia M." The name
    // tagger misses this surname-first form, which is how Epic prints names.
    private static let surnameFirstRegex = try! NSRegularExpression(
        pattern: #"^\s*[A-Z][A-Za-z'’\-]+,\s*[A-Z][A-Za-z'’\-]+(\s+[A-Z][A-Za-z'’\-]*\.?)*\s*$"#)

    /// True when the line carries something that identifies the patient.
    static func isIdentityLine(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        if dateRegex.firstMatch(in: text, range: range) != nil { return true }
        if longNumberRegex.firstMatch(in: text, range: range) != nil { return true }

        let lower = text.lowercased()
        let words = lower.split { !$0.isLetter }.map(String.init)
        let wordSet = Set(words)

        // A label alone ("Patient Medication List") is a heading. A label with
        // a colon or a number after it is a value.
        let hasLabel = !wordSet.isDisjoint(with: labelWords)
            || labelPhrases.contains { lower.contains($0) }
        let hasValue = text.contains(":") || text.contains { $0.isNumber }
        if hasLabel && hasValue { return true }

        if surnameFirstRegex.firstMatch(in: text, range: range) != nil { return true }

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
