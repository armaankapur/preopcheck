//
//  CameraWrapperView.swift
//  Stanford Preoperative Medication
//
//  Owns the whole scan flow: permission gate, privacy explainer, scanner,
//  results. Present this rather than ScannerView directly, so the explainer
//  and the info button are always in the path.
//

import SwiftUI
import AVFoundation

struct CameraWrapperView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var caseStore: CaseStore

    private enum Permission {
        case checking, authorized, denied, restricted
    }

    @State private var permission: Permission = .checking

    /// Shown automatically on first use, and on demand from the info button.
    @State private var showPrivacyNotice = false
    @State private var privacyNoticeIsFirstRun = false

    @State private var scannedMatches: [DrugMatch] = []
    @State private var isScanning = true

    @State private var resolved: [ResolvedMedication] = []
    @State private var unmatched: [String] = []
    @State private var showResults = false

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(permission == .authorized ? .white : Color.stanford)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            privacyNoticeIsFirstRun = false
                            showPrivacyNotice = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(permission == .authorized ? .white : Color.stanford)
                        }
                        .accessibilityLabel("How this app handles patient information")
                    }
                }
                .navigationDestination(isPresented: $showResults) {
                    // Saving closes the whole scan flow and lands on Home.
                    ResultsView(medications: resolved, unmatched: unmatched, onSaved: { dismiss() })
                        .environmentObject(caseStore)
                }
        }
        .onAppear(perform: start)
        .sheet(isPresented: $showPrivacyNotice) {
            PrivacyNotice(isFirstRun: privacyNoticeIsFirstRun) {
                showPrivacyNotice = false
            }
        }
        .onChange(of: isScanning) { scanning in
            guard !scanning, !scannedMatches.isEmpty else { return }
            let outcome = MedicationResolver.resolve(matches: scannedMatches)
            resolved = outcome.medications
            unmatched = outcome.unmatched
            showResults = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch permission {
        case .checking:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

        case .authorized:
            // Secure container: the live preview and detected-count chrome
            // are blacked out in screenshots and recordings.
            ScannerView(scannedMeds: $scannedMatches, isScanning: $isScanning)
                .ignoresSafeArea()
                .screenCaptureProtected()
                .ignoresSafeArea()
                .screenCaptureNotice()

        case .denied:
            permissionMessage(
                title: "Camera access is off",
                body: "Scanning needs the camera. Turn it on in Settings, or enter medications manually.",
                showSettingsButton: true)

        case .restricted:
            permissionMessage(
                title: "Camera unavailable",
                body: "Camera access is restricted on this device. You can still enter medications manually.",
                showSettingsButton: false)
        }
    }

    // MARK: Start

    private func start() {
        // The explainer comes before the camera on first run, so the user has
        // read what happens to the image before any frame is captured.
        if !PrivacyNoticeStore.hasAcknowledged {
            privacyNoticeIsFirstRun = true
            showPrivacyNotice = true
        }
        checkPermission()
    }

    private func checkPermission() {
        #if targetEnvironment(simulator)
        // No camera in the Simulator; the scanner shows a built-in sample page.
        permission = .authorized
        return
        #endif
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .authorized
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    permission = granted ? .authorized : .denied
                }
            }
        case .denied:
            permission = .denied
        case .restricted:
            permission = .restricted
        @unknown default:
            permission = .denied
        }
    }

    private func permissionMessage(title: String,
                                   body: String,
                                   showSettingsButton: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.app(40))
                .foregroundColor(.inkTertiary)

            Text(title)
                .font(.app(18, .semibold))
                .foregroundColor(.inkPrimary)

            Text(body)
                .font(.app(14))
                .foregroundColor(.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if showSettingsButton {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.app(16, .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 13)
                        .background(Color.actionGreen)
                        .cornerRadius(12)
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.stanfordLight)
    }
}
