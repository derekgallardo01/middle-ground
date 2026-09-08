import Foundation

// Fixtures: the requests SwiftUI previews, the UI tests and mock mode are built from.
//
// Split out of Request.swift, which crossed the 500-line limit when the fixtures for the
// marketing screenshots were added. They are sample data rather than model behaviour, and
// reading the model is easier without two hundred lines of them underneath it.

/// Fixture times that are an hour of the day rather than an offset from whenever the app was
/// launched.
///
/// `Date().addingTimeInterval(86_400 * 26 + 3_600 * 11)` is eleven hours after *now*, which is a
/// different clock time every run — so the Barcelona trip's dinner rendered at 10:38 AM in one
/// screenshot and 4:38 AM in another. The tests passed either way, because a time is a time. Only
/// looking at the picture caught it.
enum PreviewClock {

    /// Barcelona, so the fixture trip's hours read correctly in the zone it is actually in.
    static let tripZone = TimeZone(identifier: "Europe/Madrid") ?? .current

    /// `hour` o'clock, `daysFromNow` days out, on the trip's own clock.
    static func trip(daysFromNow: Int, hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = tripZone
        let day = calendar.startOfDay(for: Date().addingTimeInterval(Double(daysFromNow) * 86_400))
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// The next `weekday`, at `hour` o'clock. 1 is Sunday, matching `Calendar`.
    ///
    /// Nine fixtures name a day in their own title — "Drinks on Wednesday?", "Film night
    /// Saturday?", "Sunday roast?" — and every one of them was dated by a fixed offset from
    /// launch, so the day in the title and the day on the card agreed only by luck. Nothing
    /// caught it while cards showed a bare "August 8, 2026": the contradiction became visible
    /// the moment they started printing the weekday, and the first place it showed up was an
    /// App Store screenshot reading "Drinks on Wednesday?" over "Sun, Sep 13".
    ///
    /// Always in the future and never today, so a plan that has not happened yet cannot be
    /// dated this morning.
    static func next(weekday: Int, hour: Int, minute: Int = 0) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: Date().addingTimeInterval(86_400))
        let day = calendar.nextDate(
            after: tomorrow,
            matching: DateComponents(weekday: weekday),
            matchingPolicy: .nextTime,
            direction: .forward
        ) ?? tomorrow
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static var sunday: Date { next(weekday: 1, hour: 13) }
    static var monday: Date { next(weekday: 2, hour: 9) }
    static var thursday: Date { next(weekday: 5, hour: 19) }
    static var friday: Date { next(weekday: 6, hour: 20) }
    static var saturday: Date { next(weekday: 7, hour: 20) }
    static var wednesday: Date { next(weekday: 4, hour: 20) }

    /// The most recent `weekday`, at `hour` o'clock — for the fixtures whose whole purpose is
    /// having already happened.
    ///
    /// `previewToConfirmHappened` is "agreed, and its time has passed": it is what puts the
    /// "did it happen?" question on screen. Dating it forward silently removes that question
    /// from mock mode, the previews and the screenshots, which is a worse bug than the one
    /// naming the right weekday fixes.
    static func previous(weekday: Int, hour: Int, minute: Int = 0) -> Date {
        let calendar = Calendar.current
        let day = calendar.nextDate(
            after: calendar.startOfDay(for: Date()),
            matching: DateComponents(weekday: weekday),
            matchingPolicy: .nextTime,
            direction: .backward
        ) ?? Date().addingTimeInterval(-86_400)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static var lastMonday: Date { previous(weekday: 2, hour: 9) }
}

extension Request {
    static let preview = Request(
        id: "req_1",
        creatorID: User.preview.id,
        recipientIDs: [User.preview2.id],
        category: .relationship,
        title: "Date night this Friday?",
        details: "Want to try that new Italian place?",
        proposedTime: PreviewClock.friday,
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
        proposedTime: PreviewClock.thursday,
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
        proposedTime: PreviewClock.saturday,
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
        proposedTime: PreviewClock.lastMonday,
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
        proposedTime: PreviewClock.wednesday,
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
        proposedTime: PreviewClock.saturday,
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
        proposedTime: PreviewClock.sunday,
        location: "The Anchor",
        status: .accepted,
        negotiationChain: [
            NegotiationMessage(senderID: User.preview2.id, responseType: .accept, text: "I'm in.")
        ],
        createdAt: Date().addingTimeInterval(-50_000),
        updatedAt: Date().addingTimeInterval(-20_000)
    )

    /// A group plan that everybody agreed to a fortnight ago and nobody has mentioned since.
    ///
    /// The state the whole "still on?" feature exists for, and **no other fixture reaches it** —
    /// every plan here was agreed minutes ago in fixture time, so `PlanMomentum` reported them all
    /// healthy and the card appeared in no screenshot, no UI test and no recording. A feature that
    /// only ever renders on a plan nothing generates is a feature nobody would have seen fail.
    static let previewGoneQuiet = Request(
        id: "req_7",
        creatorID: User.preview.id,
        recipientIDs: [User.preview2.id, User.preview3.id],
        category: .friends,
        title: "Climbing on the 20th?",
        details: "The one out past the reservoir.",
        proposedTime: Date().addingTimeInterval(86_400 * 8),
        location: "Fen Wall",
        status: .accepted,
        negotiationChain: [
            NegotiationMessage(
                senderID: User.preview2.id,
                responseType: .accept,
                text: "Yes! Been meaning to go back.",
                timestamp: Date().addingTimeInterval(-86_400 * 12)
            )
        ],
        createdAt: Date().addingTimeInterval(-86_400 * 13),
        updatedAt: Date().addingTimeInterval(-86_400 * 12)
    )

    /// A trip, so the range renders in every screenshot and recording rather than only in a test.
    ///
    /// Every other fixture is a single moment, so nothing reached the state the feature is for —
    /// the same gap that made the quiet-plan card invisible until a fixture was added for it.
    static let previewTrip = Request(
        id: "req_8",
        creatorID: User.preview.id,
        recipientIDs: [User.preview2.id, User.preview3.id],
        category: .travel,
        title: "Barcelona in May?",
        details: "Four nights, flights not booked yet.",
        proposedTime: PreviewClock.trip(daysFromNow: 26, hour: 14),
        endTime: PreviewClock.trip(daysFromNow: 30, hour: 11),
        // The zone Apple reports for Barcelona. Set here so the "8:00 PM Spain Time" line reaches
        // a screenshot rather than only a unit test — the same gap that made the quiet-plan card
        // and the trip range invisible until a fixture reached the state they are for.
        timeZoneID: "Europe/Madrid",
        location: "Barcelona",
        status: .accepted,
        negotiationChain: [
            NegotiationMessage(
                senderID: User.preview2.id,
                responseType: .accept,
                text: "Yes — I'll look at flights.",
                timestamp: Date().addingTimeInterval(-86_400 * 2)
            )
        ],
        createdAt: Date().addingTimeInterval(-86_400 * 3),
        updatedAt: Date().addingTimeInterval(-86_400 * 2)
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
