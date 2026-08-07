import Factory
import SwiftData
import XCTest
@testable import MiddleGround

/// Sending a plan to a group, rather than to one person out of it.
///
/// Compose used to key its recipient picker on "the first participant who is not me". With the
/// fixtures — a couple of `[me, Sam]` and a group of `[me, Sam, Priya]` — that is `Sam` for both,
/// so two rows carried one tag and SwiftUI kept whichever it saw last. The group could not be
/// selected at all, and `createRequest` sent to `[recipientID]`: had it been selectable, the plan
/// would have gone to Sam alone wearing the group's name.
///
/// Nothing caught it. `Request.recipientIDs` has always been a list and the rules have always
/// worked in `allParticipantIDs` — only compose was addressing one person, and no test asked who
/// a group plan was actually sent to.
@MainActor
final class GroupRecipientTests: XCTestCase {
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

    private func loaded() async -> CreateRequestViewModel {
        let viewModel = CreateRequestViewModel()
        await viewModel.loadCurrentUserAndPartners()
        return viewModel
    }

    // MARK: - What a group is called

    /// The cache dropped `name`, and `CachedRelationshipRepository` reads from the cache, so
    /// every named group came back nameless. Nothing failed — it just quietly said the wrong
    /// thing, and a recording of "Sunday hikers" showed "Sam".
    func testAGroupKeepsItsNameThroughTheCache() {
        let entity = RelationshipEntity(from: .previewGroup)

        XCTAssertEqual(entity.toModel()?.name, "Sunday hikers", "the cache lost the group's name")
    }

    func testRenamingSurvivesTheCacheToo() {
        let entity = RelationshipEntity(from: .previewGroup)
        var renamed = Relationship.previewGroup
        renamed.name = "Thursday climbers"

        entity.update(from: renamed)

        XCTAssertEqual(entity.toModel()?.name, "Thursday climbers")
    }

    /// `partnerID(excluding:)` says in its own doc comment that it returns an arbitrary
    /// participant for a group, and the label builder called it regardless.
    func testAnUnnamedGroupIsLabelledWithEveryoneInIt() {
        XCTAssertEqual(RelationshipService.joined(["Sam"]), "Sam")
        XCTAssertEqual(RelationshipService.joined(["Sam", "Priya"]), "Sam & Priya")
        XCTAssertEqual(RelationshipService.joined(["Sam", "Priya", "Jo"]), "Sam, Priya & Jo")
    }

    /// A picker row is one line. Naming eleven people is not a label.
    func testALongListStopsNamingEverybody() {
        let many = ["Sam", "Priya", "Jo", "Ada", "Ben"]

        XCTAssertEqual(RelationshipService.joined(many), "Sam, Priya & 3 others")
    }

    func testNobodyToNameFallsBackRatherThanRenderingBlank() {
        XCTAssertNil(RelationshipService.joined([]))
    }

    /// The repository returned the group before the couple, and could return either first
    /// tomorrow. An unordered picker makes "who is this addressed to on open" a coin flip.
    func testPairsAreListedBeforeGroups() async {
        let viewModel = await loaded()

        let sizes = viewModel.relationships.map(\.participantIDs.count)
        XCTAssertEqual(sizes, sizes.sorted(), "the list must not reshuffle between launches")
        XCTAssertEqual(viewModel.relationships.first?.id, "rel_1")
    }

    /// The two fixtures must be separately selectable, which is exactly what a shared tag
    /// prevented.
    func testACoupleAndAGroupAreDistinctChoices() async {
        let viewModel = await loaded()

        let ids = viewModel.relationships.map(\.id)
        XCTAssertTrue(ids.contains("rel_1"), "the couple is missing")
        XCTAssertTrue(ids.contains("rel_2"), "the group is missing")
        XCTAssertEqual(Set(ids).count, ids.count, "two rows sharing an identifier cannot both be picked")
    }

    func testChoosingACoupleAddressesOnePerson() async {
        let viewModel = await loaded()
        viewModel.selectedRelationshipID = "rel_1"

        XCTAssertEqual(viewModel.recipients, [User.preview2.id])
    }

    /// The actual bug: a group plan has to reach everybody in the group.
    func testChoosingAGroupAddressesEverybodyInIt() async {
        let viewModel = await loaded()
        viewModel.selectedRelationshipID = "rel_2"

        XCTAssertEqual(
            Set(viewModel.recipients),
            Set([User.preview2.id, User.preview3.id]),
            "a plan sent to a group of three reached only one of them"
        )
        XCTAssertFalse(viewModel.recipients.contains(User.preview.id), "never address yourself")
    }

    func testTheCreatedRequestCarriesEveryRecipient() async {
        let viewModel = await loaded()
        viewModel.selectedRelationshipID = "rel_2"
        viewModel.title = "Sunday walk?"

        let request = await viewModel.createRequest()

        let created = try? XCTUnwrap(request)
        XCTAssertEqual(
            Set(created?.recipientIDs ?? []),
            Set([User.preview2.id, User.preview3.id])
        )
        // The field the security rules and every query actually work in.
        XCTAssertEqual(
            Set(created?.allParticipantIDs ?? []),
            Set([User.preview.id, User.preview2.id, User.preview3.id])
        )
    }

    /// `-MGComposeGroup` exists so a recording can start on a group without driving the picker
    /// menu, which lost three takes. Verified here rather than by watching a video.
    func testTheGroupLaunchArgumentSelectsTheGroup() async {
        AppConfiguration.prefersGroupRecipient = true
        defer { AppConfiguration.prefersGroupRecipient = false }

        let viewModel = await loaded()

        XCTAssertEqual(viewModel.selectedRelationshipID, "rel_2", "it did not start on the group")
        XCTAssertEqual(Set(viewModel.recipients), Set([User.preview2.id, User.preview3.id]))
    }

    func testWithoutTheArgumentItStartsOnTheFirstRelationship() async {
        AppConfiguration.prefersGroupRecipient = false

        let viewModel = await loaded()

        XCTAssertEqual(viewModel.selectedRelationshipID, "rel_1", "a couple should lead")
    }

    func testNothingCanBeSentUntilSomebodyIsChosen() async {
        let viewModel = await loaded()
        viewModel.title = "Dinner?"
        viewModel.selectedRelationshipID = ""

        XCTAssertTrue(viewModel.recipients.isEmpty)
        XCTAssertFalse(viewModel.canSubmit, "a plan addressed to nobody must not be sendable")
    }

    /// Availability is looked up by relationship now, rather than by "whichever group contains
    /// this person" — ambiguous the moment somebody is in both a couple and a group with them.
    ///
    /// Asserted only as far as it can be from outside: `groupMembers` is private, and widening a
    /// production property so a test can read it would be a worse trade than this narrower check.
    func testAvailabilityLoadsForTheChosenGroup() async {
        let viewModel = await loaded()
        viewModel.selectedRelationshipID = "rel_2"

        await viewModel.loadGroupAvailability()

        XCTAssertEqual(viewModel.selectedRelationshipID, "rel_2", "the selection must survive the load")
        XCTAssertEqual(Set(viewModel.recipients), Set([User.preview2.id, User.preview3.id]))
    }
}
