import FirebaseCrashlytics
import Foundation
import os

/// Shared loggers.
///
/// `print` is invisible in release builds and unsearchable in Console; `Logger` is neither.
///
/// Note what `Logger` alone does *not* give you: its output goes to the device's unified log,
/// which in production is only readable with the device attached to a Mac. That is why the
/// Crashlytics bridge below exists — without it there is no way to learn that anything failed
/// for a real user.
enum MGLog {
    private static let subsystem = "app.middleground"

    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let auth = Logger(subsystem: subsystem, category: "auth")

    /// Attributes subsequent crash reports to an account, and clears the attribution on
    /// sign-out. Only the Firebase UID — no name, no email.
    static func setCrashReportingUser(_ userID: String?) {
        guard AppConfiguration.isBackendEnabled else { return }
        Crashlytics.crashlytics().setUserID(userID ?? "")
    }

    /// Reports a caught error as a non-fatal.
    ///
    /// For failures the app recovers from but which should not be happening — a decode that
    /// fails, a write that is refused. These never reach a crash report on their own, so
    /// without this they are invisible outside a debugger.
    static func recordNonFatal(_ error: Error, context: String) {
        guard AppConfiguration.isBackendEnabled else { return }
        Crashlytics.crashlytics().log("\(context): \(error.localizedDescription)")
        Crashlytics.crashlytics().record(error: error)
    }
}
