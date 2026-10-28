// MomentReasonsTests.swift
// Tests for the "Why this moment" lines on the Fine Tune screen.

import Testing
@testable import VeloFilms

@MainActor
struct MomentReasonsTests {

    private func reasons(classes: String = "", gradient: Double? = 0, speed: Double? = 25,
                         segment: String? = nil, pr: Bool = false) -> [MomentReason] {
        let row = Fixtures.enrich(t: 0, speed: speed, gradient: gradient, classes: classes)
        let moment = PartnerMatcher.Moment(momentId: 0, rows: [row])
        return MomentReasons.reasons(for: moment, row: row, segmentName: segment, isPR: pr, ctx: Fixtures.context())
    }

    @Test func prOnNamedSegmentComesFirst() {
        let r = reasons(classes: "person,bicycle", segment: "Golf Links Outbound", pr: true)
        #expect(r.first == MomentReason(kind: .stravaPR, text: "Strava PR · Golf Links Outbound"))
    }

    @Test func segmentWithoutPR() {
        #expect(reasons(segment: "Richards Rd").first?.text == "Segment · Richards Rd")
    }

    @Test func prWithoutSegmentName() {
        #expect(reasons(pr: true).first?.text == "Strava PR")
    }

    @Test func ridersCountedOncePerCyclist() {
        let r = reasons(classes: "person,person,person,bicycle,bicycle,bicycle")
        #expect(r.contains(MomentReason(kind: .riders, text: "3 riders in view")))
    }

    @Test func singleRiderReadsNaturally() {
        #expect(reasons(classes: "bicycle").contains { $0.text == "1 rider in view" })
    }

    @Test func noRidersNoLine() {
        #expect(!reasons(classes: "car,car").contains { $0.kind == .riders })
    }

    @Test func climbAtThreshold() {
        #expect(reasons(gradient: 4).contains { $0.text == "Climbing 4.0%" })
    }

    @Test func descentShownAsPositivePercent() {
        #expect(reasons(gradient: -8.6).contains { $0.text == "Descending 8.6%" })
    }

    @Test func gentleSlopeHasNoGradientLine() {
        let kinds = reasons(gradient: 2).map(\.kind)
        #expect(!kinds.contains(.climb) && !kinds.contains(.descent))
    }

    @Test func speedRounded() {
        #expect(reasons(speed: 36.6).last?.text == "37 km/h")
    }

    @Test func nothingKnownNothingShown() {
        #expect(reasons(gradient: nil, speed: nil).isEmpty)
    }
}
