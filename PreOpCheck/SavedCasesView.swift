//
//  SavedCasesView.swift
//  PreOpCheck
//
//  Every saved case, newest first. Home shows only the most recent few and
//  hands off here, so a long history never clutters the landing page.
//
//  The row and the swipe-to-delete live here too and are shared with Home,
//  so both screens look and behave the same. Tapping a row pushes a
//  SavedCase value; ContentView turns that into a results screen.
//

import SwiftUI

/// Pushed by Home's "All cases" link. A value rather than a view, so it sits
/// in the root NavigationPath alongside the SavedCase values and is popped
/// with them when a save clears the path.
struct SavedCasesRoute: Hashable {}

struct SavedCasesView: View {
    @EnvironmentObject var caseStore: CaseStore

    var body: some View {
        List {
            ForEach(caseStore.cases) { savedCase in
                NavigationLink(value: savedCase) {
                    SavedCaseRow(savedCase: savedCase)
                }
                .deletesSavedCase(savedCase, from: caseStore)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.stanfordLight)
        .navigationTitle("Saved Cases")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if caseStore.cases.isEmpty {
                ContentUnavailableView("No saved cases",
                                       systemImage: "tray",
                                       description: Text("Cases you save from a results page appear here."))
            }
        }
    }
}

// MARK: - Row

/// One saved case: a short id, the hold count, the medication count and
/// when it was saved. Used by Home and by SavedCasesView.
struct SavedCaseRow: View {
    let savedCase: SavedCase

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Case \(String(savedCase.id.uuidString.prefix(4)))")
                    .font(.app(15, .semibold))
                    .foregroundColor(.inkPrimary)
                if savedCase.isStale {
                    Text("OLD GUIDELINE")
                        .font(.app(9, .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .cornerRadius(3)
                }
            }

            HStack(spacing: 4) {
                Text("\(savedCase.holdCount) hold")
                    .foregroundColor(savedCase.holdCount > 0 ? Color.stanford : .inkSecondary)
                Text("·")
                Text("\(savedCase.medications.count) meds")
                Text("·")
                Text(SavedCaseRow.timeFormatter.string(from: savedCase.date))
            }
            .font(.app(13))
            .foregroundColor(.inkSecondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Delete swipe

extension View {
    /// The Messages-style swipe: drag the row towards the leading edge and a
    /// red trash button appears; a full swipe deletes straight away.
    func deletesSavedCase(_ savedCase: SavedCase, from store: CaseStore) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation { store.delete(savedCase) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
