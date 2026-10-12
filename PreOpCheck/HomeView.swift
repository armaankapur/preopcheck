//
//  HomeView.swift
//  Stanford Preoperative Medication
//
//  Landing page: the two ways to start a check, the most recent saved
//  cases, and the offline assurances.
//
//  Built as a List rather than a ScrollView so the saved-case rows get the
//  system swipe-to-delete. The intro and the two buttons are list rows with
//  no background, inset or separator, so they look like plain content.
//

import Foundation
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var caseStore: CaseStore

    @State private var showEntry = false
    @State private var showScanner = false

    /// How many saved cases Home shows before handing off to Saved Cases.
    private static let recentLimit = 3

    var body: some View {
        List {
            Group {
                header
                scanButton
                manualButton
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            recentCases
            offlineAnalysis
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.stanfordLight)
        .navigationTitle("")
        .navigationBarHidden(true)
        .sheet(isPresented: $showEntry) {
            EntryView()
                .environmentObject(caseStore)
        }
        // Full screen, not a sheet: on iPad a sheet is a small card in the
        // middle of the display, which left the camera preview tiny.
        .fullScreenCover(isPresented: $showScanner) {
            // CameraWrapperView owns the permission gate, the privacy
            // explainer and the push to results, so nothing is wired here.
            CameraWrapperView()
                .environmentObject(caseStore)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pre-operative medication checker")
                .font(.app(28, .bold))
                .foregroundColor(.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Stanford Children's & Stanford Hospital")
                .font(.app(15, .medium))
                .foregroundColor(Color.stanford)
            Text("Pre-operative medication safety,\nat the point of care.")
                .font(.app(16))
                .foregroundColor(.inkSecondary)
                .lineSpacing(3)
                .padding(.top, 4)
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: Buttons

    private var scanButton: some View {
        Button {
            showScanner = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.app(18, .semibold))
                Text("Scan Medication List")
                    .font(.app(17, .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Color.actionGreen)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
    }

    private var manualButton: some View {
        Button {
            showEntry = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.app(16))
                Text("Enter Manually")
                    .font(.app(17, .medium))
            }
            .foregroundColor(Color.actionGreen)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Color.white)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.actionGreen, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    // MARK: Recent cases

    /// The newest few, each a swipe-to-delete row that opens its results.
    /// Past the limit, one link to the full Saved Cases screen.
    private var recentCases: some View {
        Section {
            if caseStore.cases.isEmpty {
                Text("No recent cases. Start a new check above.")
                    .font(.app(14))
                    .foregroundColor(.inkSecondary)
            } else {
                ForEach(caseStore.cases.prefix(HomeView.recentLimit)) { savedCase in
                    NavigationLink(value: savedCase) {
                        SavedCaseRow(savedCase: savedCase)
                    }
                    .deletesSavedCase(savedCase, from: caseStore)
                }
                if caseStore.cases.count > HomeView.recentLimit {
                    NavigationLink(value: SavedCasesRoute()) {
                        Text("All cases (\(caseStore.cases.count))")
                            .font(.app(15, .medium))
                            .foregroundColor(.actionGreen)
                    }
                }
            }
        } header: {
            sectionHeader("Recent cases")
        }
    }

    // MARK: Offline analysis

    private struct Assurance: Identifiable {
        let icon: String
        let text: String
        var id: String { text }
    }

    private let assurances: [Assurance] = [
        Assurance(icon: "checkmark.shield.fill", text: "HIPAA compliant"),
        Assurance(icon: "photo.badge.exclamationmark", text: "No photos saved"),
        Assurance(icon: "wifi.slash", text: "No internet needed")
    ]

    private var offlineAnalysis: some View {
        Section {
            ForEach(assurances) { item in
                HStack(spacing: 14) {
                    Image(systemName: item.icon)
                        .font(.app(18, .semibold))
                        .foregroundColor(.stanford)
                        .frame(width: 28, alignment: .center)
                    Text(item.text)
                        .font(.app(16, .medium))
                        .foregroundColor(.inkPrimary)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        } header: {
            sectionHeader("Offline analysis")
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.app(13, .semibold))
            .foregroundColor(.inkSecondary)
            .textCase(.uppercase)
    }
}
