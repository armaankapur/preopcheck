//
//  DrugLexicon.swift
//  Stanford Preoperative Medication
//
//  A plain list of drug names, far larger than the PARC database, used for
//  one purpose: telling whether a word on the page is a drug at all. The
//  scanner marks a word red only when it is in this list but has no PARC
//  guidance. Without this, "red" would have to be guessed from word shape,
//  which lit up ordinary words like "Discontinue".
//
//  Each name carries an ingredient key, so a brand and its generic share one
//  key (tylenol -> acetaminophen, vitamin d3 -> cholecalciferol). The scanner
//  uses the key to mark a drug once even when the page prints both names.
//
//  Loaded from DrugNames.txt in the app bundle: one "name<TAB>ingredient"
//  per line, built by tools/build_drug_lexicon.py from the FDA National Drug
//  Code directory. If the file is absent the lexicon is empty and nothing is
//  ever marked red. The list carries no clinical instruction; adding it does
//  not change any result.
//

import Foundation

final class DrugLexicon {

    static let shared = DrugLexicon()

    /// Normalised name -> ingredient key. Empty when no list is bundled.
    private let ingredientByName: [String: String]
    /// First two letters -> single-word names of 8+ letters, for the
    /// one-character spelling tolerance below.
    private let blockIndex: [String: [String]]

    /// Longest name in words, so the scanner knows how many words to try.
    let maxWords: Int

    private init() {
        var map: [String: String] = [:]
        var blocks: [String: [String]] = [:]
        var longest = 1
        if let url = Bundle.main.url(forResource: "DrugNames", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let columns = line.split(separator: "\t", maxSplits: 1)
                guard let first = columns.first else { continue }
                let name = DrugMatcher.normalize(String(first))
                guard name.count >= 4 else { continue }
                let key = columns.count > 1 ? DrugMatcher.normalize(String(columns[1])) : name
                map[name] = key.isEmpty ? name : key
                longest = max(longest, name.split(separator: " ").count)
                if name.count >= 8, !name.contains(" ") {
                    blocks[String(name.prefix(2)), default: []].append(name)
                }
            }
        }
        ingredientByName = map
        blockIndex = blocks
        maxWords = longest
    }

    var isEmpty: Bool { ingredientByName.isEmpty }

    /// The ingredient key for a normalised phrase, or nil if it is not a
    /// known drug name. Single long words tolerate one misread character
    /// ("Atorvastatln"), the usual camera slip; short words and multi-word
    /// phrases must match exactly, and a trailing variant tag is never
    /// bridged ("vitamin d3" vs "vitamin c").
    func ingredient(for normalizedPhrase: String) -> String? {
        if let exact = ingredientByName[normalizedPhrase] { return exact }
        guard normalizedPhrase.count >= 8, !normalizedPhrase.contains(" ") else { return nil }

        var best: String?
        for candidate in blockIndex[String(normalizedPhrase.prefix(2))] ?? [] {
            guard abs(candidate.count - normalizedPhrase.count) <= 1,
                  !DrugMatcher.differsOnlyInVariantTag(normalizedPhrase, candidate),
                  DrugMatcher.editDistance(normalizedPhrase, candidate, limit: 1) <= 1
            else { continue }
            // Two different candidates within one edit: too ambiguous to mark.
            if best != nil { return nil }
            best = candidate
        }
        return best.flatMap { ingredientByName[$0] }
    }
}
