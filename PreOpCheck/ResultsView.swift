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

    @EnvironmentObject var caseStore: CaseStore
    @State private var showUnmatched = false
    @State private var saved = false

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

    // MARK: Body

    var body: some View {
        SecureContainer {
            scrollContent
                .environmentObject(caseStore)
        }
        .background(Color.stanfordLight)
        .screenCaptureNotice()
        .navigationTitle("Pre-op Check")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryCard
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                ForEach(interactions, id: \.rule.id) { item in
                    interactionBanner(item.rule)
                }

                countLine

                if !holds.isEmpty {
                    section("Hold", accent: .stanford, prominent: true) {
                        ForEach(holds) { med in
                            medicationRow(med, badge: badgeText(for: med),
                                          badgeColor: .stanford, prominent: true)
                            divider(after: med, in: holds, inset: 20)
                        }
                    }
                }

                if !consults.isEmpty {
                    section("Consult", accent: .orange, prominent: true) {
                        ForEach(consults) { med in
                            medicationRow(med, badge: "CONSULT",
                                          badgeColor: .orange, prominent: true)
                            divider(after: med, in: consults, inset: 20)
                        }
                    }
                }

                if !takeAsDirected.isEmpty {
                    section("Take as directed", accent: .actionGreen, prominent: false) {
                        ForEach(takeAsDirected) { med in
                            medicationRow(med, badge: "TAKE",
                                          badgeColor: .actionGreen, prominent: false)
                            divider(after: med, in: takeAsDirected, inset: 16)
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

                saveButton
                disclaimer
            }
        }
        .background(Color.stanfordLight)
    }

    // MARK: Summary

    /// Always Stanford red. There is no unresolved state any more, so there
    /// is nothing for a second colour to signal.
    private var summaryCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.app(26, .semibold))
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 4) {
                Text(summaryHeadline)
                    .font(.app(19, .bold))
                    .foregroundColor(.white)
                Text(summaryLine)
                    .font(.app(14))
                    .foregroundColor(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.stanford)
        .cornerRadius(16)
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
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
    }

    // MARK: Rows

    private func medicationRow(_ med: ResolvedMedication,
                               badge: String,
                               badgeColor: Color,
                               prominent: Bool) -> some View {
        let drug = med.match.drug
        let nameSize: CGFloat = prominent ? 19 : 15
        let pad: CGFloat = prominent ? 20 : 16

        // The badge shares a line with the name only, so everything below
        // (detail, considerations, notes) gets the full card width.
        return VStack(alignment: .leading, spacing: prominent ? 6 : 4) {
            HStack(alignment: .top, spacing: 10) {
                Text(drug.displayName)
                    .font(.app(nameSize, .semibold))
                    .foregroundColor(.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(badge)
                    .font(.app(prominent ? 11 : 10, .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, prominent ? 11 : 9)
                    .padding(.vertical, prominent ? 6 : 5)
                    .background(badgeColor)
                    .cornerRadius(20)
                    .fixedSize()
            }

            HStack(spacing: 6) {
                Text(drug.drugClass)
                    .font(.app(prominent ? 13 : 12))
                    .foregroundColor(.inkSecondary)
                if med.match.needsVerification { verifyBadge }
            }

            Text(med.action.label)
                .font(.app(prominent ? 16 : 13, .semibold))
                .foregroundColor(.stanford)
                .fixedSize(horizontal: false, vertical: true)

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
        .padding(pad)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func badgeText(for med: ResolvedMedication) -> String {
        switch med.action {
        case .holdDayOfSurgery: return "HOLD DOS"
        case .holdHours(let h):  return "\(h)H"
        case .holdDays(let d):   return "\(d)D"
        default:                 return "HOLD"
        }
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
        VStack(alignment: .leading, spacing: prominent ? 10 : 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: prominent ? 12 : 8, height: prominent ? 12 : 8)
                Text(prominent ? title.uppercased() : title.uppercased())
                    .font(.app(prominent ? 17 : 13, prominent ? .bold : .semibold))
                    .foregroundColor(prominent ? .inkPrimary : .inkSecondary)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) { content() }
                .background(Color.white)
                .cornerRadius(prominent ? 18 : 14)
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
        .padding(.bottom, 32)
    }
}
