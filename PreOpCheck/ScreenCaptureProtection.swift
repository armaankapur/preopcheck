//
//  ScreenCaptureProtection.swift
//  Stanford Preoperative Medication
//
//  Two layers of protection for screens that show patient medication data.
//
//  1. SecureContainer renders its content inside the canvas view of a
//     UITextField with isSecureTextEntry on. iOS excludes that canvas from
//     screenshots, screen recordings and AirPlay mirroring, so a capture of
//     a protected screen comes out black. iOS has no public API to refuse a
//     screenshot outright; this is the closest supported behaviour.
//
//  2. `screenCaptureNotice()` listens for the screenshot notification and for
//     screen-recording state changes, and shows a short overlay explaining
//     that captures are not permitted. The overlay sits outside the secure
//     container so the person holding the phone actually sees it.
//
//  Apply both to any view that shows scanned content or results.
//

import SwiftUI
import UIKit
import Combine

// MARK: - Switch

/// Master switch for both layers below. Off for now so testers can take
/// screenshots and screen recordings while the UI is being reviewed.
/// Set back to `true` before any build that may hold real patient data.
enum ScreenCaptureProtection {
    static let isEnabled = false
}

// MARK: - Secure container

/// Hosts SwiftUI content inside a secure text field's canvas layer.
///
/// The hosted content is a separate SwiftUI hierarchy, so the enclosing
/// environment (environment objects included) is forwarded explicitly on
/// every update. Navigation modifiers still need to be applied outside the
/// container, because they talk to the enclosing navigation stack.
struct SecureContainer<Content: View>: UIViewRepresentable {
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = true
        field.layoutIfNeeded()
        context.coordinator.secureField = field

        let host = UIHostingController(rootView: rootView(context: context))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.host = host

        // The first subview of a secure UITextField is the canvas whose layer
        // carries the capture-exclusion flag. Re-parent it and draw inside it.
        let canvas = field.subviews.first ?? UIView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.isUserInteractionEnabled = true
        canvas.backgroundColor = .clear
        container.addSubview(canvas)
        canvas.addSubview(host.view)

        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            host.view.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: canvas.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: canvas.bottomAnchor)
        ])

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.host?.rootView = rootView(context: context)
    }

    private func rootView(context: Context) -> AnyView {
        AnyView(content().environment(\.self, context.environment))
    }

    final class Coordinator {
        /// Retained because the canvas view keeps only a weak link back to it.
        var secureField: UITextField?
        var host: UIHostingController<AnyView>?
    }
}

extension View {
    /// Wraps the view so it is blacked out in screenshots and recordings.
    /// Passes the view through untouched while the master switch is off.
    @ViewBuilder
    func screenCaptureProtected() -> some View {
        if ScreenCaptureProtection.isEnabled {
            SecureContainer { self }
        } else {
            self
        }
    }
}

// MARK: - Capture notice

private struct ScreenCaptureNotice: ViewModifier {
    @State private var visible = false
    @State private var hideTask: Task<Void, Never>?

    private let screenshot = NotificationCenter.default
        .publisher(for: UIApplication.userDidTakeScreenshotNotification)
    private let captureChanged = NotificationCenter.default
        .publisher(for: UIScreen.capturedDidChangeNotification)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if visible { banner }
            }
            .animation(.easeInOut(duration: 0.2), value: visible)
            .onReceive(screenshot) { _ in show(briefly: true) }
            .onReceive(captureChanged) { _ in
                if Self.isBeingCaptured { show(briefly: false) } else { hide() }
            }
            .onAppear { if Self.isBeingCaptured { show(briefly: false) } }
    }

    private var banner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "eye.slash.fill")
                .font(.app(18, .semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text("Screenshots aren't permitted")
                    .font(.app(15, .semibold))
                Text("Screen captures are blocked to protect patient privacy.")
                    .font(.app(13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundColor(.white)
        .padding(16)
        .background(Color.stanford)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityAddTraits(.isStaticText)
    }

    private static var isBeingCaptured: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.screen.isCaptured }
    }

    private func show(briefly: Bool) {
        hideTask?.cancel()
        visible = true
        guard briefly else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            // Keep the banner if a recording started in the meantime.
            if !Self.isBeingCaptured { visible = false }
        }
    }

    private func hide() {
        hideTask?.cancel()
        visible = false
    }
}

extension View {
    /// Shows a brief privacy overlay when a screenshot is taken or screen
    /// recording starts. Apply outside `screenCaptureProtected()` so the
    /// overlay itself is visible on the device. Does nothing while the
    /// master switch is off.
    @ViewBuilder
    func screenCaptureNotice() -> some View {
        if ScreenCaptureProtection.isEnabled {
            modifier(ScreenCaptureNotice())
        } else {
            self
        }
    }
}
