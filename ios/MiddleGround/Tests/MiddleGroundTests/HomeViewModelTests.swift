import XCTest
import Factory
@testable import MiddleGround

@MainActor
final class HomeViewModelTests: XCTestCase {
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

    // MARK: - The plan that has gone quietest

    private func quiet(
        id: String,
        agreedDaysAgo: Double,
        inDays: Double,
        title: String = "Plan"
    ) -> Request {
        let now = Date()
        var request = Request(
            id: id,
            creatorID: User.preview.id,
            recipientIDs: [User.preview2.id],
            category: .friends,
            title: title,
            proposedTime: now.addingTimeInterval(inDays * 86_400),
            status: .accepted,
            negotiationChain: [
                NegotiationMessage(
                    senderID: User.preview2.id,
                    responseType: .accept,
                    text: nil,
                    timestamp: now.addingTimeInterval(-agreedDaysAgo * 86_400)
                )
            ],
            updatedAt: now.addingTimeInterval(-agreedDaysAgo * 86_400)
        )
        request.status = .accepted
        return request
    }

    /// Only ever one card. A feed that opens with four "this has gone quiet" prompts is a feed
    /// nobody reads the top of, and the prompt becomes wallpaper.
    func testOnlyOneQuietPlanIsOffered() {
        let viewModel = HomeViewModel()
        viewModel.requests = [
            quiet(id: "a", agreedDaysAgo: 20, inDays: 30),
            quiet(id: "b", agreedDaysAgo: 20, inDays: 40),
            quiet(id: "c", agreedDaysAgo: 20, inDays: 50)
        ]

        XCTAssertNotNil(viewModel.quietestPlan)
    }

    /// The one with least time left to rescue gets the slot.
    func testTheMostUrgentQuietPlanWins() {
        let viewModel = HomeViewModel()
        viewModel.requests = [
            quiet(id: "far", agreedDaysAgo: 30, inDays: 40, title: "Far off"),
            quiet(id: "soon", agreedDaysAgo: 9, inDays: 3, title: "Nearly here")
        ]

        XCTAssertEqual(viewModel.quietestPlan?.id, "soon")
    }

    func testAHealthyFeedOffersNothing() {
        let viewModel = HomeViewModel()
        viewModel.requests = [
            quiet(id: "fresh", agreedDaysAgo: 0.5, inDays: 14),
            quiet(id: "chatty", agreedDaysAgo: 1, inDays: 30)
        ]

        XCTAssertNil(viewModel.quietestPlan, "nothing here has gone quiet")
    }

    /// "Leave it" has to mean it, or the card is a snooze button that asks again immediately.
    func testLeavingAPlanAloneRemovesItFromTheSlot() {
        let viewModel = HomeViewModel()
        let plan = quiet(id: "a", agreedDaysAgo: 20, inDays: 30)
        viewModel.requests = [plan]
        XCTAssertNotNil(viewModel.quietestPlan)

        viewModel.leaveQuietPlanAlone(plan)

        XCTAssertNil(viewModel.quietestPlan)
    }

    func testLoadCurrentUserPopulatesUser() async {
        let viewModel = HomeViewModel()
        await viewModel.loadCurrentUser()

        XCTAssertNotNil(viewModel.currentUser)
        XCTAssertEqual(viewModel.currentUser?.id, User.preview.id)
    }

    func testLoadRequestsPopulatesRequests() async {
        let viewModel = HomeViewModel()
        await viewModel.loadCurrentUser()
        await viewModel.loadRequests()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.requests.isEmpty, "mock repository seeds requests")
    }

    // Home no longer loads or shows gamification stats — the streak and growth score live on the
    // Activities tab. The restore that `loadStats` used to perform now happens inside
    // `recordResponse`, covered by GamificationServiceTests.

    /// The header's count must follow whose turn it is, not `status == .pending`.
    ///
    /// A request you have been countered on is not pending — that is the whole point of the
    /// turn-taking model — but it is the one most in need of an answer. Counting `isPending`
    /// reported "Nothing waiting on you" while a live negotiation sat on the user's turn.
    func testAwaitingYouCountIncludesRequestsMidNegotiation() async {
        let viewModel = HomeViewModel()
        await viewModel.loadCurrentUser()
        let me = User.preview.id

        let counteredOnMe = Request(
            creatorID: me,
            recipientIDs: ["partner"],
            category: .friends,
            title: "Movie night?",
            status: .countered,
            negotiationChain: [
                NegotiationMessage(senderID: "partner", responseType: .counter, text: "Sunday?")
            ]
        )
        let awaitingThem = Request(
            creatorID: me,
            recipientIDs: ["partner"],
            category: .daily,
            title: "Swap chores?"
        )
        let settled = Request(
            creatorID: "partner",
            recipientIDs: [me],
            category: .travel,
            title: "Weekend away",
            status: .accepted
        )
        viewModel.requests = [counteredOnMe, awaitingThem, settled]

        XCTAssertTrue(counteredOnMe.canRespond(as: me), "precondition: it is the user's turn")
        XCTAssertFalse(counteredOnMe.isPending, "precondition: and it is not .pending")
        XCTAssertEqual(viewModel.awaitingYouCount, 1)
    }
}
