import XCTest
@testable import MiddleGround

/// Typing indicators and read receipts.
///
/// The failure mode both share is a lie that persists: an indicator that never clears because a
/// phone was force-quit, or a receipt that claims someone read something they never opened. Both
/// are tested here from that angle rather than from the happy path.
final class PresenceTests: XCTestCase {
    // MARK: - Typing

    /// The reason the flag expires on its own rather than being cleared by its owner.
    func testATypingFlagGoesStaleWithoutAnyoneClearingIt() {
        let started = Date().addingTimeInterval(-TypingPresence.staleAfter - 1)
        let presence = TypingPresence(userID: "alice", startedAt: started)

        XCTAssertTrue(
            presence.hasExpired(),
            "a phone that lost signal mid-sentence never clears its own flag"
        )
    }

    func testAFreshFlagIsLive() {
        XCTAssertFalse(TypingPresence(userID: "alice").hasExpired())
    }

    /// The heartbeat has to comfortably beat the expiry, or an ordinary pause between words
    /// flickers the indicator off and on.
    func testTheHeartbeatIsWellInsideTheExpiry() {
        XCTAssertLessThan(TypingPresence.heartbeat, TypingPresence.staleAfter)
        XCTAssertLessThanOrEqual(
            TypingPresence.heartbeat * 2,
            TypingPresence.staleAfter,
            "two missed beats should still be inside the window"
        )
    }

    func testExpiryIsDerivedFromTheStartRatherThanChosen() {
        let started = Date()
        let presence = TypingPresence(userID: "alice", startedAt: started)
        XCTAssertEqual(
            presence.expiresAt.timeIntervalSince(started),
            TypingPresence.staleAfter,
            accuracy: 0.001
        )
    }

    func testYouAreNeverShownYourOwnTyping() async {
        let repository = MockTypingPresenceRepository()
        await repository.startTyping(userID: "alice", forRequest: "r1")
        await repository.startTyping(userID: "bob", forRequest: "r1")

        var seen: [TypingPresence] = []
        for await batch in repository.observeTyping(forRequest: "r1", excluding: "alice") {
            seen = batch
            break
        }
        XCTAssertEqual(seen.map(\.userID), ["bob"])
    }

    func testStoppingClearsTheFlagAtOnce() async {
        let repository = MockTypingPresenceRepository()
        await repository.startTyping(userID: "alice", forRequest: "r1")
        var count = await repository.typingCount(forRequest: "r1")
        XCTAssertEqual(count, 1)

        await repository.stopTyping(userID: "alice", forRequest: "r1")
        count = await repository.typingCount(forRequest: "r1")
        XCTAssertEqual(count, 0)
    }

    // MARK: - Read receipts

    func testAReceiptCoversEverythingUpToWhenItWasWritten() {
        let now = Date()
        let receipt = PlanReadReceipt(userID: "alice", readAt: now)

        XCTAssertTrue(receipt.hasSeen(now.addingTimeInterval(-60)), "written before they looked")
        XCTAssertFalse(
            receipt.hasSeen(now.addingTimeInterval(60)),
            "a message sent after they looked has not been seen"
        )
    }

    func testYouAreNeverShownYourOwnReceipt() async {
        let repository = MockPlanReadReceiptRepository()
        await repository.markRead(userID: "alice", forRequest: "r1")
        await repository.markRead(userID: "bob", forRequest: "r1")

        var seen: [PlanReadReceipt] = []
        for await batch in repository.observeReceipts(forRequest: "r1", excluding: "alice") {
            seen = batch
            break
        }
        XCTAssertEqual(seen.map(\.userID), ["bob"])
    }

    /// One document per person per plan, not one per message — re-reading must not accumulate.
    func testMarkingReadTwiceKeepsOneReceipt() async {
        let repository = MockPlanReadReceiptRepository()
        await repository.markRead(userID: "alice", forRequest: "r1")
        await repository.markRead(userID: "alice", forRequest: "r1")

        let count = await repository.receiptCount(forRequest: "r1")
        XCTAssertEqual(count, 1)
    }
}
