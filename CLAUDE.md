# CLAUDE.md

Guidance for Claude (and any other coding agent) working in this repo.

## Who you're working with

Armaan owns this fork. He is newer to programming: explain everything in plain English,
define any technical term the first time you use it, and lead with the answer.

## What the app does

PreOpCheck is an iPhone app for clinicians. You point the camera at a printed medication
list (or type the drug names in), and for each drug it shows what to do before surgery:
take as usual, hold for a set time, hold on the day of surgery, or consult a named team.
The rules come from the PARC Pre-Operative Medication Guidelines (Stanford Children's
Health, Pediatric Anesthesia & Pain Medicine). They are **pediatric** guidelines.

Everything runs on the phone. There is no server, no network code, and no third-party
libraries. Swift + SwiftUI, with AVFoundation (camera) and Vision (Apple's on-device text
recognition).

## Project structure

```
PreOpCheck/                     the app itself
  PreOpCheckApp.swift           app starts here; creates the CaseStore
  ContentView.swift             root navigation, shows HomeView
  HomeView.swift                home screen: Scan, Enter Manually, recent cases
  CameraWrapperView.swift       scan flow: camera permission, privacy notice, scanner, results
  ScannerView.swift             live camera + text recognition + allergy-section exclusion
  EntryView.swift               typing drug names by hand
  DrugMatcher.swift             turns text into drugs (exact, salt-stripped, and fuzzy matching)
  MedicationResolver.swift      one front door for "text -> drugs" (manual, scan, saved case)
  MedicationDatabase.swift      THE CLINICAL DATA: every drug and its pre-op instruction
  ResultsView.swift             results screen: Hold / Consult / Take as directed, Save Case
  CaseStore.swift               saved cases, stored on the phone in UserDefaults
  PrivacyNotice.swift           first-run privacy explainer
  ScreenCaptureProtection.swift blacks out results in screenshots / screen recordings
  Theme.swift                   colors and font sizes
  Info.plist, Assets.xcassets   app settings, icon, colors
PreOpCheckTests/                test target (currently only Xcode's empty template)
PreOpCheck.xcodeproj/           Xcode project
docs/                           screenshot used by README
```

Flow: camera or typed text -> `DrugMatcher` -> `MedicationResolver` -> `ResultsView`
-> optionally saved by `CaseStore`.

## Build, run, test

- Requires the full **Xcode** app (the command-line tools alone are not enough).
- Scheme: **PreOpCheck**. Test target: **PreOpCheckTests**.
- Deployment target in the project file is **iOS 26.4** (the README agrees). If you
  expected 16.4, check with Armaan before changing it.
- Open in Xcode: `open PreOpCheck.xcodeproj`, pick the PreOpCheck scheme and a device, press Run.
- Command line build (simulator):
  `xcodebuild -project PreOpCheck.xcodeproj -scheme PreOpCheck -destination 'generic/platform=iOS Simulator' build`
- Command line tests (pick a simulator that exists on the machine; `xcrun simctl list devices`):
  `xcodebuild -project PreOpCheck.xcodeproj -scheme PreOpCheck -destination 'platform=iOS Simulator,name=iPhone 17' test`
- Running on a real iPhone needs a signing team set under Signing & Capabilities.

## Rules

1. **Never change medication data or protocol logic without telling Armaan first.**
   This is clinical content. That means anything in `MedicationDatabase.swift`
   (drugs, brands, actions, hold times, conditionals, interaction rules, guideline
   revision) and any logic that decides which drug or instruction a patient gets
   (`DrugMatcher.swift`, `MedicationResolver.swift`, the section exclusion in
   `ScannerView.swift`, severity bucketing in `ResultsView.swift`). Describe the
   proposed change and why, and wait for a yes.
2. **The camera only works on a real iPhone.** Scanning cannot be tested in the simulator.
3. **The simulator supports manual entry only.** Use "Enter Manually" to test there.
4. Patient data must never leave the device: no network calls, analytics, crash
   reporters, logging of scanned text, or cloud sync without Armaan's explicit approval.
5. Don't run `git push`, and don't touch files outside this repo.
