import XCTest
@testable import MiddleGround

/// The wire names of the analytics events.
///
/// These strings are the schema. Firestore stores the raw value, the admin funnel filters on it,
/// the daily digest counts it in `CloudFunctions/index.js`, and `firestore.indexes.json` has an
/// index keyed on it. Renaming a case without changing the stored value in step orphans every
/// event already written — and the reverse, changing a raw value, silently zeroes a funnel step
/// that has years of history behind it.
///
/// Nothing else in the app pins them, so this does.
final class AnalyticsEventTests: XCTestCase {

    /// The exact strings the backend counts. Adding a case is fine; changing one of these is a
    /// migration, not an edit.
    func testTheWireNamesAreWhatTheBackendCounts() {
        let expected: [EventType: String] = [
            .signedUp: "signed_up",
            .signedIn: "signed_in",
            .onboardingCompleted: "onboarding_completed",
            .relationshipCreated: "relationship_created",
            .relationshipLeft: "relationship_left",
            .inviteCreated: "invite_created",
            .inviteShared: "invite_shared",
            .inviteRedeemed: "invite_redeemed",
            .contentReported: "content_reported",
            .requestCreated: "request_created",
            .requestResponded: "request_responded",
            .requestCancelled: "request_cancelled",
            .requestConfirmed: "request_confirmed",
            .requestStillOn: "request_still_on",
            .appOpened: "app_opened"
        ]
        for (type, wire) in expected {
            XCTAssertEqual(type.rawValue, wire, "\(type) changed its stored value")
        }
    }

    /// A new case added without a wire name here would be counted by nothing.
    func testEveryEventTypeIsPinned() {
        let pinned: Set<String> = [
            "signed_up", "signed_in", "onboarding_completed", "relationship_created",
            "relationship_left", "invite_created", "invite_shared", "invite_redeemed",
            "content_reported", "request_created", "request_responded", "request_cancelled",
            "request_confirmed", "request_still_on", "app_opened"
        ]
        let actual = Set(EventType.allCases.map(\.rawValue))
        XCTAssertEqual(
            actual,
            pinned,
            "an event type was added or removed without updating this test, the admin funnel, or "
                + "the daily digest's fixed list of counts"
        )
    }

    /// Signing up and signing back in are different questions, and were the same silence.
    ///
    /// `signedUp` fires once per account ever. Before `signedIn` existed a returning user — a
    /// reinstall, a second device, a sign-in after signing out — produced no event at all, and
    /// `appOpened` could not stand in: it is debounced to one every thirty minutes and fires for
    /// an install the person already had.
    func testSigningUpAndSigningInAreDistinct() {
        XCTAssertNotEqual(EventType.signedUp.rawValue, EventType.signedIn.rawValue)
        XCTAssertNotEqual(EventType.signedIn.rawValue, EventType.appOpened.rawValue)
        XCTAssertEqual(EventType.signedIn.displayName, "Signed in")
    }

    /// Every type needs a label and an icon, because the admin activity list renders both for
    /// whatever it finds — a case missing one would render blank rather than fail.
    func testEveryTypeCanBeShown() {
        for type in EventType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "\(type) has no display name")
            XCTAssertFalse(type.iconName.isEmpty, "\(type) has no icon")
        }
    }

    /// An event round-trips through the stored representation unchanged.
    func testAnEventSurvivesEncoding() throws {
        let event = AnalyticsEvent(userID: "user_1", type: .signedIn)
        let data = try JSONEncoder().encode(event)
        let restored = try JSONDecoder().decode(AnalyticsEvent.self, from: data)

        XCTAssertEqual(restored.type, .signedIn)
        XCTAssertEqual(restored.userID, "user_1")
    }
}
