import XCTest
@testable import MiddleGround

/// Tapping a notification, which crashed the app every single time.
///
/// `NotificationCenter.post` delivers synchronously on the calling thread. The tap handler is an
/// `async` delegate method on a class with no actor isolation, so it ran on a cooperative-pool
/// thread — and its observer in `HomeView` mutates `AppState`, which is `@MainActor`. A closure
/// inside a view body is *assumed* main-actor at compile time, so nothing was diagnosed; Swift
/// checks the assumption at runtime and traps when it does not hold.
///
/// This was invisible in mock mode and in every UI test, because neither delivers a real push:
/// the handler is only ever reached by `UNUserNotificationCenterDelegate`. It took a physical
/// device, a real token, and six pushes to find, which is exactly why it survived to here.
final class NotificationTapTests: XCTestCase {

    /// The observer must run on the main thread — that is the whole fix, and the property it
    /// eventually writes (`AppState.selectedTab`) traps if it does not.
    func testAPlanNotificationIsDeliveredOnTheMainThread() async {
        let observed = expectation(description: "observer ran")
        var wasMainThread = false
        var deliveredID: String?

        let token = NotificationCenter.default.addObserver(
            forName: .didReceiveRequestNotification,
            object: nil,
            queue: nil // Deliberately nil: post on the caller's thread, exactly as production does.
        ) { note in
            wasMainThread = Thread.isMainThread
            deliveredID = note.userInfo?["request_id"] as? String
            observed.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        // From a detached task, which is what the delegate callback amounts to. `await` is
        // required by @MainActor and is the compile-time half of the guarantee.
        await Task.detached {
            await NotificationService.handleNotification(userInfo: ["request_id": "req_6"])
        }.value

        await fulfillment(of: [observed], timeout: 2)
        XCTAssertTrue(wasMainThread, "the observer mutates @MainActor state and will trap off-main")
        XCTAssertEqual(deliveredID, "req_6")
    }

    /// The nudge names a group rather than a plan and takes the other branch, so it needs its own
    /// check — it was already the one push whose deep link had been broken once before.
    func testANudgeIsAlsoDeliveredOnTheMainThread() async {
        let observed = expectation(description: "observer ran")
        var wasMainThread = false

        let token = NotificationCenter.default.addObserver(
            forName: .didReceiveNudgeNotification,
            object: nil,
            queue: nil
        ) { _ in
            wasMainThread = Thread.isMainThread
            observed.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await Task.detached {
            await NotificationService.handleNotification(userInfo: ["relationship_id": "rel_1"])
        }.value

        await fulfillment(of: [observed], timeout: 2)
        XCTAssertTrue(wasMainThread)
    }

    /// A payload naming neither posts nothing at all, rather than sending the app somewhere
    /// arbitrary. There is no `expectation` to fulfil here — the assertion is the silence.
    @MainActor
    func testAPayloadWithNoTargetNavigatesNowhere() {
        var posts = 0
        let names: [Notification.Name] = [.didReceiveRequestNotification, .didReceiveNudgeNotification]
        let tokens = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                posts += 1
            }
        }
        defer { tokens.forEach(NotificationCenter.default.removeObserver) }

        NotificationService.handleNotification(userInfo: ["something_else": "value"])

        XCTAssertEqual(posts, 0)
    }
}
