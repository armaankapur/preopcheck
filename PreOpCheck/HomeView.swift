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
                offlineBadge
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
            Text("Stanford Preoperative Medication")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.inkPrimary)
            Text("Stanford Children's & Stanford Hospital")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.stanford)
            Text("Pre-operative medication safety,\nat the point of care.")
                .font(.system(size: 16))
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
                    .font(.system(size: 18, weight: .semibold))
                Text("Scan Medication List")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Color.stanford)
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
                    .font(.system(size: 16))
                Text("Enter Manually")
                    .font(.system(size: 17, weight: .medium))
            }
            .foregroundColor(Color.stanford)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Color.white)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.stanford.opacity(0.4), lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }

    // MARK: Recent cases

    private var recentCases: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT CASES")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.inkSecondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            if caseStore.cases.isEmpty {
                Text("No recent cases. Start a new check above.")
                    .font(.system(size: 14))
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.inkPrimary)
                    if c.isStale {
                        Text("OLD GUIDELINE")
                            .font(.system(size: 9, weight: .bold))
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
                .font(.system(size: 13))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
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

    // MARK: Badge

    private var offlineBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "cross.case.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Offline-First Analysis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Camera scanning works without internet using on-device Vision framework.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .background(Color.stanford)
        .cornerRadius(12)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 32)
    }
}
