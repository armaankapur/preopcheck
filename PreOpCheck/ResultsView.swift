//
//  ResultsView.swift
//  Stanford Preoperative Medication
//
//  Three buckets, top to bottom: Hold, Consult, Take as directed.
//
//  A medication whose guidance branches (diuretics, GLP-1 agonists, cannabis)
//  is a Consult. The app never asks the clinician to pick a branch. Instead
//  the card carries a read-only "Considerations" box listing every branch and
//  its instruction, and the clinician decides with the patient in front of
//  them. Nothing on this screen blocks saving.
//
//  The whole scroll area sits inside a secure container so screenshots and
//  recordings of patient medication data come out black.
//

import SwiftUI

struct ResultsView: View {
    let medications: [ResolvedMedication]
    var unmatched: [String] = []
    /// Called once the case is saved, after the button has shown "Case
    /// Saved" for a moment. Each presenter uses it to return to Home, since
    /// only the presenter knows whether this screen sits in a sheet, a
    /// full-screen cover or the main navigation stack.
    var onSaved: (() -> Void)? = nil

    @EnvironmentObject var caseStore: CaseStore
    @State private var showUnmatched = false
    @State private var saved = false
    /// Rows the clinician has tapped open to see the full notes.
    @State private var expanded: Set<String> = []
    /// Grouped by Hold / Consult / Take (default), or in the order the drugs
    /// appeared on the page or were typed.
    @State private var grouped = true

    // MARK: Buckets

    private var holds: [ResolvedMedication] {
        medications.filter { $0.action.severity == .hold }
    }
    private var consults: [ResolvedMedication] {
        medications.filter { $0.action.severity == .consult }
    }
    private var takeAsDirected: [ResolvedMedication] {
        medications.filter { $0.action.severity == .takeAsDirected }
    }
    private var interactions: [(rule: InteractionRule, drug: Drug)] {
        MedicationDatabase.applyInteractionRules(to: medications.map { $0.match.drug })
    }
    /// Source order: top of the scanned page first, or as typed.
    private var inOrder: [ResolvedMedication] {
        medications.sorted { $0.order < $1.order }
    }

    private func verdictColor(for med: ResolvedMedication) -> Color {
        switch med.action.severity {
        case .hold:           return .stanford
        case .consult:        return .orange
        case .takeAsDirected: return .actionGreen
        }
    }

    /// Switch between the grouped view (on, the default) and the order the
    /// drugs appeared on the page or were typed (off). Resets to grouped
    /// each time the screen opens. A small bubble, just the word and the
    /// switch, tucked to the right of the count line.
    private var viewModePicker: some View {
        HStack(spacing: 4) {
            Text("Sort")
                .font(.app(13, .semibold))
                .foregroundColor(.inkPrimary)
            Toggle("Sort", isOn: $grouped.animation())
                .labelsHidden()
                .controlSize(.small)
                .tint(.actionGreen)
        }
        .accessibilityHint("On groups by hold, consult and take as directed. Off keeps the order scanned or typed.")
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .background(Color.white)
        .cornerRadius(10)
    }

    // MARK: Body

    var body: some View {
        scrollContent
            .environmentObject(caseStore)
            .screenCaptureProtected()
            .background(Color.stanfordLight)
        .screenCaptureNotice()
        .navigationTitle("Pre-op Check")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                summaryCard
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                ForEach(interactions, id: \.rule.id) { item in
                    interactionBanner(item.rule)
                }

                HStack(spacing: 12) {
                    countLine
                    Spacer(minLength: 8)
                    viewModePicker
                }
                .padding(.horizontal, 16)

                if grouped {
                    if !holds.isEmpty {
                        section("Hold", accent: .stanford, prominent: true) {
                            ForEach(holds) { med in
                                medicationRow(med, verdictColor: .stanford, prominent: true)
                                divider(after: med, in: holds, inset: 20)
                            }
                        }
                    }

                    if !consults.isEmpty {
                        section("Consult", accent: .orange, prominent: true) {
                            ForEach(consults) { med in
                                medicationRow(med, verdictColor: .orange, prominent: true)
                                divider(after: med, in: consults, inset: 20)
                            }
                        }
                    }

                    if !takeAsDirected.isEmpty {
                        section("Take as directed", accent: .actionGreen, prominent: false) {
                            ForEach(takeAsDirected) { med in
                                medicationRow(med, verdictColor: .actionGreen, prominent: false)
                                divider(after: med, in: takeAsDirected, inset: 16)
                            }
                        }
                    }
                } else if !inOrder.isEmpty {
                    // One list in source order; each pill carries its own colour.
                    section("Medications", accent: .inkSecondary, prominent: true) {
                        ForEach(inOrder) { med in
                            medicationRow(med, verdictColor: verdictColor(for: med), prominent: true)
                            divider(after: med, in: inOrder, inset: 20)
                        }
                    }
                }

                if !unmatched.isEmpty {
                    collapsible("NOT IN DATABASE", count: unmatched.count,
                                isExpanded: $showUnmatched) {
                        ForEach(unmatched, id: \.self) { text in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(text)
                                        .font(.app(15, .semibold))
                                        .foregroundColor(.inkPrimary)
                                    Text("Not in the PARC guideline. Verify manually.")
                                        .font(.app(13))
                                        .foregroundColor(.orange)
                                }
                                Spacer()
                            }
                            .padding(16)
                        }
                    }
                }

                disclaimer
            }
            // Same column width everywhere: on iPad and in landscape the
            // content stays a phone-like column, centred, instead of
            // stretching the name and pill to opposite edges.
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(Color.stanfordLight)
        // Save Case stays on screen however long the list is, so the
        // clinician never has to scroll to find it.
        .safeAreaInset(edge: .bottom) {
            saveButton
                .padding(.vertical, 8)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .background(Color.stanfordLight)
        }
    }

    // MARK: Summary

    /// Always Stanford red. There is no unresolved state any more, so there
    /// is nothing for a second colour to signal.
    private var summaryCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.app(22, .semibold))
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 3) {
                Text(summaryHeadline)
                    .font(.app(17, .bold))
                    .foregroundColor(.white)
                Text(summaryLine)
                    .font(.app(14))
                    .foregroundColor(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.stanford)
        .cornerRadius(14)
    }

    private var summaryHeadline: String {
        let h = holds.count, c = consults.count
        if h > 0 && c > 0 { return "\(h) to hold, \(c) to consult" }
        if h > 0 { return "\(h) to hold" }
        if c > 0 { return "\(c) to consult" }
        return "No holds or consults"
    }

    private var summaryLine: String {
        if !holds.isEmpty {
            let n = holds.count
            return "\(n) medication\(n > 1 ? "s" : "") require\(n > 1 ? "" : "s") a hold before surgery. Review every card below with the patient."
        }
        if !consults.isEmpty {
            return "No holds, but consults are required. Review the considerations on each card."
        }
        return "All medications may be taken as directed. Confirm the list with the patient."
    }

    /// The total, as one small line above the categories.
    private var countLine: some View {
        let n = medications.count
        var parts = ["\(n) medication\(n == 1 ? "" : "s")"]
        if !holds.isEmpty { parts.append("\(holds.count) hold") }
        if !consults.isEmpty { parts.append("\(consults.count) consult") }
        if !takeAsDirected.isEmpty { parts.append("\(takeAsDirected.count) take as directed") }
        return Text(parts.joined(separator: " · "))
            .font(.app(12, .medium))
            .foregroundColor(.inkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    // MARK: Rows

    /// One line per drug: the name on the left, the verdict on the right.
    /// Tapping the row shows the full notes (class, detail, considerations,
    /// concern, half-life, pediatric cardiac) underneath, so nothing from the
    /// guideline is lost, it is just folded away.
    private func medicationRow(_ med: ResolvedMedication,
                               verdictColor: Color,
                               prominent: Bool) -> some View {
        let drug = med.match.drug
        let isExpanded = expanded.contains(med.id)
        let size: CGFloat = prominent ? 16 : 15
        // 12 points above and below a one-line name keeps the row at the
        // 44-point tap height while fitting more rows on a page.
        let pad: CGFloat = 12

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation {
                    if isExpanded { expanded.remove(med.id) } else { expanded.insert(med.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    // Generic name only. Brand names live in the expanded notes.
                    Text(drug.generic)
                        .font(.app(size, .semibold))
                        .foregroundColor(.inkPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if med.match.needsVerification { verifyBadge }
                    Spacer(minLength: 8)
                    // The verdict pill never shrinks or truncates; the name gives way first.
                    Text(verdict(for: med.action))
                        .font(.app(prominent ? 12 : 11, .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, prominent ? 10 : 8)
                        .padding(.vertical, 4)
                        .background(verdictColor)
                        .cornerRadius(20)
                        .fixedSize()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.app(11))
                        .foregroundColor(.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                details(for: med)
            }
        }
        .padding(pad)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The short verdict on the pill at the right of the one-line row:
    /// how long to hold, CONSULT, or TAKE. The full instruction
    /// (`Action.label`) is in the expanded notes.
    private func verdict(for action: Action) -> String {
        switch action {
        case .takeAsDirected:    return "TAKE"
        case .holdDayOfSurgery:  return "HOLD DOS"
        case .holdHours(let h):  return "\(h)H"
        case .holdDays(let d):   return "\(d)D"
        case .consult, .variable: return "CONSULT"
        }
    }

    /// Everything that used to sit under the name, shown when the row is tapped.
    @ViewBuilder
    private func details(for med: ResolvedMedication) -> some View {
        let drug = med.match.drug

        // The full instruction, since the pill only shows the short form.
        Text(med.action.label)
            .font(.app(14, .semibold))
            .foregroundColor(.stanford)
            .fixedSize(horizontal: false, vertical: true)

        if !drug.brands.isEmpty {
            Text("Also known as: \(drug.brands.joined(separator: ", "))")
                .font(.app(13))
                .foregroundColor(.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Text(drug.drugClass)
            .font(.app(13))
            .foregroundColor(.inkSecondary)

        if let detail = drug.guidance.detail {
            Text(detail)
                .font(.app(13))
                .foregroundColor(.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !med.considerations.isEmpty {
            considerationsBox(med.considerations)
        }

        if let concern = drug.guidance.concern {
            Text("Concern: \(concern)")
                .font(.app(12))
                .foregroundColor(.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let half = drug.halfLifeHours {
            Text("Half-life \(half, specifier: "%.1f") h")
                .font(.app(11))
                .foregroundColor(.inkTertiary)
        }

        if let peds = drug.guidance.pediatricCardiac {
            pediatricNote(peds)
        }
    }

    /// Read-only list of every branch of a drug's guidance. Replaces the old
    /// pathway picker: the clinician reads the options and decides.
    private func considerationsBox(_ branches: [Conditional]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.app(13, .semibold))
                Text("Considerations")
                    .font(.app(14, .semibold))
            }
            .foregroundColor(.inkPrimary)

            if let question = branches.first?.question {
                Text(question)
                    .font(.app(13, .medium))
                    .foregroundColor(.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(branches) { branch in
                VStack(alignment: .leading, spacing: 2) {
                    (Text(branch.whenLabel + ": ").fontWeight(.semibold)
                     + Text(branch.action.label))
                        .font(.app(14))
                        .foregroundColor(.inkPrimary)
                    if let detail = branch.detail {
                        Text(detail)
                            .font(.app(13))
                            .foregroundColor(.inkSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.stanfordLight)
        .cornerRadius(10)
        .padding(.top, 4)
    }

    private var verifyBadge: some View {
        Text("VERIFY")
            .font(.app(9, .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.gray)
            .cornerRadius(4)
    }

    private func pediatricNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "heart.text.square")
                .font(.app(11))
                .foregroundColor(.stanford)
            Text("Pediatric Cardiac Anesthesia: \(text)")
                .font(.app(12))
                .foregroundColor(.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.stanfordLight)
        .cornerRadius(8)
    }

    private func interactionBanner(_ rule: InteractionRule) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            Text(rule.message)
                .font(.app(13, .medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(14)
        .background(Color.stanford)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    // MARK: Layout helpers

    /// Hold and Consult are prominent: larger header, larger card radius.
    /// Take as directed uses the quieter style but is always expanded.
    private func section<Content: View>(_ title: String,
                                        accent: Color,
                                        prominent: Bool,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: prominent ? 10 : 8, height: prominent ? 10 : 8)
                Text(title.uppercased())
                    .font(.app(prominent ? 14 : 13, prominent ? .bold : .semibold))
                    .foregroundColor(prominent ? .inkPrimary : .inkSecondary)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) { content() }
                .background(Color.white)
                .cornerRadius(14)
                .padding(.horizontal, 16)
        }
    }

    private func collapsible<Content: View>(_ title: String,
                                            count: Int,
                                            isExpanded: Binding<Bool>,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { isExpanded.wrappedValue.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .font(.app(13, .semibold))
                        .foregroundColor(.inkSecondary)
                    Spacer()
                    Text("\(count)")
                        .font(.app(14))
                        .foregroundColor(.inkSecondary)
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.app(12))
                        .foregroundColor(.inkSecondary)
                }
                .padding(.horizontal, 16)
            }

            if isExpanded.wrappedValue {
                VStack(spacing: 0) { content() }
                    .background(Color.white)
                    .cornerRadius(14)
                    .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func divider(after med: ResolvedMedication,
                         in list: [ResolvedMedication],
                         inset: CGFloat) -> some View {
        if med.id != list.last?.id {
            Divider().padding(.leading, inset)
        }
    }

    // MARK: Actions

    private var saveButton: some View {
        Button {
            caseStore.save(medications)
            saved = true
            // Let "Case Saved" register before leaving the screen.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.7))
                onSaved?()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                Text(saved ? "Case Saved" : "Save Case")
                    .font(.app(17, .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(saved ? Color.gray : Color.actionGreen)
            .cornerRadius(14)
        }
        .disabled(saved)
        .padding(.horizontal, 16)
    }

    private var disclaimer: some View {
        VStack(spacing: 6) {
            Text("Reference: \(GuidelineMeta.title), revised \(GuidelineMeta.revision). \(GuidelineMeta.source).")
                .font(.app(11, .medium))
            Text(GuidelineMeta.scope)
                .font(.app(11, .semibold))
                .foregroundColor(.stanford)
            Text("For clinical decision support only. Not a substitute for professional judgment. Always verify with the attending anesthesiologist.")
                .font(.app(11))
        }
        .foregroundColor(.inkSecondary)
        .multilineTextAlignment(.center)
        .padding(12)
        .background(Color.white)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Previews

#Preview("Short list") {
    let outcome = MedicationResolver.demo()
    NavigationStack {
        ResultsView(medications: outcome.medications, unmatched: outcome.unmatched)
            .environmentObject(CaseStore())
    }
}

#Preview("Long Epic-style list") {
    let outcome = MedicationResolver.resolve(lines: [
        "Acetaminophen (Tylenol) 500 mg", "Amlodipine (Norvasc) 5 mg", "Atorvastatin (Lipitor) 20 mg",
        "Losartan (Cozaar) 50 mg", "Metformin (Glucophage) 500 mg", "Omeprazole (Prilosec) 20 mg",
        "Sertraline (Zoloft) 50 mg", "Albuterol HFA (ProAir HFA)", "Fluticasone (Flonase)",
        "Lisinopril 10 mg", "Furosemide 20 mg", "Enoxaparin 40 mg", "Metoprolol succinate 25 mg",
        "Ibuprofen 400 mg", "Semaglutide 1 mg weekly", "Cetirizine 10 mg", "Montelukast 5 mg"
    ])
    NavigationStack {
        ResultsView(medications: outcome.medications, unmatched: outcome.unmatched)
            .environmentObject(CaseStore())
    }
}
