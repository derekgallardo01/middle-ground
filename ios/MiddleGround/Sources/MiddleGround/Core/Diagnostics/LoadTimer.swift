import Foundation
import OSLog

/// Times how long a screen takes to get its data.
///
/// Instruments can tell you the app spent time in Firestore; it cannot tell you *which await* on
/// which screen. This can, because it wraps the loads by name — and naming them is the whole
/// point, since the expensive thing here has always been doing the same load twice rather than
/// any single load being slow.
///
/// Emits signposts, so an `xctrace` recording shows these as intervals alongside CPU samples, and
/// also logs the duration in DEBUG so a number is readable without opening Instruments.
///
/// Compiled out of release builds entirely: `measure` is inlined to a bare call to its own body
/// when `DEBUG` is not set, so shipping code pays nothing.
enum LoadTimer {
    #if DEBUG
    private static let signposter = OSSignposter(
        subsystem: "app.middleground", category: "screen-load"
    )
    #endif

    /// Records an interval that was timed by the caller.
    ///
    /// For work that cannot be wrapped in a closure — a stream whose *first* delivery is the
    /// load, while the stream itself stays open afterwards.
    static func record(_ name: StaticString, since started: ContinuousClock.Instant) {
        #if DEBUG
        let elapsed = ContinuousClock.now - started
        MGLog.performance.info(
            "\(String(describing: name), privacy: .public) took \(elapsed.milliseconds, privacy: .public) ms"
        )
        #endif
    }

    /// Runs `work`, recording how long it took under `name`.
    ///
    /// Rethrows rather than swallowing: a timer that changes error behaviour would be a timer
    /// that changes what it measures.
    @discardableResult
    static func measure<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        #if DEBUG
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        let started = ContinuousClock.now
        defer {
            let elapsed = ContinuousClock.now - started
            signposter.endInterval(name, state)
            MGLog.performance.info(
                "\(String(describing: name), privacy: .public) took \(elapsed.milliseconds, privacy: .public) ms"
            )
        }
        return try await work()
        #else
        return try await work()
        #endif
    }
}

#if DEBUG
private extension Duration {
    /// Whole milliseconds. Sub-millisecond precision is noise next to a network round trip, and
    /// a round number is easier to compare across runs.
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds * 1_000 + attoseconds / 1_000_000_000_000_000)
    }
}
#endif
