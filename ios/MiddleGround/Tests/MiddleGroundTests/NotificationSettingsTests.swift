import XCTest
@testable import MiddleGround

/// The whole model is one question — does this notification send? — and the answer has to fail
/// in the direction of sending. Every test here is about absence: no document, no key, a key the
/// running version has never heard of.
final class NotificationSettingsTests: XCTestCase {
    func testEverythingIsOnByDefault() {
        let settings = NotificationSettings()
        for kind in NotificationKind.allCases {
            XCTAssertTrue(settings.isEnabled(kind), "\(kind.rawValue) should default to on")
        }
    }

    func testSwitchingOneOffLeavesTheRestAlone() {
        var settings = NotificationSettings()
        settings.set(.newRequest, enabled: false)

        XCTAssertFalse(settings.isEnabled(.newRequest))
        XCTAssertTrue(settings.isEnabled(.response))
        XCTAssertTrue(settings.isEnabled(.confirmPlan))
    }

    func testSwitchingBackOnClearsIt() {
        var settings = NotificationSettings()
        settings.set(.weeklyNudge, enabled: false)
        settings.set(.weeklyNudge, enabled: true)

        XCTAssertTrue(settings.isEnabled(.weeklyNudge))
        // Written as `true` rather than omitted: a merge write cannot delete a field, so leaving
        // it out would silently keep the stored `false` and the nudge would stay muted.
        XCTAssertEqual(settings.fields[NotificationKind.weeklyNudge.rawValue], true)
    }

    func testEveryKindIsWritten() {
        XCTAssertEqual(NotificationSettings().fields.count, NotificationKind.allCases.count)
    }

    func testAKeyWeDoNotRecogniseIsIgnored() {
        // A newer client mutes something this version has never heard of. The unknown key must
        // not affect anything here, and — because `fields` writes every known kind and merges —
        // must survive the round trip rather than being silently un-muted.
        let settings = NotificationSettings(fields: ["newRequest": false, "somethingNewer": false])

        XCTAssertFalse(settings.isEnabled(.newRequest))
        XCTAssertTrue(settings.isEnabled(.response))
        XCTAssertNil(settings.fields["somethingNewer"])
    }

    func testMissingKeysReadAsOn() {
        let settings = NotificationSettings(fields: ["newRequest": false])

        XCTAssertFalse(settings.isEnabled(.newRequest))
        for kind in NotificationKind.allCases where kind != .newRequest {
            XCTAssertTrue(settings.isEnabled(kind), "\(kind.rawValue) was absent and must read as on")
        }
    }

    /// The raw values are the Firestore field names and are matched by string in
    /// `CloudFunctions/push.js`. Renaming a case un-mutes everyone who had muted it, because the
    /// backend would look for a field nobody writes and a missing field means send.
    func testRawValuesMatchTheBackend() {
        XCTAssertEqual(
            Set(NotificationKind.allCases.map(\.rawValue)),
            [
                "newRequest", "response", "confirmPlan", "planCancelled",
                "weeklyNudge", "planReminder", "message"
            ]
        )
    }
}
