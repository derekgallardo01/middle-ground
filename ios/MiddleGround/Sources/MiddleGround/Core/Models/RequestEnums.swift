import Foundation

// The vocabulary a request is described in: what kind of plan it is, how someone can answer,
// what state it ends up in, and why it was called off.
//
// Split out of Request.swift, which had grown past the 500-line limit. These are the types most
// often read while trying to understand the model, and they read better without a 200-line
// struct underneath them.

enum RequestCategory: String, Codable, CaseIterable, Identifiable {
    case relationship
    case friends
    case family
    case daily
    case travel
    case spontaneous
    case dating
    case chill

    /// A category this build does not recognise, kept so the request still appears.
    ///
    /// Decoding used to fail closed: `RequestDTO.toModel()` returned nil on an unknown raw value
    /// and the repository `compactMap`ped it away, so a request created in a category added after
    /// your build shipped was not an error — it was simply *absent*. One person sends a plan, the
    /// other never sees it, and nothing anywhere reports a problem. Falling back here means the
    /// worst case is a request with a generic icon rather than a request that does not exist.
    ///
    /// Deliberately excluded from `allCases` so it can never be picked when composing.
    case unknown

    static var allCases: [RequestCategory] {
        [.relationship, .friends, .family, .daily, .travel, .spontaneous, .dating, .chill]
    }

    var id: String { rawValue }

    /// Never fails. Unrecognised values become `.unknown`.
    init(storedValue: String) {
        self = RequestCategory(rawValue: storedValue) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .relationship: return "Relationship"
        case .friends: return "Friends"
        case .family: return "Family"
        case .daily: return "Daily Life"
        case .travel: return "Travel"
        case .spontaneous: return "Spontaneous"
        case .dating: return "Dating"
        case .chill: return "Chill"
        case .unknown: return "Other"
        }
    }

    var iconName: String {
        switch self {
        case .relationship: return "heart.fill"
        case .friends: return "person.2.fill"
        case .family: return "house.fill"
        case .daily: return "checklist"
        case .travel: return "airplane"
        case .spontaneous: return "bolt.fill"
        case .dating: return "heart.circle.fill"
        case .chill: return "sofa.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Whether an accepted plan actually took place, as reported by one participant.
///
/// This is the signal the app never collected. A request's life ended at `accepted`, and
/// `RequestStatus.completed` was a state nothing ever assigned — so there was no record of
/// whether anyone turned up, and nothing that depends on attendance could be computed from it.
enum ConfirmationOutcome: String, Codable, Hashable, Sendable {
    case happened
    case didNotHappen
}

enum ResponseType: String, Codable, CaseIterable, Identifiable {
    case accept
    case decline
    case negotiate
    case reschedule
    case counter
    case save

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .accept: return "Accept"
        case .decline: return "Decline"
        case .negotiate: return "Suggest"
        case .reschedule: return "Reschedule"
        case .counter: return "Counter"
        case .save: return "Save"
        }
    }

    var emoji: String {
        switch self {
        case .accept: return "✅"
        case .decline: return "❌"
        case .negotiate: return "🤝"
        case .reschedule: return "⏰"
        case .counter: return "📝"
        case .save: return "❤️"
        }
    }

    /// Past-tense phrasing for the activity feed.
    var activityDescription: String {
        switch self {
        case .accept: return "Accepted a request"
        case .decline: return "Declined a request"
        case .negotiate: return "Found a middle ground"
        case .reschedule: return "Rescheduled a plan"
        case .counter: return "Sent a counter-offer"
        case .save: return "Saved a request for later"
        }
    }
}

enum RequestStatus: String, Codable, Identifiable {
    case pending
    case accepted
    case declined
    case negotiated
    case rescheduled
    case countered
    case saved
    case completed

    /// Withdrawn by whoever sent it.
    ///
    /// Cancelling used to delete the document outright, which erased the fact that a plan had
    /// ever been made — and with it any hope of "cancelled three times in a row" meaning
    /// anything. You cannot build a reliability signal on records that disappear when they
    /// become inconvenient. Same shape of problem as an unrestricted delete on a settled
    /// request: the evidence goes with the row.
    case cancelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .negotiated: return "Negotiating"
        case .rescheduled: return "Rescheduled"
        case .countered: return "Countered"
        case .saved: return "Saved"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }
}

/// Why a plan was called off.
///
/// A recorded reason is what separates "life happened" from a pattern, and it is what an appeal
/// would argue over later. Free text is deliberately not an option here: a fixed list is
/// comparable across cancellations, which a sentence never is.
enum CancellationReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case somethingCameUp
    case unwell
    case plansChanged
    case runningLate
    case noLongerNeeded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .somethingCameUp: return "Something came up"
        case .unwell: return "Not feeling well"
        case .plansChanged: return "Our plans changed"
        case .runningLate: return "Running too late"
        case .noLongerNeeded: return "No longer needed"
        }
    }
}
