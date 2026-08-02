import XCTest
@testable import MiddleGround

/// The follow-through record cannot be rebuilt after the fact, so the derivation that produces it
/// is worth pinning: a row written with the wrong group size or the wrong side of the late
/// window is a number nobody can correct later.
final class PlanOutcomeTests: XCTestCase {
    private let creator = "user_1"
    private let recipient = "user_2"

    private func makeRequest(
        recipients: [String]? = nil,
        proposedTime: Date? = nil,
        category: RequestCategory = .friends
    ) -> Request {
        Request(
            creatorID: creator,
            recipientIDs: recipients ?? [recipient],
            category: category,
            title: "Dinner?",
            proposedTime: proposedTime,
            status: .accepted
        )
    }

    func testGroupSizeCountsEveryone() {
        let pair = PlanOutcome.from(makeRequest(), outcome: .agreed)
        XCTAssertEqual(pair.groupSize, 2)

        let trio = PlanOutcome.from(
            makeRequest(recipients: [recipient, "user_3"]),
            outcome: .agreed
        )
        XCTAssertEqual(trio.groupSize, 3, "the creator counts toward the party size")
    }

    func testHoursBeforePlanIsPositiveWhenTheTimeIsStillAhead() {
        let now = Date()
        let outcome = PlanOutcome.from(
            makeRequest(proposedTime: now.addingTimeInterval(6 * 3600)),
            outcome: .cancelledEarly,
            now: now
        )
        XCTAssertEqual(outcome.hoursBeforePlan, 6)
        XCTAssertTrue(outcome.hadProposedTime)
    }

    /// Attendance is confirmed after the fact, so a negative value is the normal case there.
    func testHoursBeforePlanIsNegativeAfterTheEvent() {
        let now = Date()
        let outcome = PlanOutcome.from(
            makeRequest(proposedTime: now.addingTimeInterval(-3 * 3600)),
            outcome: .attended,
            now: now
        )
        XCTAssertEqual(outcome.hoursBeforePlan, -3)
    }

    func testATimelessPlanRecordsNoDistance() {
        let outcome = PlanOutcome.from(makeRequest(), outcome: .cancelledEarly)
        XCTAssertNil(outcome.hoursBeforePlan)
        XCTAssertFalse(outcome.hadProposedTime)
    }

    /// The distinction the whole record exists to make.
    func testTheLateWindowSeparatesTheTwoCancellations() {
        let now = Date()
        let window = ReliabilityScore.lateCancellationWindow

        let early = makeRequest(proposedTime: now.addingTimeInterval(window + 3600))
        XCTAssertFalse(early.isCancellingLate(at: now))

        let late = makeRequest(proposedTime: now.addingTimeInterval(window - 3600))
        XCTAssertTrue(late.isCancellingLate(at: now))
    }

    /// Anything identifying has to be absent from the model itself, not merely omitted by the
    /// caller — the encoded row is what reaches Firestore.
    func testTheEncodedRowCarriesNothingIdentifying() throws {
        // A timeless plan omits `hoursBeforePlan` entirely, so the assertion is containment
        // rather than equality — which is also exactly what `hasOnly` permits in firestore.rules.
        let allowed: Set<String> = [
            "outcome", "groupSize", "category", "hadProposedTime", "hoursBeforePlan", "at"
        ]
        let forbidden = ["userID", "requestID", "creatorID", "title", "details", "location"]

        for request in [makeRequest(), makeRequest(proposedTime: Date())] {
            let encoded = try JSONEncoder().encode(
                PlanOutcome.from(request, outcome: .attended)
            )
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            )

            XCTAssertTrue(
                Set(json.keys).isSubset(of: allowed),
                "a new field here must be one that cannot single anybody out: \(Set(json.keys).subtracting(allowed))"
            )
            for key in forbidden {
                XCTAssertNil(json[key], "\(key) must never reach plan_outcomes")
            }
        }
    }

    func testEveryOutcomeTypeHasAStableWireName() {
        XCTAssertEqual(
            Set(PlanOutcomeType.allCases.map(\.rawValue)),
            ["agreed", "attended", "cancelled_early", "cancelled_late", "no_showed", "disputed"],
            "these strings are matched literally in firestore.rules"
        )
    }
}
