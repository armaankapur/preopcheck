//
//  CaseStore.swift
//  Stanford Preoperative Medication
//
//  Rewritten for the PARC guidance model.
//
//  Note on what is persisted: NOT the DrugMatch. Bounding boxes and match
//  confidence are scan-time artifacts and have no meaning once the case is
//  saved. What matters clinically is which drug, what the clinician answered,
//  and what instruction that produced. Storing only the drug id also means a
//  future guideline revision won't leave stale drug text in old cases.
//

import Foundation
import Combine

// MARK: - Saved shapes

struct SavedMedication: Codable, Identifiable, Hashable {
    let drugID: String
    let matchedText: String        // what was actually read off the page
    let needsVerification: Bool    // was this a fuzzy OCR match
    let chosenBranchLabel: String? // which conditional the clinician picked
    let action: Action?            // resolved instruction, nil if unanswered

    var id: String { drugID }

    /// Resolved live against the current database rather than stored.
    var drug: Drug? { MedicationDatabase.byID[drugID] }

    var displayName: String { drug?.displayName ?? matchedText }
}

struct SavedCase: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let medications: [SavedMedication]
    let guidelineRevision: String

    var holdCount: Int {
        medications.filter { $0.action?.severity == .hold }.count
    }
    var consultCount: Int {
        medications.filter { $0.action?.severity == .consult }.count
    }
    var unresolvedCount: Int {
        medications.filter { $0.action == nil }.count
    }

    /// True when the case was saved against an older revision of the guideline.
    var isStale: Bool { guidelineRevision != GuidelineMeta.revision }
}

// MARK: - Store

final class CaseStore: ObservableObject {

    @Published private(set) var cases: [SavedCase] = []

    private let defaultsKey = "preop.savedCases.v2"
    private let maxCases = 50

    init() { load() }

    // MARK: Save

    /// Called from ResultsView. Matches `caseStore.save(medications)`.
    func save(_ medications: [ResolvedMedication]) {
        let saved = medications.map { med in
            SavedMedication(
                drugID: med.match.drug.id,
                matchedText: med.match.matchedText,
                needsVerification: med.match.needsVerification,
                chosenBranchLabel: med.chosenBranch?.whenLabel,
                action: med.action
            )
        }

        let newCase = SavedCase(
            id: UUID(),
            date: Date(),
            medications: saved,
            guidelineRevision: GuidelineMeta.revision
        )

        cases.insert(newCase, at: 0)
        if cases.count > maxCases { cases = Array(cases.prefix(maxCases)) }
        persist()
    }

    // MARK: Delete

    func delete(_ savedCase: SavedCase) {
        cases.removeAll { $0.id == savedCase.id }
        persist()
    }

    func deleteAll() {
        cases.removeAll()
        persist()
    }

    // MARK: Persistence

    private func persist() {
        do {
            let data = try JSONEncoder().encode(cases)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            // Non-fatal. A failed write must never block the clinical flow.
            print("CaseStore: failed to persist. \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        do {
            cases = try JSONDecoder().decode([SavedCase].self, from: data)
        } catch {
            // v1 cases used the old MedicationResult shape and cannot be
            // migrated, since the old three-state model has no equivalent
            // for a conditional. Start clean rather than guess.
            print("CaseStore: could not decode saved cases, starting empty. \(error)")
            cases = []
        }
    }
}
