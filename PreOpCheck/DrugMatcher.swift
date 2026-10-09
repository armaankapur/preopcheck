//
//  DrugMatcher.swift
//  Stanford Preoperative Medication
//
//  Replaces the ad-hoc string matching that lived inside ScannerView.
//  Three rules this file enforces, which the old pipeline did not:
//
//  1. Nothing enters the result set as a string. Everything resolves to a
//     canonical drug id first. Dedup is therefore structural, not a cleanup pass.
//  2. Fuzzy matching is bounded by length, blocked by first-two-letters, and
//     disabled entirely for short tokens. This is the false-positive fix.
//  3. Longest-span wins. "diclofenac XR" is matched before "diclofenac".
//

import Foundation
import CoreGraphics

// MARK: - Input

/// One OCR token with its normalized bounding box (Vision coordinate space).
struct OCRToken {
    let text: String
    let box: CGRect
    let ocrConfidence: Float
}

// MARK: - Output

struct DrugMatch: Identifiable {
    let drug: Drug
    var id: String { drug.id }
    let matchedText: String       // what was actually on the page
    let matchKind: MatchKind
    let boxes: [CGRect]

    var needsVerification: Bool { matchKind == .fuzzy }
}

enum MatchKind: Int, Comparable {
    case fuzzy = 0          // edit distance within bound
    case normalized = 1     // matched after stripping salt / form suffix
    case exact = 2          // literal match on generic or brand

    static func < (l: MatchKind, r: MatchKind) -> Bool { l.rawValue < r.rawValue }
}

// MARK: - Matcher

final class DrugMatcher {

    static let shared = DrugMatcher()

    /// normalized name -> drug id. Includes generics, brands, and n-grams.
    private let index: [String: String]
    /// first two letters -> candidate keys, for fuzzy blocking.
    private let blockIndex: [String: [String]]
    /// longest key, in tokens. Drives the n-gram window.
    private let maxGram: Int

    private init() {
        var idx: [String: String] = [:]
        var maxN = 1

        for drug in MedicationDatabase.all {
            for name in drug.searchNames {
                let key = DrugMatcher.normalize(name)
                guard !key.isEmpty else { continue }
                // First writer wins so a brand never overwrites a generic.
                if idx[key] == nil { idx[key] = drug.id }
                maxN = max(maxN, key.split(separator: " ").count)
            }
        }

        var blocks: [String: [String]] = [:]
        for key in idx.keys where key.count >= 6 {
            let prefix = String(key.prefix(2))
            blocks[prefix, default: []].append(key)
        }

        self.index = idx
        self.blockIndex = blocks
        self.maxGram = maxN
    }

    // MARK: Normalization

    /// Suffixes that do not change which drug it is.
    private static let saltSuffixes: Set<String> = [
        "hcl", "hydrochloride", "sodium", "potassium", "calcium", "succinate",
        "tartrate", "besylate", "maleate", "mesylate", "fumarate", "citrate",
        "sulfate", "acetate", "phosphate", "bitartrate", "napsylate"
    ]

    /// Words that appear on every med list and are never a drug.
    /// This is the single biggest false-positive fix.
    static let stopWords: Set<String> = [
        // dosing
        "mg", "mcg", "ml", "gm", "g", "unit", "units", "iu", "meq", "tab", "tabs",
        "tablet", "tablets", "cap", "caps", "capsule", "capsules", "dose", "doses",
        "puff", "puffs", "spray", "patch", "drop", "drops", "vial", "syringe", "pen",
        // frequency
        "daily", "bid", "tid", "qid", "qhs", "qam", "qpm", "prn", "hs", "ac", "pc",
        "once", "twice", "three", "four", "times", "day", "week", "weekly", "monthly",
        "hour", "hours", "night", "morning", "evening", "bedtime", "needed",
        // route
        "po", "iv", "im", "sq", "subq", "sc", "oral", "orally", "topical", "inhaled",
        "inhalation", "nebulized", "sublingual", "rectal", "transdermal",
        // list scaffolding
        "medication", "medications", "med", "meds", "list", "current", "active",
        "home", "outpatient", "inpatient", "prescription", "rx", "sig", "refill",
        "refills", "quantity", "qty", "start", "stop", "date", "prescriber",
        "pharmacy", "ndc", "generic", "brand", "name", "patient", "dob", "mrn",
        "ssn", "age", "sex", "male", "female", "allergy", "allergies", "nkda",
        "take", "taking", "hold", "continue", "resume", "discontinue", "instruct",
        "surgery", "surgical", "preop", "preoperative", "anesthesia", "npo",
        "page", "of", "and", "or", "the", "for", "with", "per", "as", "by", "to"
    ]

    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
            .replacingOccurrences(of: "’", with: "'")
        let cleaned = lowered.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) || $0 == " " ? Character($0) : " " }
        return String(cleaned)
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Strips a trailing salt or form word. Returns nil if nothing was stripped.
    private static func stripSalt(_ key: String) -> String? {
        let parts = key.split(separator: " ").map(String.init)
        guard parts.count > 1, let last = parts.last, saltSuffixes.contains(last) else { return nil }
        return parts.dropLast().joined(separator: " ")
    }

    // MARK: Matching

    /// The only public entry point. Everything else in the app calls this.
    func match(_ tokens: [OCRToken]) -> [DrugMatch] {
        // Keep positions so n-grams can be assembled and boxes unioned.
        let usable = tokens.enumerated().map { (i, t) in
            (index: i, token: t, norm: DrugMatcher.normalize(t.text))
        }

        var hits: [(id: String, text: String, kind: MatchKind, boxes: [CGRect])] = []
        var consumed = Set<Int>()

        // Longest span first. This is what stops "diclofenac XR" from
        // collapsing into "diclofenac" and getting the wrong hold window.
        for span in stride(from: maxGram, through: 1, by: -1) {
            guard usable.count >= span else { continue }
            for start in 0...(usable.count - span) {
                let range = start..<(start + span)
                if range.contains(where: { consumed.contains($0) }) { continue }

                let slice = usable[range]
                let phrase = slice.map { $0.norm }.filter { !$0.isEmpty }.joined(separator: " ")
                guard !phrase.isEmpty else { continue }

                guard let (id, kind) = resolve(phrase, isSingleToken: span == 1) else { continue }

                hits.append((id, slice.map { $0.token.text }.joined(separator: " "),
                             kind, slice.map { $0.token.box }))
                range.forEach { consumed.insert($0) }
            }
        }

        return dedupe(hits)
    }

    /// Resolve one candidate phrase to a drug id. Returns nil for no match.
    private func resolve(_ phrase: String, isSingleToken: Bool) -> (String, MatchKind)? {
        // Gate 1: stop words never match, at any stage.
        if isSingleToken && DrugMatcher.stopWords.contains(phrase) { return nil }
        // Gate 2: pure numbers and short fragments never match.
        if phrase.count < 4 { return nil }
        if phrase.allSatisfy({ $0.isNumber }) { return nil }

        // Exact.
        if let id = index[phrase] { return (id, .exact) }

        // Salt or form stripped.
        if let stripped = DrugMatcher.stripSalt(phrase), let id = index[stripped] {
            return (id, .normalized)
        }

        // Fuzzy, heavily bounded. OCR errors are usually one or two characters.
        guard phrase.count >= 6 else { return nil }
        let bound = phrase.count >= 10 ? 2 : 1
        let prefix = String(phrase.prefix(2))

        var best: (id: String, distance: Int)?
        for candidate in blockIndex[prefix] ?? [] {
            // Length gate: a real OCR error does not change length much.
            guard abs(candidate.count - phrase.count) <= bound else { continue }
            // Variant gate: "vitamin d3" is within two edits of "vitamin c",
            // but the difference is the product, not an OCR slip.
            if DrugMatcher.differsOnlyInVariantTag(phrase, candidate) { continue }
            let d = DrugMatcher.editDistance(phrase, candidate, limit: bound)
            guard d <= bound else { continue }
            if best == nil || d < best!.distance {
                best = (index[candidate]!, d)
            }
        }

        if let b = best { return (b.id, .fuzzy) }
        return nil
    }

    /// Dedup happens here and nowhere else. Keyed on drug id, so a brand and its
    /// generic collapse automatically. The strongest match kind wins.
    private func dedupe(
        _ hits: [(id: String, text: String, kind: MatchKind, boxes: [CGRect])]
    ) -> [DrugMatch] {
        var out: [String: DrugMatch] = [:]

        for hit in hits {
            guard let drug = MedicationDatabase.byID[hit.id] else { continue }

            if let existing = out[hit.id] {
                let strongest = max(existing.matchKind, hit.kind)
                let text = hit.kind > existing.matchKind ? hit.text : existing.matchedText
                out[hit.id] = DrugMatch(
                    drug: drug,
                    matchedText: text,
                    matchKind: strongest,
                    boxes: existing.boxes + hit.boxes
                )
            } else {
                out[hit.id] = DrugMatch(drug: drug, matchedText: hit.text,
                                        matchKind: hit.kind, boxes: hit.boxes)
            }
        }

        // Stable order: severity, then category, then name.
        return out.values.sorted {
            if $0.drug.guidance.severity != $1.drug.guidance.severity {
                return severityRank($0.drug.guidance.severity) < severityRank($1.drug.guidance.severity)
            }
            return $0.drug.generic < $1.drug.generic
        }
    }

    private func severityRank(_ s: Severity) -> Int {
        switch s {
        case .hold:            return 0
        case .consult:         return 1
        case .takeAsDirected:  return 2
        }
    }

    // MARK: Variant tags

    /// True when two normalised names share every word except the last, and
    /// the last word is a short variant tag on at least one side: a letter or
    /// letter-plus-number such as "c", "d3", "b12", or a form code like "xr".
    /// Such a difference names a different product, never an OCR slip, so
    /// fuzzy matching must not bridge it. Exact and salt-stripped matching
    /// do not consult this.
    static func differsOnlyInVariantTag(_ a: String, _ b: String) -> Bool {
        let ta = a.split(separator: " "), tb = b.split(separator: " ")
        guard ta.count >= 2, ta.count == tb.count else { return false }
        guard ta.dropLast().elementsEqual(tb.dropLast()) else { return false }
        guard let la = ta.last, let lb = tb.last, la != lb else { return false }
        return isVariantTag(la) || isVariantTag(lb)
    }

    private static func isVariantTag(_ word: Substring) -> Bool {
        word.count <= 3 || word.contains { $0.isNumber }
    }

    // MARK: Edit distance

    /// Damerau-Levenshtein with early exit. Transposition matters because
    /// OCR swaps adjacent characters often.
    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let s = Array(a), t = Array(b)
        if abs(s.count - t.count) > limit { return limit + 1 }

        var prev2 = [Int](repeating: 0, count: t.count + 1)
        var prev  = Array(0...t.count)
        var cur   = [Int](repeating: 0, count: t.count + 1)

        for i in 1...s.count {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                var v = min(cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    v = min(v, prev2[j - 2] + 1)
                }
                cur[j] = v
                rowMin = min(rowMin, v)
            }
            if rowMin > limit { return limit + 1 }
            prev2 = prev; prev = cur; cur = [Int](repeating: 0, count: t.count + 1)
        }
        return prev[t.count]
    }
}

// MARK: - Resolution

/// A match with its guideline instruction. There is no interactive state:
/// drugs whose guidance branches are consults, and the branches are shown to
/// the clinician as read-only considerations.
struct ResolvedMedication: Identifiable {
    let match: DrugMatch

    /// Position in the source: top to bottom on the scanned page, or the
    /// order typed or saved. Drives the "In order" view on the results screen.
    var order: Int = 0

    var id: String { match.id }

    var action: Action { match.drug.guidance.action }

    /// Branches the clinician should weigh. Empty for most drugs.
    var considerations: [Conditional] { match.drug.guidance.conditionals }
}
