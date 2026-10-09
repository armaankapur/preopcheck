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
  PatientIdentity.swift         decides which scanned lines identify the patient (name, DOB, MRN)
  RedactionOverlayView.swift    the blur bars the scanner draws over those lines
  EntryView.swift               typing drug names by hand
  DrugMatcher.swift             turns text into drugs (exact, salt-stripped, and fuzzy matching)
  DrugLexicon.swift             big FDA name list; only answers "is this word a drug at all?"
  DrugNames.txt                 the data DrugLexicon loads (generated, do not edit by hand)
  MedicationResolver.swift      one front door for "text -> drugs" (manual, scan, saved case)
  MedicationDatabase.swift      THE CLINICAL DATA: every drug and its pre-op instruction
  ResultsView.swift             results screen: Hold / Consult / Take as directed, Save Case
  CaseStore.swift               saved cases, stored on the phone in UserDefaults
  PrivacyNotice.swift           first-run privacy explainer
  ScreenCaptureProtection.swift blacks out results in screenshots / screen recordings
  Theme.swift                   colors and font sizes
  Info.plist, Assets.xcassets   app settings, icon, colors
PreOpCheckTests/                tests (DrugMatcherTests.swift covers the matcher, PatientIdentityTests.swift the privacy blur; nothing else yet)
PreOpCheck.xcodeproj/           Xcode project
tools/build_drug_lexicon.py     rebuilds DrugNames.txt from the FDA drug directory
docs/                           README screenshot, plus docs/worklog/ (dated notes on what was done)
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

## Design rules

These keep the code easy to change. Follow them on every task.

1. **Each fact lives in one place.** The test: "if this changes, how many files do I
   touch?" The answer should be one.
   - Colors, fonts and spacing come from `Theme.swift`. Don't write a raw color or
     font size in a view; add a named one to `Theme.swift` and use that.
   - Clinical rules and word lists (drugs, hold times, section headings, stop words)
     live in `MedicationDatabase.swift` or a small file of their own, never inside a
     view or the camera code.
2. **Views only display.** Any decision about which drug was found or what instruction
   it gets lives outside the views, in plain code that can be tested without the screen.
3. **Don't build for futures that haven't arrived.** No new protocol, generic type or
   settings option until there are two real uses for it. Simple and direct beats flexible.
4. **One job per file.** If a file is past roughly 400 lines or is doing more than one
   job, say so and propose a split before adding to it. Known offenders today:
   `ScannerView.swift` and `ResultsView.swift`. Don't make them bigger without asking.
5. **Reuse before you write.** Check whether something similar already exists and use
   it. Don't copy-paste a block into a second place; move it somewhere shared.
6. **Clear names, and comments that say why.** A comment explains the reason for a
   choice, not what the line does.
7. **Fail loudly.** Never hide an error or quietly fall back to a default in clinical
   code. A visible failure is better than a wrong answer that looks right.
8. **Stay in scope.** Change only what the task needs. If you spot something else worth
   fixing, mention it instead of fixing it.

## UI work

Applies to any change a user can see.

**What good looks like here.** The reader is a busy clinician. The verdict (hold, consult,
take) must be readable correctly at a glance. Clarity beats style.

- Follow Apple's Human Interface Guidelines. Use standard iOS controls and system
  spacing before inventing a custom one.
- Colors and fonts come from `Theme.swift` (see Design rules). Fonts go through
  `Font.app` so the whole app scales together.
- Anything tappable is at least 44 x 44 points.
- Never rely on color alone to carry a verdict; pair it with text.
- Text must not be cut off or overlap at larger text sizes.
- It must work on iPhone and iPad, portrait and landscape.

**Look at it, don't guess.** Never call UI work done from reading the code alone.

1. Make sure the view has an Xcode preview (a small live render of one screen) with
   realistic content: long drug names, many rows, an empty state.
2. Render the preview and look at the picture.
3. Write down what is wrong: cramped or uneven spacing, misalignment, cut-off text,
   weak contrast, unclear order of importance, anything that looks unlike a normal iOS app.
4. Fix it, render again, and compare with the previous picture.
5. Repeat until a pass turns up nothing worth fixing. If you are still going after about
   five passes, stop and show Armaan where it stands instead of continuing to tweak.
6. Check at least one iPhone and one iPad size, plus landscape, before finishing.

**Limits.** If a preview will not render, say so; do not report the UI as checked. The
scanner screen needs a real camera, so its live behavior can only be checked on Armaan's
phone. Report which screens and sizes you actually looked at, and what you changed
between passes.

## How to work on a task

1. **Plan first.** For anything beyond a one-line fix, list the files you will touch
   and why, in plain English, and wait for Armaan's yes before writing code.
2. **One thing per change.** A feature, a fix and a tidy-up are three separate changes,
   each small enough to read in one sitting.
3. **Tests for anything clinical.** A change to matching, resolving, section exclusion
   or severity bucketing comes with a test that fails before the change and passes
   after. Use real examples (real drug names, real OCR slips), not made-up easy ones.
4. **Check it yourself.** Build, and run the tests, before saying it's done.
5. **Report honestly.** Finish with: what changed, what you verified and how, what you
   did NOT verify (anything camera-related needs Armaan's phone), and anything you were
   unsure about.
6. **Keep this file true.** If you add, remove or rename a file, update the project
   structure above in the same change.

## Hard rules

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
