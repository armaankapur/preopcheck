//
//  ContentView.swift
//  PreOpCheck
//
//  Created by Timo on 4/27/26.
//
//  Root navigation. Home and Saved Cases push values rather than views, so
//  the two destinations below are declared once here, and saving from an
//  opened case can clear the whole path and land on Home.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var caseStore: CaseStore
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .environmentObject(caseStore)
                .navigationDestination(for: SavedCase.self) { savedCase in
                    let outcome = MedicationResolver.resolve(saved: savedCase)
                    ResultsView(medications: outcome.medications,
                                unmatched: outcome.unmatched,
                                onSaved: { path = NavigationPath() })
                        .environmentObject(caseStore)
                }
                .navigationDestination(for: SavedCasesRoute.self) { _ in
                    SavedCasesView()
                        .environmentObject(caseStore)
                }
        }
        .tint(Color.stanford)
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
        .environmentObject(CaseStore())
}
