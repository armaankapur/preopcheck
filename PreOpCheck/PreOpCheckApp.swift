//
//  PreOpCheckApp.swift
//  PreOpCheck
//
//  Created by Timo on 4/27/26.
//

import SwiftUI

@main
struct PreOpCheckApp: App {
    @StateObject var caseStore = CaseStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(caseStore)
        }
    }
}
