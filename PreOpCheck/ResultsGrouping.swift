//
//  ResultsGrouping.swift
//  PreOpCheck
//
//  How the results screen groups drugs and what each row's pill says. Kept
//  out of ResultsView so the rules can be tested without the screen.
//
//  Two groups: Hold / Consult, then Take as directed. A consult drug needs
//  the same attention as a hold, so it sits in the hold group, after the
//  timed holds. Its pill shows "*" in place of a time, and the starred
//  consult instruction leads its dropdown.
//

enum ResultsGrouping {

    /// Timed holds first, then consults. Order within each comes from the
    /// resolver.
    static func holdOrConsult(_ meds: [ResolvedMedication]) -> [ResolvedMedication] {
        meds.filter { $0.action.severity == .hold }
            + meds.filter { $0.action.severity == .consult }
    }

    static func takeAsDirected(_ meds: [ResolvedMedication]) -> [ResolvedMedication] {
        meds.filter { $0.action.severity == .takeAsDirected }
    }

    /// The short verdict on the pill: how long to hold, "*" for a consult,
    /// or TAKE. The full instruction is in the dropdown.
    static func pill(for action: Action) -> String {
        switch action {
        case .takeAsDirected:     return "TAKE"
        case .holdDayOfSurgery:   return "HOLD DOS"
        case .holdHours(let h):   return "\(h)H"
        case .holdDays(let d):    return "\(d)D"
        case .consult, .variable: return "*"
        }
    }

    /// First line of the dropdown. Consults carry the same "*" as their pill
    /// so the two read as a footnote and its mark.
    static func instructionLine(for action: Action) -> String {
        action.severity == .consult ? "* \(action.label)" : action.label
    }
}
