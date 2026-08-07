import XCTest
@testable import MiddleGround

/// When a plan has gone quiet, and — just as importantly — when it has not.
///
/// The failure this guards against is not a wrong number. It is a prompt appearing on a plan that
/// is perfectly healthy, which teaches people to ignore the prompt, which costs the one case it
/// existed for. Most of these tests assert that nothing happens.
final class PlanMomentumTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func days(_ count: Double) -> TimeInterval { count * 86_400 }

    /// A plan agreed `agreedDaysAgo` back, happening `inDays` from now, untouched since agreement.
    private func plan(
        agreedDaysAgo: Double,
        inDays: Double,
        lastTouchedDaysAgo: Double? = nil,
        stillOn: [String: Date] = [:],
        status: RequestStatus = .accepted
    ) -> Request {
        let agreedAt = now.addingTimeInterval(-days(agreedDaysAgo))
        var request = Request(
            creatorID: "user_1",
            recipientIDs: ["user_2"],
            category: .friends,
            title: "Dinner",
            proposedTime: now.addingTimeInterval(days(inDays)),
            status: status,
            negotiationChain: [
                NegotiationMessage(
                    senderID: "user_2",
                    responseType: .accept,
                    text: nil,
                    timestamp: agreedAt
                )
            ],
            stillOn: stillOn,
            createdAt: agreedAt.addingTimeInterval(-days(1)),
            updatedAt: now.addingTimeInterval(-days(lastTouchedDaysAgo ?? agreedDaysAgo))
        )
        request.status = status
        return request
    }

    // MARK: - The boundary with the reminder that already exists

    /// `remindBeforePlan` sends "Still on?" sixteen hours out. Prompting inside that window asks
    /// the same question twice, which is how a useful nudge turns into noise.
    func testAPlanInsideTheReminderWindowIsLeftAlone() {
        let momentum = PlanMomentum.from(
            request: plan(agreedDaysAgo: 20, inDays: 0.5),   // 12 hours
            now: now
        )

        XCTAssertEqual(momentum.state, .notApplicable)
        XCTAssertFalse(momentum.wantsCheckIn)
    }

    func testAPlanJustOutsideTheReminderWindowIsOurs() {
        let momentum = PlanMomentum.from(
            request: plan(agreedDaysAgo: 20, inDays: 0.75),  // 18 hours
            now: now
        )

        XCTAssertTrue(momentum.wantsCheckIn, "nothing else will ask about this one")
    }

    // MARK: - Silence is relative to the runway

    /// Six days of quiet on a plan a month out is a group getting on with their lives.
    func testSixQuietDaysOnALongRunwayIsFine() {
        let momentum = PlanMomentum.from(
            request: plan(agreedDaysAgo: 6, inDays: 24),
            now: now
        )

        XCTAssertEqual(momentum.state, .warm)
        XCTAssertFalse(momentum.wantsCheckIn)
    }

    /// The same six days on a plan next week is a plan dissolving.
    func testTheSameSixDaysOnAShortRunwayIsNot() {
        let momentum = PlanMomentum.from(
            request: plan(agreedDaysAgo: 6, inDays: 2),
            now: now
        )

        XCTAssertTrue(momentum.wantsCheckIn)
        XCTAssertEqual(momentum.state, .atRisk, "two days away and nobody has spoken")
    }

    func testAFortnightOfSilenceCountsHoweverFarOffItIs() {
        let momentum = PlanMomentum.from(
            request: plan(agreedDaysAgo: 20, inDays: 60),
            now: now
        )

        XCTAssertEqual(momentum.state, .fading, "a fortnight of nothing is worth a word")
    }

    // MARK: - Nothing happens to a plan that has just been made

    /// Without a floor, a plan agreed on Monday for Wednesday is "fading" by Tuesday.
    func testAPlanAgreedThisMorningIsNeverFlagged() {
        let momentum = PlanMomentum.from(
            request: plan(agreedDaysAgo: 0.25, inDays: 2),
            now: now
        )

        XCTAssertEqual(momentum.state, .early)
        XCTAssertFalse(momentum.wantsCheckIn)
    }

    // MARK: - Only agreed, dated plans

    func testAPendingPlanHasNoMomentum() {
        let momentum = PlanMomentum.from(
            request: plan(agreedDaysAgo: 30, inDays: 30, status: .pending),
            now: now
        )

        XCTAssertEqual(momentum.state, .notApplicable)
    }

    func testAPlanWithNoTimeHasNoMomentum() {
        var request = plan(agreedDaysAgo: 30, inDays: 30)
        request.proposedTime = nil

        XCTAssertEqual(PlanMomentum.from(request: request, now: now).state, .notApplicable)
    }

    func testAPlanInThePastHasNoMomentum() {
        let momentum = PlanMomentum.from(
            request: plan(agreedDaysAgo: 30, inDays: -1),
            now: now
        )

        XCTAssertEqual(momentum.state, .notApplicable, "that is attendance's question now")
    }

    // MARK: - Saying you are still coming quiets it

    func testAStillOnResetsTheSilence() {
        let saidYesterday = ["user_2": now.addingTimeInterval(-days(1))]
        let momentum = PlanMomentum.from(
            request: plan(agreedDaysAgo: 20, inDays: 4, stillOn: saidYesterday),
            now: now
        )

        XCTAssertFalse(momentum.wantsCheckIn, "somebody confirmed yesterday")
    }

    func testAnOldStillOnDoesNotHoldItOpenForever() {
        let saidAgesAgo = ["user_2": now.addingTimeInterval(-days(19))]
        let momentum = PlanMomentum.from(
            request: plan(agreedDaysAgo: 20, inDays: 4, stillOn: saidAgesAgo),
            now: now
        )

        XCTAssertTrue(momentum.wantsCheckIn)
    }

    // MARK: - It always says why

    func testEveryFlaggedPlanExplainsItself() {
        for (agreed, away) in [(6.0, 2.0), (20.0, 60.0), (10.0, 3.0)] {
            let momentum = PlanMomentum.from(
                request: plan(agreedDaysAgo: agreed, inDays: away),
                now: now
            )
            XCTAssertTrue(momentum.wantsCheckIn)
            XCTAssertFalse(
                momentum.reason.isEmpty,
                "a ring with no sentence tells somebody they are failing and not at what"
            )
        }
    }

    func testTheReasonReadsLikeSomethingAPersonWouldSay() {
        // Agreed 12 days ago for 8 days' time: a 20-day runway, so it tolerates 10 days of quiet
        // and this is past it.
        let momentum = PlanMomentum.from(
            request: plan(agreedDaysAgo: 12, inDays: 8),
            now: now
        )

        XCTAssertEqual(momentum.reason, "Agreed 12 days ago. Nothing since. 8 days to go.")
    }

    /// The boundary itself, written down because it is a judgement rather than a fact: nine quiet
    /// days on a twenty-day runway is still inside what that plan tolerates. Moving the halving
    /// changes this test, which is the point of having it.
    func testJustInsideTheToleranceIsStillWarm() {
        let momentum = PlanMomentum.from(
            request: plan(agreedDaysAgo: 9, inDays: 11),
            now: now
        )

        XCTAssertEqual(momentum.state, .warm)
        XCTAssertFalse(momentum.wantsCheckIn)
    }

    func testJustOutsideItIsNot() {
        let momentum = PlanMomentum.from(
            request: plan(agreedDaysAgo: 11, inDays: 9),
            now: now
        )

        XCTAssertTrue(momentum.wantsCheckIn)
    }

    // MARK: - It has to survive the cache

    /// The repository is remote-then-local: `fetchLocal` is what the app actually reads, so a
    /// field the entity does not persist is invisible everywhere even when the network fetch
    /// worked. That is how a group lost its name (`9ff2d97`) with nothing failing, and `seats` is
    /// still losing that way today.
    func testStillOnSurvivesTheOfflineCache() throws {
        var request = plan(agreedDaysAgo: 4, inDays: 10)
        request.stillOn = ["user_2": now.addingTimeInterval(-days(1))]

        let restored = try XCTUnwrap(RequestEntity(from: request).toModel())

        XCTAssertEqual(restored.stillOn.keys.sorted(), ["user_2"])
        XCTAssertEqual(
            restored.stillOn["user_2"]?.timeIntervalSince1970 ?? 0,
            request.stillOn["user_2"]?.timeIntervalSince1970 ?? -1,
            accuracy: 1,
            "the cache dropped it, and nothing would have failed"
        )
    }

    func testAnEntityWrittenBeforeStillOnExistedStillLoads() throws {
        let entity = RequestEntity(from: plan(agreedDaysAgo: 4, inDays: 10))
        entity.stillOnData = nil   // a store created before this shipped

        let restored = try XCTUnwrap(entity.toModel())

        XCTAssertTrue(restored.stillOn.isEmpty)
    }

    /// `update(from:)` is a separate code path from `init(from:)` and has been the one that
    /// forgot a field before.
    func testUpdatingACachedRequestKeepsStillOn() throws {
        let entity = RequestEntity(from: plan(agreedDaysAgo: 4, inDays: 10))
        var later = plan(agreedDaysAgo: 4, inDays: 10)
        later.stillOn = ["user_1": now]

        entity.update(from: later)

        XCTAssertEqual(try XCTUnwrap(entity.toModel()).stillOn.keys.sorted(), ["user_1"])
    }

    // MARK: - When it was agreed

    /// `updatedAt` is overwritten by every later edit, so it cannot answer this.
    func testAgreementTimeComesFromTheChainNotFromUpdatedAt() throws {
        let request = plan(agreedDaysAgo: 12, inDays: 20, lastTouchedDaysAgo: 1)

        let agreedAt = try XCTUnwrap(request.agreedAt)
        XCTAssertEqual(
            agreedAt.timeIntervalSince1970,
            now.addingTimeInterval(-days(12)).timeIntervalSince1970,
            accuracy: 1
        )
    }

    /// A yes given before the time moved is not a yes to the new time.
    func testAYesGivenBeforeTheTimeMovedIsNotCurrent() {
        var request = plan(agreedDaysAgo: 10, inDays: 10)
        request.stillOn["user_2"] = now.addingTimeInterval(-days(5))
        request.negotiationChain.append(
            NegotiationMessage(
                senderID: "user_1",
                responseType: .reschedule,
                text: nil,
                proposedTime: now.addingTimeInterval(days(20)),
                timestamp: now.addingTimeInterval(-days(2))
            )
        )

        XCTAssertFalse(request.hasCurrentStillOn(from: "user_2"))
    }
}
