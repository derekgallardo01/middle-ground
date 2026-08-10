import XCTest
@testable import MiddleGround

/// What is on which day of a trip.
///
/// A trip was one title, one place and a range of dates — enough to agree on going, nothing for
/// the part where four people need to know Thursday's train is at 07:40. The grouping here is
/// derived rather than stored, because a stored day number survives a date change and an item
/// filed under a day the trip no longer has is worse than no itinerary at all.
///
/// Days are computed in the **plan's** zone. That is the whole point of `timeZoneID`: dinner at
/// 20:00 in Barcelona is on the 14th there, and 13:00 on the 14th to somebody in Chicago — which
/// is the same day only by luck, and is a different day for anything after early evening.
final class ItineraryTests: XCTestCase {

    /// 2027-05-12 09:00 UTC — 11:00 in Madrid, so a whole day is comfortably inside both zones.
    private let start = Date(timeIntervalSince1970: 1_810_112_400)

    private func trip(nights: Double = 4, zone: String? = nil) -> Request {
        Request(
            creatorID: "user_1",
            recipientIDs: ["user_2"],
            category: .travel,
            title: "Barcelona",
            proposedTime: start,
            endTime: start.addingTimeInterval(nights * 86_400),
            timeZoneID: zone
        )
    }

    private func item(
        _ title: String,
        dayOffset: Double? = nil,
        hour: Double = 0,
        author: String = "user_1",
        created: Double = 0
    ) -> ItineraryItem {
        ItineraryItem(
            authorID: author,
            title: title,
            at: dayOffset.map { start.addingTimeInterval($0 * 86_400 + hour * 3_600) },
            createdAt: start.addingTimeInterval(created)
        )
    }

    // MARK: - The shape of a trip

    func testEveryDayOfTheTripAppearsIncludingTheEmptyOnes() {
        let days = trip().itineraryDays(from: [item("Dinner", dayOffset: 2)])

        XCTAssertEqual(days.count, 5, "a four-night trip has five days")
        XCTAssertEqual(days.map(\.number), [1, 2, 3, 4, 5])
        // "Nothing on Wednesday yet" is information. A list that skips empty days cannot be read
        // as an itinerary — it reads as a list of items.
        XCTAssertEqual(days.filter { $0.items.isEmpty }.count, 4)
    }

    func testAnItemLandsOnItsOwnDay() {
        let days = trip().itineraryDays(from: [item("Train", dayOffset: 3)])

        XCTAssertEqual(days[3].items.map(\.title), ["Train"])
        XCTAssertTrue(days[0].items.isEmpty)
    }

    func testItemsOnOneDayAreInTimeOrder() {
        let days = trip().itineraryDays(from: [
            item("Dinner", dayOffset: 1, hour: 9),
            item("Museum", dayOffset: 1, hour: 2),
            item("Coffee", dayOffset: 1, hour: 1)
        ])

        XCTAssertEqual(days[1].items.map(\.title), ["Coffee", "Museum", "Dinner"])
    }

    /// Two things genuinely at the same time are ordered by when they were added, so the list does
    /// not reshuffle between reads — the same rule the recipient picker and the referral table
    /// needed, for the same reason.
    func testATieBreaksByWhenItWasAdded() {
        let days = trip().itineraryDays(from: [
            item("Second", dayOffset: 1, hour: 9, created: 200),
            item("First", dayOffset: 1, hour: 9, created: 100)
        ])

        XCTAssertEqual(days[1].items.map(\.title), ["First", "Second"])
    }

    // MARK: - Days belong to the trip, not to the reader

    /// The failure the plan's zone exists to prevent. 23:00 in Barcelona on day two is 16:00 the
    /// same day in Chicago and 22:00 in London — but 00:30 in Barcelona is the *next* day there
    /// and the previous evening to a reader further west.
    func testAnEveningItemStaysOnItsOwnEveningAbroad() throws {
        let madrid = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
        // 23:30 Madrid on day two of the trip.
        var calendar = Calendar.current
        calendar.timeZone = madrid
        let dayTwo = calendar.startOfDay(for: start.addingTimeInterval(86_400))
        let lateDinner = try XCTUnwrap(calendar.date(byAdding: .hour, value: 23, to: dayTwo))

        let abroad = trip(zone: "Europe/Madrid")
        let days = abroad.itineraryDays(from: [
            ItineraryItem(authorID: "user_1", title: "Late dinner", at: lateDinner)
        ])

        let carrying = days.filter { !$0.items.isEmpty }
        XCTAssertEqual(carrying.count, 1)
        XCTAssertEqual(carrying.first?.number, 2, "the late dinner moved off its own evening")
    }

    /// And a plan with no zone still groups on the reader's calendar, exactly as before.
    func testAPlanWithNoZoneGroupsOnTheReadersCalendar() {
        let days = trip().itineraryDays(from: [item("Lunch", dayOffset: 2)])

        let firstCarrying = days.first { !$0.items.isEmpty }
        XCTAssertEqual(firstCarrying?.number, 3)
    }

    // MARK: - Items that do not have a day

    func testAnItemWithNoTimeIsNotFiledUnderDayOne() {
        let items = [item("Somewhere for lunch"), item("Train", dayOffset: 1)]
        let plan = trip()

        let filed = plan.itineraryDays(from: items).contains { day in
            day.items.contains { $0.title == "Somewhere for lunch" }
        }
        XCTAssertFalse(filed, "an item nobody has pinned down was silently given a day")
        XCTAssertEqual(plan.unscheduledItinerary(from: items).map(\.title), ["Somewhere for lunch"])
    }

    func testUnscheduledItemsKeepTheOrderTheyWereAddedIn() {
        let items = [item("Third", created: 300), item("First", created: 100), item("Second", created: 200)]

        XCTAssertEqual(
            trip().unscheduledItinerary(from: items).map(\.title),
            ["First", "Second", "Third"]
        )
    }

    // MARK: - What a date change does

    /// Moving a trip strands everything already arranged. Dropping those items loses work people
    /// did; keeping them in day one puts a booking on the wrong morning. They are surfaced.
    func testItemsOutsideTheTripAreShownRatherThanLostOrMisfiled() {
        let items = [item("Old dinner", dayOffset: 9), item("Train", dayOffset: 1)]
        let plan = trip()

        XCTAssertEqual(plan.strandedItinerary(from: items).map(\.title), ["Old dinner"])
        XCTAssertFalse(
            plan.itineraryDays(from: items).contains { $0.items.contains { $0.title == "Old dinner" } },
            "an item outside the trip was filed inside it"
        )
    }

    func testAnItemBeforeTheTripIsStrandedToo() {
        XCTAssertEqual(
            trip().strandedItinerary(from: [item("Too early", dayOffset: -3)]).map(\.title),
            ["Too early"]
        )
    }

    func testNothingIsStrandedWhenEverythingFits() {
        let items = [item("A", dayOffset: 0), item("B", dayOffset: 4), item("C")]

        XCTAssertTrue(trip().strandedItinerary(from: items).isEmpty)
    }

    // MARK: - Plans that are not trips

    func testASingleMomentPlanHasOneDay() {
        var dinner = trip()
        dinner.endTime = nil

        XCTAssertEqual(dinner.itineraryDays(from: []).count, 1)
    }

    func testAPlanWithNoTimeHasNoDaysAtAll() {
        var chore = trip()
        chore.proposedTime = nil

        XCTAssertTrue(chore.itineraryDays(from: [item("Anything")]).isEmpty)
        XCTAssertTrue(chore.strandedItinerary(from: [item("Anything", dayOffset: 1)]).isEmpty)
    }

    // MARK: - What an item is allowed to be

    func testATitleIsTrimmedAndCapped() {
        let long = ItineraryItem(authorID: "u", title: "  " + String(repeating: "a", count: 500))

        XCTAssertEqual(long.title.count, RequestLimits.title)
        XCTAssertFalse(long.title.hasPrefix(" "))
    }

    func testALocationIsCappedToo() {
        let item = ItineraryItem(
            authorID: "u", title: "Dinner", location: String(repeating: "b", count: 500)
        )

        XCTAssertEqual(item.location?.count, RequestLimits.location)
    }

    /// Items written before a field existed have to decode, the same tolerance `Request` has.
    func testAnItemWrittenBeforeCreatedAtExistedStillDecodes() throws {
        let json = #"{"id":"i1","authorID":"u1","title":"Train"}"#

        let item = try JSONDecoder().decode(ItineraryItem.self, from: Data(json.utf8))

        XCTAssertEqual(item.title, "Train")
        XCTAssertNil(item.at)
        XCTAssertFalse(item.isScheduled)
    }
}
