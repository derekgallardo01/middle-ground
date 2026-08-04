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

    // MARK: - One plan per destructive action
    //
    // Accepting, declining, negotiating and countering all *settle* the plan they act on, so they
    // cannot be demonstrated on the same fixture — the first one filmed removes the response row
    // the rest need. Confirming attendance is the same: "yes it happened" and "no it didn't" are
    // two answers to one question and need a plan each. These exist so the recorded tour can show
    // every action rather than the first one and four empty screens.

    /// For accepting. Awaiting the preview user's answer.
    static let previewToAccept = Request(
        id: "req_10",
        creatorID: User.preview2.id,
        recipientIDs: [User.preview.id],
        category: .friends,
        title: "Pizza on Thursday?",
        details: "That place by the park.",
        proposedTime: Date().addingTimeInterval(86_400 * 4),
        status: .pending,
        createdAt: Date().addingTimeInterval(-1_700),
        updatedAt: Date().addingTimeInterval(-1_700)
    )

    /// For declining.
    static let previewToDecline = Request(
        id: "req_11",
        creatorID: User.preview2.id,
        recipientIDs: [User.preview.id],
        category: .daily,
        title: "Early gym tomorrow?",
        details: "6am start.",
        proposedTime: Date().addingTimeInterval(86_400),
        status: .pending,
        createdAt: Date().addingTimeInterval(-1_600),
        updatedAt: Date().addingTimeInterval(-1_600)
    )

    /// For negotiating.
    static let previewToNegotiate = Request(
        id: "req_12",
        creatorID: User.preview2.id,
        recipientIDs: [User.preview.id],
        category: .travel,
        title: "Weekend in the mountains?",
        details: "Thinking two nights.",
        proposedTime: Date().addingTimeInterval(86_400 * 9),
        status: .pending,
        createdAt: Date().addingTimeInterval(-1_500),
        updatedAt: Date().addingTimeInterval(-1_500)
    )

    /// For countering with a different time.
    static let previewToCounter = Request(
        id: "req_13",
        creatorID: User.preview2.id,
        recipientIDs: [User.preview.id],
        category: .chill,
        title: "Film night Saturday?",
        details: "Your pick.",
        proposedTime: Date().addingTimeInterval(86_400 * 2),
        status: .pending,
        createdAt: Date().addingTimeInterval(-1_400),
        updatedAt: Date().addingTimeInterval(-1_400)
    )

    /// For answering "Yes, it did". Agreed, and its time has passed.
    static let previewToConfirmHappened = Request(
        id: "req_14",
        creatorID: User.preview2.id,
        recipientIDs: [User.preview.id],
        category: .friends,
        title: "Coffee on Monday",
        proposedTime: Date().addingTimeInterval(-7_200),
        location: "Prospect Park",
        status: .accepted,
        createdAt: Date().addingTimeInterval(-90_000),
        updatedAt: Date().addingTimeInterval(-7_200)
    )

    /// For answering "No, it didn't".
    static let previewToConfirmMissed = Request(
        id: "req_15",
        creatorID: User.preview2.id,
        recipientIDs: [User.preview.id],
        category: .daily,
        title: "Market run",
        proposedTime: Date().addingTimeInterval(-10_800),
        location: "The Anchor",
        status: .accepted,
        createdAt: Date().addingTimeInterval(-95_000),
        updatedAt: Date().addingTimeInterval(-10_800)
    )

    /// A second cancellable plan, so two different cancellation reasons can be shown.
    static let previewToCancel = Request(
        id: "req_16",
        creatorID: User.preview.id,
        recipientIDs: [User.preview2.id],
        category: .dating,
        title: "Drinks on Wednesday?",
        details: "That wine bar.",
        proposedTime: Date().addingTimeInterval(86_400 * 5),
        status: .pending,
        createdAt: Date().addingTimeInterval(-1_300),
        updatedAt: Date().addingTimeInterval(-1_300)
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
