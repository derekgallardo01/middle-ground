import Foundation

// Fixtures: the requests SwiftUI previews, the UI tests and mock mode are built from.
//
// Split out of Request.swift, which crossed the 500-line limit when the fixtures for the
// marketing screenshots were added. They are sample data rather than model behaviour, and
// reading the model is easier without two hundred lines of them underneath it.

extension Request {
    static let preview = Request(
        id: "req_1",
        creatorID: User.preview.id,
        recipientIDs: [User.preview2.id],
        category: .relationship,
        title: "Date night this Friday?",
        details: "Want to try that new Italian place?",
        proposedTime: Date().addingTimeInterval(86400 * 3),
        status: .pending,
        createdAt: Date().addingTimeInterval(-86_400),
        updatedAt: Date().addingTimeInterval(-86_400)
    )

    /// A request the preview user must answer — i.e. one where the response row actually
    /// renders.
    ///
    /// Every other fixture makes `User.preview` the *creator*, so in mock mode the app's
    /// primary control was never shown: not in SwiftUI previews, not in the UI tests, and not
    /// in the App Store screenshots generated from mock mode.
    static let previewAwaitingMe = Request(
        id: "req_0",
        creatorID: User.preview2.id,
        recipientIDs: [User.preview.id],
        category: .daily,
        title: "Split the chores this week?",
        details: "I'll take dishes if you take laundry.",
        status: .pending,
        // Explicit timestamps so the feed order is deterministic. The fixtures all took
        // `Date()` at static-init time, which differ by microseconds, so the sort by
        // `updatedAt` produced an arbitrary order and buried the only respondable request.
        createdAt: Date().addingTimeInterval(-1_800),
        updatedAt: Date().addingTimeInterval(-1_800)
    )

    /// Mid-conversation, with the turn back on the preview user.
    ///
    /// The chain deliberately ends on a counter from the other person: that is the state that
    /// used to be unreachable, because a counter closed the request permanently.
    static let previewNegotiating = Request(
        id: "req_2",
        creatorID: User.preview.id,
        recipientIDs: [User.preview2.id],
        category: .friends,
        title: "Dinner Tonight?",
        details: "Pizza at 7?",
        status: .countered,
        negotiationChain: [
            NegotiationMessage(senderID: User.preview.id, responseType: .negotiate, text: "How about 7?"),
            NegotiationMessage(senderID: User.preview2.id, responseType: .counter, text: "Can we do 8 instead?")
        ],
        createdAt: Date().addingTimeInterval(-7_200),
        updatedAt: Date().addingTimeInterval(-3_600)
    )

    /// A plan with points on it, live and agreed by both sides.
    ///
    /// Fixtures exist for the screens the app is *about*; these three exist for the screens the
    /// marketing site has to photograph. Without them the stake row, the location row and a
    /// group of three are unreachable in mock mode, so the features cannot be shown to anyone
    /// who has not installed the app.
    static let previewStaked = Request(
        id: "req_4",
        creatorID: User.preview.id,
        recipientIDs: [User.preview2.id],
        category: .friends,
        title: "Climbing on Saturday",
        details: "Third time we've tried to book this.",
        proposedTime: Date().addingTimeInterval(86_400 * 2),
        location: "The Castle",
        status: .accepted,
        negotiationChain: [
            NegotiationMessage(senderID: User.preview2.id, responseType: .accept, text: "Booked it.")
        ],
        stake: Stake(proposedBy: User.preview.id, points: 25, acceptedBy: User.preview2.id),
        createdAt: Date().addingTimeInterval(-90_000),
        updatedAt: Date().addingTimeInterval(-40_000)
    )

    /// A plan happening right now, so it sits inside its location-sharing window.
    ///
    /// `proposedTime` is deliberately a few minutes in the past rather than a fixed date: the
    /// window is relative to now, so a hardcoded date would put this fixture outside it within
    /// a day and the row would silently stop rendering.
    static let previewHappeningNow = Request(
        id: "req_5",
        creatorID: User.preview2.id,
        recipientIDs: [User.preview.id],
        category: .dating,
        title: "Dinner at Lucia's",
        details: "Table for two, 7pm.",
        proposedTime: Date().addingTimeInterval(-600),
        location: "Lucia's",
        status: .accepted,
        negotiationChain: [
            NegotiationMessage(senderID: User.preview.id, responseType: .accept, text: "See you there.")
        ],
        createdAt: Date().addingTimeInterval(-260_000),
        updatedAt: Date().addingTimeInterval(-3_000)
    )

    /// Three people on one plan, with one of them still to answer.
    static let previewGroupPlan = Request(
        id: "req_6",
        creatorID: User.preview.id,
        recipientIDs: [User.preview2.id, User.preview3.id],
        category: .friends,
        title: "Sunday roast?",
        details: "The place with the good potatoes.",
        proposedTime: Date().addingTimeInterval(86_400 * 4),
        location: "The Anchor",
        status: .accepted,
        negotiationChain: [
            NegotiationMessage(senderID: User.preview2.id, responseType: .accept, text: "I'm in.")
        ],
        createdAt: Date().addingTimeInterval(-50_000),
        updatedAt: Date().addingTimeInterval(-20_000)
    )

    static let previewAccepted = Request(
        id: "req_3",
        creatorID: User.preview.id,
        recipientIDs: [User.preview2.id],
        category: .travel,
        title: "Weekend Getaway",
        details: "Beach house May 24–26",
        status: .accepted,
        createdAt: Date().addingTimeInterval(-172_800),
        updatedAt: Date().addingTimeInterval(-172_800)
    )
}
