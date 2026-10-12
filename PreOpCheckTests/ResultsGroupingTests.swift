//
//  ResultsGroupingTests.swift
//  PreOpCheckTests
//
//  The results screen has two groups: Hold / Consult and Take as directed.
//  Consult drugs sit in the hold group after the timed holds, and their pill
//  shows "*" instead of a time, with the consult instruction starred at the
//  top of the dropdown.
//

import Testing
@testable import PreOpCheck

struct ResultsGroupingTests {

    private func resolve(_ lines: [String]) -> [ResolvedMedication] {
        MedicationResolver.resolve(lines: lines).medications
    }

    private func pill(_ line: String) throws -> String {
        let med = try #require(resolve([line]).first, "\(line) did not resolve")
        return ResultsGrouping.pill(for: med.action)
    }

    @Test func consultDrugsShowAnAsteriskNotATime() throws {
        // Plain consults, including apixaban whose note mentions 48 hours.
        #expect(try pill("insulin glargine") == "*")
        #expect(try pill("warfarin 5 mg") == "*")
        #expect(try pill("apixaban 5 mg") == "*")
        // A case-by-case drug is a consult too.
        #expect(try pill("furosemide 20 mg") == "*")
    }

    @Test func timedHoldsKeepTheirTime() throws {
        #expect(try pill("metformin 500 mg") == "24H")
        #expect(try pill("lisinopril 10 mg") == "HOLD DOS")
        // Clopidogrel's note mentions a consult, but the guideline action is a hold.
        #expect(try pill("clopidogrel 75 mg") == "5D")
        #expect(try pill("hydroxyzine 25 mg") == "TAKE")
    }

    @Test func consultsJoinTheHoldGroupAfterTheHolds() {
        let meds = resolve(["warfarin 5 mg", "hydroxyzine 25 mg", "metformin 500 mg",
                            "insulin glargine", "clopidogrel 75 mg"])

        let holdGroup = ResultsGrouping.holdOrConsult(meds).map(\.match.drug.generic)
        #expect(Set(holdGroup.prefix(2)) == ["metformin", "clopidogrel"])
        #expect(Set(holdGroup.suffix(2)) == ["warfarin", "insulin glargine"])
        #expect(holdGroup.count == 4)

        #expect(ResultsGrouping.takeAsDirected(meds).map(\.match.drug.generic) == ["hydroxyzine"])
    }

    @Test func onlyConsultsGetAStarredNote() throws {
        let insulin = try #require(resolve(["insulin glargine"]).first)
        #expect(ResultsGrouping.instructionLine(for: insulin.action) == "* Consult Endocrinology")

        let metformin = try #require(resolve(["metformin 500 mg"]).first)
        #expect(ResultsGrouping.instructionLine(for: metformin.action) == "Hold 24 hours prior to surgery")
    }
}
