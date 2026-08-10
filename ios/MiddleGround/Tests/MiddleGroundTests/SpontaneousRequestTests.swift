import Factory
import XCTest
@testable import MiddleGround

/// "Who's about?" — the quick invite with a window on it.
///
/// This file exists because coverage was measured for the first time and this view model came back
/// at **0%**: 111 lines of a user-facing feature that no test had ever executed. Two real bugs were
/// sitting in it, and both are the kind that only look wrong when somebody has more than one group
/// — which is exactly the state a fixture never reaches by accident.
final class SpontaneousRequestTests: XCTestCase {

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

    private func group(
        id: String,
        members: [String],
        code: String,
        type: RelationshipType = .friends,
        name: String? = nil
    ) -> Relationship {
        Relationship(
            id: id,
            participantIDs: members,
            type: type,
            name: name,
            inviteCode: code,
            seats: 8
        )
    }

    // MARK: - Which code gets shared

    /// The bug. Profile and Compose were both fixed for this; this third copy was missed.
    ///
    /// With two unpaired groups, `first { !$0.isPaired }` returns whichever happens to be first —
    /// so the screen offers a code for a group the person was not thinking about, and whoever
    /// redeems it lands somewhere nobody chose.
    @MainActor
    func testNoCodeIsOfferedWhenSeveralGroupsCouldOwnIt() {
        let model = SpontaneousRequestViewModel()
        model.relationships = [
            group(id: "a", members: [User.preview.id], code: "AAAAAA"),
            group(id: "b", members: [User.preview.id], code: "BBBBBB")
        ]

        XCTAssertNil(
            model.inviteCode,
            "an arbitrary group's code was offered — the invitee lands somewhere nobody picked"
        )
    }

    @MainActor
    func testTheCodeIsOfferedWhenOnlyOneGroupCouldOwnIt() {
        let model = SpontaneousRequestViewModel()
        model.relationships = [
            group(id: "a", members: [User.preview.id], code: "AAAAAA"),
            group(id: "paired", members: [User.preview.id, User.preview2.id], code: "CCCCCC")
        ]

        XCTAssertEqual(model.inviteCode, "AAAAAA")
    }

    @MainActor
    func testNoCodeWhenEveryGroupIsAlreadyPaired() {
        let model = SpontaneousRequestViewModel()
        model.relationships = [
            group(id: "paired", members: [User.preview.id, User.preview2.id], code: "CCCCCC")
        ]

        XCTAssertNil(model.inviteCode)
    }

    // MARK: - Who you are asking

    /// The second bug. `displayLabels` is keyed by *relationship* and describes the whole group —
    /// "Sam and Priya" for a group of three — so labelling each member with it produced two rows
    /// reading the same thing, in the picker whose only job is saying who you are asking.
    @MainActor
    func testEachPersonIsNamedIndividuallyNotByTheirGroup() async {
        let model = SpontaneousRequestViewModel()
        model.currentUser = .preview
        model.relationships = [
            group(id: "trio", members: [User.preview.id, User.preview2.id, User.preview3.id], code: "TRIOAA")
        ]
        model.displayLabels = ["trio": "Sam and Priya"]

        await model.loadCurrentUserAndPartners()

        let names = model.everyone.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "two people came back with the same name: \(names)")
        XCTAssertFalse(
            names.contains("Sam and Priya"),
            "a person was labelled with their whole group: \(names)"
        )
    }

    /// Somebody in two groups is one person, asked once.
    @MainActor
    func testSomebodyInTwoGroupsAppearsOnce() async {
        let model = SpontaneousRequestViewModel()
        model.currentUser = .preview
        model.relationships = [
            group(id: "one", members: [User.preview.id, User.preview2.id], code: "ONEAAA"),
            group(id: "two", members: [User.preview.id, User.preview2.id], code: "TWOAAA")
        ]

        await model.loadCurrentUserAndPartners()

        XCTAssertEqual(model.everyone.filter { $0.id == User.preview2.id }.count, 1)
    }

    @MainActor
    func testYouAreNotOnTheListOfPeopleToAsk() async {
        let model = SpontaneousRequestViewModel()
        model.currentUser = .preview
        model.relationships = [
            group(id: "one", members: [User.preview.id, User.preview2.id], code: "ONEAAA")
        ]

        await model.loadCurrentUserAndPartners()

        XCTAssertFalse(model.everyone.contains { $0.id == User.preview.id })
    }

    // MARK: - What may be sent

    /// Nobody asked, in the app or outside it, is not a plan.
    @MainActor
    func testYouCannotSendToNobody() {
        let model = SpontaneousRequestViewModel()

        XCTAssertFalse(model.canSubmit)

        model.invitesSomeoneOutside = true
        XCTAssertTrue(model.canSubmit, "inviting somebody outside the app is asking somebody")
    }

    /// The title is optional on purpose — "who's about?" is the whole point — so the feed needs a
    /// readable fallback rather than a blank row.
    @MainActor
    func testAnEmptyTitleStillReadsAsSomething() {
        let model = SpontaneousRequestViewModel()

        XCTAssertFalse(model.resolvedTitle.isEmpty)
        model.title = "   "
        XCTAssertFalse(model.resolvedTitle.isEmpty, "whitespace was accepted as a title")
        model.title = "Coffee?"
        XCTAssertEqual(model.resolvedTitle, "Coffee?")
    }

    /// The window and the time are different questions. `proposedTime` used to be
    /// `now + expiresInMinutes`, so "expires in 30 minutes" and "happening in 30 minutes" were one
    /// value and neither could be set alone.
    @MainActor
    func testTheExpiryWindowAndTheEventTimeAreSeparate() async {
        let model = SpontaneousRequestViewModel()
        model.currentUser = .preview
        model.recipientIDs = [User.preview2.id]
        model.hasEventTime = true
        model.eventTime = Date().addingTimeInterval(6 * 3_600)
        model.expiresInMinutes = 30

        let sent = await model.sendRequest()

        let proposed = try? XCTUnwrap(sent?.proposedTime)
        XCTAssertNotNil(proposed)
        XCTAssertGreaterThan(
            proposed ?? .distantPast,
            Date().addingTimeInterval(3 * 3_600),
            "the chosen time was overwritten by the expiry window"
        )
    }

    @MainActor
    func testWithNoChosenTimeThePlanLandsAtTheEndOfTheWindow() async {
        let model = SpontaneousRequestViewModel()
        model.currentUser = .preview
        model.recipientIDs = [User.preview2.id]
        model.hasEventTime = false
        model.expiresInMinutes = 45

        let sent = await model.sendRequest()

        let proposed = try? XCTUnwrap(sent?.proposedTime)
        XCTAssertNotNil(proposed)
        XCTAssertGreaterThan(proposed ?? .distantPast, Date().addingTimeInterval(40 * 60))
        XCTAssertLessThan(proposed ?? .distantFuture, Date().addingTimeInterval(50 * 60))
    }

    @MainActor
    func testASpontaneousPlanIsCategorisedAsOne() async {
        let model = SpontaneousRequestViewModel()
        model.currentUser = .preview
        model.recipientIDs = [User.preview2.id]

        let sent = await model.sendRequest()

        XCTAssertEqual(sent?.category, .spontaneous)
        XCTAssertFalse(model.isLoading, "the spinner was left running")
    }
}
