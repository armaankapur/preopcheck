//
//  EntryView.swift
//  Stanford Preoperative Medication
//

import SwiftUI

struct EntryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var caseStore: CaseStore
    @State private var medInput = ""
    @State private var meds: [String] = []
    @State private var showResults = false
    @State private var results: [ResolvedMedication] = []
    @State private var unmatched: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    Text("Type or paste each medication name below. We'll check each one against the PARC pre-operative guideline.")
                        .font(.app(14))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Input row
                    HStack(spacing: 10) {
                        TextField("Drug name (e.g. Lisinopril)...", text: $medInput)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(.systemGray4), lineWidth: 0.5))
                            .onSubmit { addMed() }

                        Button(action: addMed) {
                            Text("Add")
                                .font(.app(15, .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.actionGreen)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Chips
                    if meds.isEmpty {
                        Text("No medications added yet")
                            .font(.app(14))
                            .foregroundColor(Color(.systemGray3))
                            .padding(.horizontal, 20)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(meds.enumerated()), id: \.offset) { i, med in
                                HStack(spacing: 6) {
                                    Text(med)
                                        .font(.app(14))

                                    // Live check against the guideline so a typo
                                    // is visible before Analyze is tapped.
                                    if !isRecognized(med) {
                                        Image(systemName: "questionmark.circle")
                                            .font(.app(12))
                                            .foregroundColor(.orange)
                                    }

                                    Button {
                                        meds.remove(at: i)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.app(11, .semibold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.white)
                                .cornerRadius(20)
                                .overlay(RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color(.systemGray4), lineWidth: 0.5))
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Analyze button
                    Button(action: analyze) {
                        Text("Analyze Medications")
                            .font(.app(17, .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(meds.isEmpty ? Color.gray : Color.actionGreen)
                            .cornerRadius(14)
                    }
                    .disabled(meds.isEmpty)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .padding(.bottom, 32)
            }
            .background(Color.stanfordLight)
            .navigationTitle("New Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.stanford)
                }
            }
            .navigationDestination(isPresented: $showResults) {
                ResultsView(medications: results, unmatched: unmatched)
                    .environmentObject(caseStore)
            }
        }
    }

    // MARK: Actions

    func addMed() {
        let parts = medInput
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        for p in parts {
            guard !p.isEmpty else { continue }
            // Case-insensitive duplicate check so "Lisinopril" and "lisinopril"
            // don't both end up as chips.
            guard !meds.contains(where: { $0.caseInsensitiveCompare(p) == .orderedSame }) else { continue }
            meds.append(p)
        }
        medInput = ""
    }

    /// Same matcher the scanner uses, so manual entry and scanning can never
    /// disagree about the same drug.
    func analyze() {
        let outcome = MedicationResolver.resolve(lines: meds)
        results = outcome.medications
        unmatched = outcome.unmatched
        showResults = true
    }

    private func isRecognized(_ text: String) -> Bool {
        let tokens = text
            .split(separator: " ")
            .map { OCRToken(text: String($0), box: .zero, ocrConfidence: 1.0) }
        return !DrugMatcher.shared.match(tokens).isEmpty
    }
}
