import Foundation

/// Where somebody is, once, because they chose to say so.
///
/// A point rather than a feed. Nothing here updates on its own: each share is a deliberate tap
/// that writes one coordinate, and the next tap replaces it. Continuous tracking would need
/// `Always` authorisation and a background mode, which is a far heavier privacy posture and a
/// much harder App Review conversation for a feature whose real job is "I'm outside" and "I'm
/// five minutes away".
struct SharedLocation: Codable, Sendable, Equatable, Identifiable {
    let userID: String
    let latitude: Double
    let longitude: Double
    let sharedAt: Date
    /// When this stops being visible and is deleted. Firestore TTL removes the document; the app
    /// hides it the moment it lapses, because TTL deletion is only promised within 24 hours and
    /// a stale pin is worse than none.
    let expiresAt: Date

    var id: String { userID }

    var hasExpired: Bool { expiresAt < Date() }
}

extension Request {
    /// How long before a plan's time location sharing opens.
    ///
    /// Sharing opens *before* the plan starts, which is the whole point: "I'm five minutes away"
    /// is a thing you say on the way, not once you have arrived.
    static let locationWindowBefore: TimeInterval = 60 * 60
    /// And how long after. Long enough to cover the plan itself, short enough that a coordinate
    /// from this evening is not still readable tomorrow morning.
    static let locationWindowAfter: TimeInterval = 4 * 60 * 60

    /// Whether this plan is close enough in time for location sharing to be possible at all.
    ///
    /// The scope is the point of the feature. Location is not something the app knows about you;
    /// it is something you can hand over for a few hours around one agreed plan, and only when
    /// that plan is actually happening. An undated request has no window and never qualifies.
    func isWithinLocationWindow(at now: Date = Date()) -> Bool {
        guard status == .accepted, let time = proposedTime else { return false }
        return now >= time.addingTimeInterval(-Self.locationWindowBefore)
            && now <= time.addingTimeInterval(Self.locationWindowAfter)
    }

    func canShareLocation(as userID: String, at now: Date = Date()) -> Bool {
        isParticipant(userID) && isWithinLocationWindow(at: now)
    }

    /// When a point shared right now should disappear.
    var locationExpiry: Date? {
        proposedTime?.addingTimeInterval(Self.locationWindowAfter)
    }
}
