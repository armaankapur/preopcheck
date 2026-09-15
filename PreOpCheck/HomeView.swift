//
//  HomeView.swift
//  Stanford Preoperative Medication
//

import Foundation
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var caseStore: CaseStore

    @State private var showEntry = false
    @State private var showScanner = false
    @State private var navigateToResults = false

    @State private var resultsToShow: [ResolvedMedication] = []
    @State private var unmatchedToShow: [String] = []

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                scanButton
                manualButton
                recentCases
                offlineAnalysis
            }
        }
        .background(Color.stanfordLight)
        .navigationTitle("")
        .navigationBarHidden(true)
        .sheet(isPresented: $showEntry) {
            EntryView()
                .environmentObject(caseStore)
        }
        .sheet(isPresented: $showScanner) {
            // CameraWrapperView owns the permission gate, the privacy
            // explainer and the push to results, so nothing is wired here.
            CameraWrapperView()
                .environmentObject(caseStore)
        }
        .navigationDestination(isPresented: $navigateToResults) {
            ResultsView(medications: resultsToShow, unmatched: unmatchedToShow)
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
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 28)
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
        .padding(.horizontal, 20)
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
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }

    // MARK: Recent cases

    private var recentCases: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT CASES")
                .font(.app(13, .semibold))
                .foregroundColor(.inkSecondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            if caseStore.cases.isEmpty {
                Text("No recent cases. Start a new check above.")
                    .font(.app(14))
                    .foregroundColor(.inkSecondary)
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 1) {
                    ForEach(caseStore.cases.prefix(5)) { c in
                        Button {
                            open(c)
                        } label: {
                            caseRow(c)
                        }
                    }
                }
                .cornerRadius(14)
                .padding(.horizontal, 20)
            }
        }
    }

    private func caseRow(_ c: SavedCase) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Case \(String(c.id.uuidString.prefix(4)))")
                        .font(.app(15, .semibold))
                        .foregroundColor(.inkPrimary)
                    if c.isStale {
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
                    if c.holdCount > 0 {
                        Text("\(c.holdCount) hold")
                            .foregroundColor(Color.stanford)
                    } else {
                        Text("0 hold")
                            .foregroundColor(.inkSecondary)
                    }
                    Text("·").foregroundColor(.inkSecondary)
                    Text("\(c.medications.count) meds")
                        .foregroundColor(.inkSecondary)
                    Text("·").foregroundColor(.inkSecondary)
                    Text(HomeView.timeFormatter.string(from: c.date))
                        .foregroundColor(.inkSecondary)
                }
                .font(.app(13))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.app(14, .medium))
                .foregroundColor(Color(.systemGray3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white)
    }

    private func open(_ c: SavedCase) {
        let outcome = MedicationResolver.resolve(saved: c)
        resultsToShow = outcome.medications
        unmatchedToShow = outcome.unmatched
        navigateToResults = true
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
        VStack(alignment: .leading, spacing: 0) {
            Text("OFFLINE ANALYSIS")
                .font(.app(13, .semibold))
                .foregroundColor(.inkSecondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    if item.id != assurances.last?.id {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .background(Color.white)
            .cornerRadius(14)
            .padding(.horizontal, 20)
        }
        .padding(.top, 28)
        .padding(.bottom, 32)
    }
}
