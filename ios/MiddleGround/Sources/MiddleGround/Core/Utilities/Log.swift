import Foundation
import os

/// Shared loggers.
///
/// `print` is invisible in release builds and unsearchable in Console; `Logger` is neither.
enum MGLog {
    private static let subsystem = "app.middleground"

    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let auth = Logger(subsystem: subsystem, category: "auth")
}
