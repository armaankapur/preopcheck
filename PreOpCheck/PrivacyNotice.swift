//
//  PrivacyNotice.swift
//  Stanford Preoperative Medication
//
//  Shown full-screen the first time the scanner is opened, and available on
//  demand after that from the info button on the scan screen.
//
//  Design intent: this is the app's actual privacy mechanism made legible.
//  It replaces the on-screen blur, which obscured the camera preview and gave
//  the impression that the image was being processed and concealed. Nothing
//  about the blur protected anything: the paper document is already visible in
//  the room, and the real protections are that nothing is written to disk and
//  nothing leaves the device.
//
//  The wording is deliberately short enough that a clinician can repeat it out
//  loud to a patient who asks what the app is doing, or turn the phone around
//  and show them this screen.
//

import SwiftUI

// MARK: - Seen-state

enum PrivacyNoticeStore {
    private static let key = "preop.privacyNotice.acknowledged.v1"

    static var hasAcknowledged: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func acknowledge() {
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Exposed for testing and for a future "show this again" setting.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - View

struct PrivacyNotice: View {
    /// First run shows a single "Got it" that records acknowledgement.
    /// Re-reads show "Done" and change nothing.
    var isFirstRun: Bool
    var onDismiss: () -> Void

    private struct Point {
        let icon: String
        let title: String
        let body: String
    }

    private let points: [Point] = [
        Point(icon: "iphone",
              title: "Everything happens on this phone",
              body: "Text is read using the phone's built-in text recognition. "
                  + "Nothing is sent to a server, and the app works with no internet connection."),
        Point(icon: "photo.badge.exclamationmark",
              title: "No photo is ever saved",
              body: "The camera is never recording. Frames are read and discarded immediately. "
                  + "Nothing is written to your camera roll or to the app."),
        Point(icon: "pills",
              title: "Only medication names are kept",
              body: "Any other text on the page, including patient names, dates of birth and "
                  + "record numbers, is discarded and never stored.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    Image(systemName: "lock.shield")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundColor(.stanford)
                        .padding(.top, 44)
                        .padding(.bottom, 18)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("How this app handles patient information")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundColor(.inkPrimary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 32)

                    ForEach(points, id: \.title) { point in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: point.icon)
                                .font(.system(size: 19))
                                .foregroundColor(.stanford)
                                .frame(width: 28, alignment: .center)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(point.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.inkPrimary)
                                Text(point.body)
                                    .font(.system(size: 14))
                                    .foregroundColor(.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.bottom, 24)
                    }

                    Text("This screen can be shown to a patient who asks what the app does. "
                       + "You can reopen it any time from the info button on the scan screen.")
                        .font(.system(size: 13))
                        .foregroundColor(.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 28)
            }

            VStack(spacing: 10) {
                Button {
                    if isFirstRun { PrivacyNoticeStore.acknowledge() }
                    onDismiss()
                } label: {
                    Text(isFirstRun ? "Got it" : "Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.stanford)
                        .cornerRadius(14)
                }

                Text("\(GuidelineMeta.title), revised \(GuidelineMeta.revision)")
                    .font(.system(size: 11))
                    .foregroundColor(.inkTertiary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(Color.white)
        }
        .background(Color.white)
    }
}
