//
//  ContentView.swift
//  PreOpCheck
//
//  Created by Timo on 4/27/26.
//

// ContentView.swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var caseStore: CaseStore
    
    var body: some View {
        NavigationStack {
            HomeView()
                .environmentObject(caseStore)
        }
        .tint(Color.stanford)
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
        .environmentObject(CaseStore())
}
