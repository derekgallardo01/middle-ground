import Factory
import XCTest
@testable import MiddleGround

/// The face a plan wears in the feed.
///
/// The first person to use this app said it "feels like a list" and "needs emojis". The
/// screenshots agreed with him: three cards reading "Coffee tomorrow?", "Drinks on Wednesday?"
/// and "Date night this Friday?" each carried the same monochrome heart, because all three are
/// the `relationship` category and for a couple almost every plan is. An icon that never varies
/// is not information.
///
/// Most of these are about the field surviving the trip to storage and back. That is where this
/// class of change has failed here before — `name` and `seats` were both added to the model and
/// forgotten on the entity, and because the repository is remote-then-local the loss showed up
/// only on a cold launch. A test that builds a `Request`, keeps it in memory and asserts on it
/// would pass with either of those bugs present.
final class PlanEmojiTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppConfiguration.useMockRepositories = true
        Container.shared.authService.register { MockAuthService() }
    }

    override func tearDown() {
        Container.shared.authService.reset()
        AppConfiguration.useMockRepositories = false
        super.tearDown()
    }

    private func plan(category: RequestCategory = .relationship, emoji: String? = nil) -> Request {
        Request(
            creatorID: "user_1",
            recipientIDs: ["user_2"],
            category: category,
            title: "Drinks on Wednesday?",
            emoji: emoji
        )
    }

    // MARK: - What gets shown

    func testAChosenEmojiIsWhatShows() {
        XCTAssertEqual(plan(emoji: "🍸").displayEmoji, "🍸")
    }

    /// Every plan written before the picker existed. They gain colour without being backfilled
    /// to something nobody chose.
    func testAPlanWithNoEmojiFallsBackToItsCategory() {
        XCTAssertEqual(plan(category: .travel).displayEmoji, RequestCategory.travel.emoji)
        XCTAssertEqual(plan(category: .relationship).displayEmoji, "❤️")
    }

    /// Reachable from the admin venue editor, whose emoji field is free text. An empty string is
    /// not a choice, and rendering one leaves a hole where the face should be.
    func testAnEmptyEmojiIsNotAChoice() {
        XCTAssertEqual(plan(category: .chill, emoji: "").displayEmoji, RequestCategory.chill.emoji)
        XCTAssertEqual(plan(category: .chill, emoji: "   ").displayEmoji, RequestCategory.chill.emoji)
    }

    /// The bug this whole change is about: a couple's feed showing one repeated glyph. Categories
    /// need not all differ, but the ones a couple actually uses must.
    func testTheCategoriesACoupleUsesDoNotAllLookTheSame() {
        let faces = [RequestCategory.relationship, .dating, .chill, .daily, .travel].map(\.emoji)
        XCTAssertEqual(Set(faces).count, faces.count, "two categories share a face: \(faces)")
    }

    // MARK: - Surviving storage
    //
    // Both round trips, because the app reads from both: Firestore on a live fetch, SwiftData on
    // a cold launch with no network. A field carried by one and dropped by the other is a feed
    // that looks right until the day somebody opens it on the train.

    func testTheEmojiSurvivesTheFirestoreWireFormat() throws {
        let original = plan(emoji: "🍸")
        let restored = try XCTUnwrap(RequestDTO(from: original).toModel())

        XCTAssertEqual(restored.emoji, "🍸")
    }

    func testTheEmojiSurvivesTheLocalStore() throws {
        let original = plan(emoji: "🎬")
        let restored = try XCTUnwrap(RequestEntity(from: original).toModel())

        XCTAssertEqual(restored.emoji, "🎬")
    }

    /// `update(from:)` is a separate assignment list from `init(from:)`, and only one of them was
    /// wrong when `timeZoneID` went in. Both get asserted.
    func testTheEmojiSurvivesAnUpdateToAnExistingRow() throws {
        let entity = RequestEntity(from: plan(emoji: "🍸"))
        entity.update(from: plan(emoji: "🏨"))

        XCTAssertEqual(try XCTUnwrap(entity.toModel()).emoji, "🏨")
    }

    /// A plan stored before the field existed decodes rather than failing, and lands on nil so
    /// the category fallback runs.
    func testAStoredPlanFromBeforeTheFieldDecodes() throws {
        let json = """
        {
            "id": "req_1",
            "creatorID": "user_1",
            "recipientIDs": ["user_2"],
            "category": "relationship",
            "title": "Drinks on Wednesday?",
            "status": "pending",
            "negotiationChain": [],
            "confirmations": {},
            "createdAt": 0,
            "updatedAt": 0
        }
        """
        let decoded = try JSONDecoder().decode(Request.self, from: Data(json.utf8))

        XCTAssertNil(decoded.emoji)
        XCTAssertEqual(decoded.displayEmoji, "❤️")
    }

    // MARK: - Where the choice comes from

    @MainActor
    func testComposeStartsFromTheCategoryAndFollowsIt() {
        let viewModel = CreateRequestViewModel(category: .relationship)
        XCTAssertEqual(viewModel.emoji, "❤️")

        viewModel.chooseCategory(.travel)
        XCTAssertEqual(viewModel.emoji, "✈️", "the suggestion should follow an unchosen category")
    }

    /// Tapping "🍸 That wine bar" is choosing it. Before this the venue's emoji — the one thing an
    /// operator editing a venue controls about how it looks — was discarded at that tap.
    @MainActor
    func testAPlaceEmojiBecomesThePlansAndOutranksTheCategory() {
        let viewModel = CreateRequestViewModel(category: .relationship)
        viewModel.adoptEmoji(fromPlace: "🍸")

        XCTAssertEqual(viewModel.emoji, "🍸")

        viewModel.chooseCategory(.family)
        XCTAssertEqual(viewModel.emoji, "🍸", "changing category discarded a deliberate choice")
    }

    @MainActor
    func testAnEmptyPlaceEmojiChangesNothing() {
        let viewModel = CreateRequestViewModel(category: .chill)
        viewModel.adoptEmoji(fromPlace: nil)
        viewModel.adoptEmoji(fromPlace: " ")

        XCTAssertEqual(viewModel.emoji, RequestCategory.chill.emoji)
    }

    /// The row must always show the current pick as selected, including one that came from a
    /// venue and is in no category's list — otherwise it renders with nothing highlighted.
    @MainActor
    func testThePickerAlwaysContainsWhatIsSelected() {
        let viewModel = CreateRequestViewModel(category: .family)
        viewModel.chooseEmoji("🦑")

        XCTAssertTrue(viewModel.emojiChoices.contains("🦑"))
        XCTAssertEqual(
            Set(viewModel.emojiChoices).count,
            viewModel.emojiChoices.count,
            "the row is offering the same face twice"
        )
    }

    @MainActor
    func testThePickerOffersWhatTheCategoryTendsToInvolve() {
        let viewModel = CreateRequestViewModel(category: .travel)
        let offered = viewModel.emojiChoices

        for suggestion in PlaceSuggestion.forCategory(.travel) {
            XCTAssertTrue(offered.contains(suggestion.emoji),
                          "\(suggestion.name) is offered as a place but not as a face")
        }
    }

    /// A category with no place suggestions still has to offer something, or the row is empty.
    @MainActor
    func testACategoryWithNoPlacesStillOffersItsOwn() {
        let viewModel = CreateRequestViewModel(category: .daily)

        XCTAssertTrue(PlaceSuggestion.forCategory(.daily).isEmpty)
        XCTAssertEqual(viewModel.emojiChoices, [RequestCategory.daily.emoji])
    }

    // MARK: - What Apple already knew

    func testTheCategoriesTheNearbySearchAsksForAllHaveAFace() {
        // The readable forms `MapKitPlaceDiscoveryProvider.readableCategory` produces for the
        // categories `PlaceKind.pointOfInterestCategories` actually searches.
        let searched = [
            "Restaurant", "Cafe", "Bakery", "Brewery", "Nightlife", "Winery",
            "Hotel", "Theater", "Stadium", "Amusement Park", "Music Venue"
        ]
        for category in searched {
            XCTAssertNotNil(
                PlaceCategoryEmoji.forPointOfInterest(category),
                "the nearby list can return a \(category) and has no face for it"
            )
        }
    }

    /// Unrecognised is nil, not a generic pin: the caller then keeps the category's emoji, which
    /// is a better answer than 📌.
    func testAnUnknownCategoryHasNoOpinion() {
        XCTAssertNil(PlaceCategoryEmoji.forPointOfInterest("Laundromat"))
        XCTAssertNil(PlaceCategoryEmoji.forPointOfInterest(nil))
    }
}
