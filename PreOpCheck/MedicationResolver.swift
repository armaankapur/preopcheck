//
//  MedicationResolver.swift
//  Stanford Preoperative Medication
//
//  The single conversion point from raw input to ResolvedMedication.
//
//  Manual entry and camera scanning must go through the same matcher, or the
//  two paths will disagree about the same drug. Typing "Xarelto" and scanning
//  "Xarelto" have to produce identical results, and the only way to guarantee
//  that is for both to call DrugMatcher.
//

import Foundation
import CoreGraphics

enum MedicationResolver {

    /// Result of resolving free text. `unmatched` is what the user typed that
    /// resolved to nothing, so the UI can show it rather than silently drop it.
    struct Outcome {
        var medications: [ResolvedMedication]
        var unmatched: [String]
    }

    // MARK: Free text (manual entry)

    /// Accepts one line per medication. Commas, semicolons and newlines all
    /// split, so a pasted list works as well as line-by-line typing.
    static func resolve(freeText text: String) -> Outcome {
        let lines = text
            .components(separatedBy: CharacterSet(charactersIn: "\n,;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return resolve(lines: lines)
    }

    static func resolve(lines: [String]) -> Outcome {
        var found: [String: DrugMatch] = [:]
        var unmatched: [String] = []

        for line in lines {
            let tokens = line
                .split(separator: " ")
                .map { OCRToken(text: String($0), box: .zero, ocrConfidence: 1.0) }

            let matches = DrugMatcher.shared.match(tokens)

            if matches.isEmpty {
                unmatched.append(line)
                continue
            }

            for m in matches {
                if let existing = found[m.id] {
                    if m.matchKind > existing.matchKind { found[m.id] = m }
                } else {
                    found[m.id] = m
                }
            }
        }

        return Outcome(medications: wrap(Array(found.values)), unmatched: unmatched)
    }

    // MARK: Scan output

    /// Scanner already ran the matcher, so this only wraps.
    static func resolve(matches: [DrugMatch]) -> Outcome {
        Outcome(medications: wrap(matches), unmatched: [])
    }

    // MARK: Saved case

    /// Rehydrates a stored case. Drug details are looked up live rather than
    /// read from storage, so reopening an old case reflects the current
    /// guideline. If a drug id no longer exists (guideline revised, drug
    /// removed) it surfaces as unmatched instead of vanishing.
    static func resolve(saved: SavedCase) -> Outcome {
        var medications: [ResolvedMedication] = []
        var unmatched: [String] = []

        for item in saved.medications {
            guard let drug = MedicationDatabase.byID[item.drugID] else {
                unmatched.append(item.matchedText)
                continue
            }

            let match = DrugMatch(
                drug: drug,
                matchedText: item.matchedText,
                matchKind: item.needsVerification ? .fuzzy : .exact,
                boxes: []
            )

            // Re-attach the branch the clinician chose, matched by label.
            let branch = drug.guidance.conditionals.first {
                $0.whenLabel == item.chosenBranchLabel
            }

            medications.append(ResolvedMedication(match: match, chosenBranch: branch))
        }

        return Outcome(medications: medications.sorted { rank($0) < rank($1) },
                       unmatched: unmatched)
    }

    // MARK: Shared

    private static func wrap(_ matches: [DrugMatch]) -> [ResolvedMedication] {
        matches
            .map { ResolvedMedication(match: $0, chosenBranch: nil) }
            .sorted { rank($0) < rank($1) }
    }

    /// Unanswered conditionals sort to the top, then holds, then consults.
    private static func rank(_ m: ResolvedMedication) -> Int {
        if m.isUnresolved { return 0 }
        switch m.action?.severity {
        case .hold:           return 1
        case .consult:        return 2
        case .conditional:    return 3
        case .takeAsDirected: return 4
        case .none:           return 5
        }
    }

    // MARK: Demo

    /// Sample data for HomeView's demo path. Deliberately mixes a hold, a
    /// consult, a conditional and a take-as-directed so every results section
    /// renders.
    static func demo() -> Outcome {
        resolve(lines: [
            "lisinopril 10 mg daily",
            "furosemide 20 mg twice daily",
            "enoxaparin 40 mg subcutaneous",
            "metoprolol succinate 25 mg",
            "ibuprofen 400 mg as needed",
            "semaglutide 1 mg weekly",
            "atorvastatin 20 mg nightly"
        ])
    }
}
