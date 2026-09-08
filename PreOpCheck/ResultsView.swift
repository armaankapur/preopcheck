//
//  ResultsView.swift
//  Stanford Preoperative Medication
//
//  Rewritten for the PARC guidance model.
//
//  The single most important change: a medication with unanswered conditionals
//  is NOT given an answer. It goes into a "Needs your input" section at the top
//  and the clinician picks the branch. The old three-bucket view would have
//  shown one confident answer for furosemide regardless of whether it was
//  prescribed for hypertension or fluid overload, and those go opposite ways.
//

import SwiftUI

struct ResultsView: View {
    @State var medications: [ResolvedMedication]
    var unmatched: [String] = []

    @EnvironmentObject var caseStore: CaseStore
    @State private var showTakeAsDirected = false
    @State private var showUnmatched = false
    @State private var saved = false

    // MARK: Buckets

    private var needsInput: [ResolvedMedication] {
        medications.filter { $0.isUnresolved }
    }
    private var holds: [ResolvedMedication] {
        medications.filter { !$0.isUnresolved && $0.action?.severity == .hold }
    }
    private var consults: [ResolvedMedication] {
        medications.filter { !$0.isUnresolved && $0.action?.severity == .consult }
    }
    private var takeAsDirected: [ResolvedMedication] {
        medications.filter { !$0.isUnresolved && $0.action?.severity == .takeAsDirected }
    }
    private var needsVerification: [ResolvedMedication] {
        medications.filter { $0.match.needsVerification }
    }
    private var interactions: [(rule: InteractionRule, drug: Drug)] {
        MedicationDatabase.applyInteractionRules(to: medications.map { $0.match.drug })
    }
    private var isComplete: Bool { needsInput.isEmpty }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                ForEach(interactions, id: \.rule.id) { item in
                    interactionBanner(item.rule)
                }

                if !needsInput.isEmpty {
                    section("NEEDS YOUR INPUT") {
                        ForEach(needsInput) { med in
                            conditionalRow(med)
                            divider(after: med, in: needsInput)
                        }
                    }
                }

                if !holds.isEmpty {
                    section("HOLD") {
                        ForEach(holds) { med in
                            resolvedRow(med, badge: badgeText(for: med), badgeColor: .red)
                            divider(after: med, in: holds)
                        }
                    }
                }

                if !consults.isEmpty {
                    section("CONSULT BEFORE PROCEEDING") {
                        ForEach(consults) { med in
                            resolvedRow(med, badge: "CONSULT", badgeColor: .orange)
                            divider(after: med, in: consults)
                        }
                    }
                }

                if !takeAsDirected.isEmpty {
                    collapsible("TAKE AS DIRECTED", count: takeAsDirected.count,
                                isExpanded: $showTakeAsDirected) {
                        ForEach(takeAsDirected) { med in
                            resolvedRow(med, badge: "TAKE", badgeColor: Color(hex: "#34C759"))
                            divider(after: med, in: takeAsDirected)
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
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.black)
                                    Text("Not in the PARC guideline. Verify manually.")
                                        .font(.system(size: 13))
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
        .navigationTitle("Pre-op Check")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Summary

    private var summaryCard: some View {
        VStack(spacing: 10) {
            HStack {
                statBox(medications.count, "Total")
                statDivider
                statBox(holds.count, "Hold")
                statDivider
                statBox(needsInput.count, "Needs input")
            }

            Text(summaryLine)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.92))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(summaryColor)
        .cornerRadius(16)
    }

    private var summaryLine: String {
        if !needsInput.isEmpty {
            let n = needsInput.count
            return "\(n) medication\(n > 1 ? "s" : "") cannot be resolved until you answer the questions below"
        }
        if !holds.isEmpty {
            let n = holds.count
            return "\(n) medication\(n > 1 ? "s" : "") require a hold before surgery"
        }
        if !consults.isEmpty { return "No holds, but consults are required" }
        return "All medications may be taken as directed"
    }

    private var summaryColor: Color {
        if !needsInput.isEmpty { return .orange }
        if !holds.isEmpty { return .stanford }
        if !consults.isEmpty { return .orange }
        return Color(hex: "#34C759")
    }

    private func statBox(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(n)")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Divider().frame(height: 40).background(Color.white.opacity(0.4))
    }

    // MARK: Rows

    /// A medication whose guidance branches. No answer is shown until a branch
    /// is chosen. This is the core behavioral change from the old view.
    private func conditionalRow(_ med: ResolvedMedication) -> some View {
        let drug = med.match.drug
        let conditionals = drug.guidance.conditionals
        let question = conditionals.first?.question ?? "Select one"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(drug.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                    Text(drug.drugClass)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if med.match.needsVerification { verifyBadge }
            }

            Text(question)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(.darkGray))

            VStack(spacing: 6) {
                ForEach(conditionals) { branch in
                    Button {
                        choose(branch, for: med.id)
                    } label: {
                        HStack {
                            Text(branch.whenLabel)
                                .font(.system(size: 14))
                                .foregroundColor(.black)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.stanfordLight)
                        .cornerRadius(10)
                    }
                }
            }

            if let peds = drug.guidance.pediatricCardiac {
                pediatricNote(peds)
            }
        }
        .padding(16)
    }

    private func resolvedRow(_ med: ResolvedMedication, badge: String, badgeColor: Color) -> some View {
        let drug = med.match.drug
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(drug.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                    if med.match.needsVerification { verifyBadge }
                }

                Text(drug.drugClass)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                if let action = med.action {
                    Text(action.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.stanford)
                }

                if let branch = med.chosenBranch {
                    Text("Because: \(branch.whenLabel)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                if let detail = med.chosenBranch?.detail ?? drug.guidance.detail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundColor(Color(.darkGray))
                }

                if let concern = drug.guidance.concern {
                    Text("Concern: \(concern)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                if let half = drug.halfLifeHours {
                    Text("Half-life \(half, specifier: "%.1f") h")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if let peds = drug.guidance.pediatricCardiac {
                    pediatricNote(peds)
                }
            }
            Spacer()
            Text(badge)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(badgeColor)
                .cornerRadius(20)
        }
        .padding(16)
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
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.gray)
            .cornerRadius(4)
    }

    private func pediatricNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 11))
                .foregroundColor(.stanford)
            Text("Pediatric Cardiac Anesthesia: \(text)")
                .font(.system(size: 12))
                .foregroundColor(Color(.darkGray))
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
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(14)
        .background(Color.stanford)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    // MARK: Layout helpers

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
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
    private func divider(after med: ResolvedMedication, in list: [ResolvedMedication]) -> some View {
        if med.id != list.last?.id {
            Divider().padding(.leading, 16)
        }
    }

    // MARK: Actions

    private func choose(_ branch: Conditional, for id: String) {
        guard let idx = medications.firstIndex(where: { $0.id == id }) else { return }
        withAnimation { medications[idx].chosenBranch = branch }
    }

    private var saveButton: some View {
        VStack(spacing: 8) {
            Button {
                caseStore.save(medications)
                saved = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                    Text(saved ? "Case Saved" : "Save Case")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(saved || !isComplete ? Color.gray : Color.stanford)
                .cornerRadius(14)
            }
            .disabled(saved || !isComplete)

            if !isComplete {
                Text("Answer the outstanding questions before saving.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    private var disclaimer: some View {
        VStack(spacing: 6) {
            Text("\(GuidelineMeta.title), revised \(GuidelineMeta.revision). \(GuidelineMeta.source).")
                .font(.system(size: 11, weight: .medium))
            Text(GuidelineMeta.scope)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.stanford)
            Text("For clinical decision support only. Not a substitute for professional judgment. Always verify with the attending anesthesiologist.")
                .font(.system(size: 11))
        }
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(12)
        .background(Color.white)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }
}
