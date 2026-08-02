import XCTest
@testable import MiddleGround

/// Calling a plan off, and what counts as leaving it too late.
///
/// The reliability score has counted late cancellations since it was written, but the thing it
/// counted was unreachable: `canCancel` required `isOpen`, which excludes `accepted`, so a plan
/// became uncancellable the moment somebody agreed to it. The only cancellable plans were ones
/// nobody had said yes to — and abandoning one of those costs no one anything.
final class LateCancellationTests: XCTestCase {
    private let alice = "alice"
    private let bob = "bob"
    private let day: TimeInterval = 24 * 60 * 60

    private func plan(
        status: RequestStatus = .accepted,
        at proposedTime: Date? = nil,
        confirmations: [String: ConfirmationOutcome] = [:]
    ) -> Request {
        Request(
            creatorID: alice,
            recipientIDs: [bob],
            category: .friends,
            title: "Dinner",
            proposedTime: proposedTime,
            status: status,
            confirmations: confirmations
        )
    }

    // MARK: - What can be called off

    /// The case that was impossible, and the only one the score actually cares about.
    func testAnAgreedPlanCanBeCalledOff() {
        XCTAssertTrue(plan(status: .accepted).canCancel(as: alice))
    }

    func testAPlanNobodyAnsweredCanStillBeWithdrawn() {
        XCTAssertTrue(plan(status: .pending).canCancel(as: alice))
        XCTAssertTrue(plan(status: .countered).canCancel(as: alice))
    }

    func testOnlyTheCreatorCanCallItOff() {
        XCTAssertFalse(plan(status: .accepted).canCancel(as: bob))
    }

    func testWhatIsFinishedStaysFinished() {
        for status in [RequestStatus.completed, .cancelled, .declined] {
            XCTAssertFalse(
                plan(status: status).canCancel(as: alice),
                "\(status.rawValue) should not be cancellable"
            )
        }
    }

    /// Once anyone has said whether it happened, the plan is a record. Cancelling it would erase
    /// attendance somebody already reported — which is also how you would erase your own no-show.
    func testAPlanSomeoneHasAnsweredAboutCannotBeErased() {
        let answered = plan(status: .accepted, confirmations: [bob: .didNotHappen])
        XCTAssertFalse(answered.canCancel(as: alice))
    }

    // MARK: - What counts as late

    func testCallingOffTheSameEveningIsLate() {
        let soon = plan(at: Date().addingTimeInterval(2 * 3600))
        XCTAssertTrue(soon.isCancellingLate())
    }

    func testCallingOffNextWeekIsNot() {
        let distant = plan(at: Date().addingTimeInterval(7 * day))
        XCTAssertFalse(distant.isCancellingLate())
    }

    /// The boundary itself, from both sides — a window nobody has tested is a window that drifts.
    func testTheWindowIsExactlyOneDay() {
        let now = Date()
        let justInside = plan(at: now.addingTimeInterval(day - 60))
        let justOutside = plan(at: now.addingTimeInterval(day + 60))

        XCTAssertTrue(justInside.isCancellingLate(at: now))
        XCTAssertFalse(justOutside.isCancellingLate(at: now))
    }

    /// "Split the chores" has no moment to be late for.
    func testAPlanWithNoTimeIsNeverLate() {
        XCTAssertFalse(plan(at: nil).isCancellingLate())
    }

    /// The warning shown before cancelling and the record kept afterwards must agree. They are
    /// computed from different clocks — `now` versus `updatedAt` — so a difference in the window
    /// would mean warning about something the score does not count, or counting something it
    /// never warned about.
    func testTheWarningAndTheRecordUseTheSameWindow() {
        let now = Date()
        var cancelled = plan(status: .accepted, at: now.addingTimeInterval(3 * 3600))
        XCTAssertTrue(cancelled.isCancellingLate(at: now))

        cancelled.status = .cancelled
        cancelled.updatedAt = now
        XCTAssertTrue(cancelled.wasCancelledLate)
    }

    // MARK: - Who is offered the option

    /// Found on a real device: the detail screen showed "Cancel request" to whoever was waiting,
    /// which after a counter is usually the *recipient*. They could open the reason picker,
    /// choose a reason, and only then be told they were not allowed. `canCancel` is the gate the
    /// view should have been asking, and these assert the answer it gives.
    func testTheRecipientIsNotOfferedCancellation() {
        // The state from the screenshot: negotiated, waiting on the other person.
        let negotiating = plan(status: .negotiated, at: Date().addingTimeInterval(5 * day))

        XCTAssertTrue(negotiating.canCancel(as: alice), "the creator may call it off")
        XCTAssertFalse(negotiating.canCancel(as: bob), "the recipient may not, so must not be asked")
    }

    /// The same question for every state the waiting row can appear in — it is shown whenever
    /// someone has replied and is waiting, which is most of a plan's life.
    func testOnlyTheCreatorIsEverOfferedCancellation() {
        for status in [RequestStatus.pending, .negotiated, .countered, .rescheduled, .saved, .accepted] {
            let request = plan(status: status, at: Date().addingTimeInterval(5 * day))
            XCTAssertTrue(request.canCancel(as: alice), "creator, \(status.rawValue)")
            XCTAssertFalse(request.canCancel(as: bob), "recipient, \(status.rawValue)")
        }
    }

    // MARK: - What the score does with it

    func testOnlyLateCancellationsCountAgainstYou() {
        let now = Date()
        let courteous = Request(
            creatorID: alice,
            recipientIDs: [bob],
            category: .friends,
            title: "Early notice",
            proposedTime: now.addingTimeInterval(10 * day),
            status: .cancelled,
            updatedAt: now
        )
        let lastMinute = Request(
            creatorID: alice,
            recipientIDs: [bob],
            category: .friends,
            title: "Tonight",
            proposedTime: now.addingTimeInterval(3600),
            status: .cancelled,
            updatedAt: now
        )

        let score = ReliabilityScore.from(requests: [courteous, lastMinute], userID: alice, now: now)

        XCTAssertEqual(score.lateCancellations, 1, "only the last-minute one should count")
    }

    func testSomebodyElsesCancellationIsNotYours() {
        let now = Date()
        let theirs = Request(
            creatorID: bob,
            recipientIDs: [alice],
            category: .friends,
            title: "Theirs",
            proposedTime: now.addingTimeInterval(3600),
            status: .cancelled,
            updatedAt: now
        )

        let score = ReliabilityScore.from(requests: [theirs], userID: alice, now: now)

        XCTAssertEqual(score.lateCancellations, 0)
    }
}
