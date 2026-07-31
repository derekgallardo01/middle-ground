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

    func testLoadStatsPopulatesStats() async {
        let viewModel = HomeViewModel()
        await viewModel.loadCurrentUser()
        await viewModel.loadStats()

        XCTAssertGreaterThanOrEqual(viewModel.stats.level, 1)
    }

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
