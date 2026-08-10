import Factory
import XCTest
@testable import MiddleGround

/// Signing up, which is the one flow every user goes through exactly once.
///
/// It had **no tests at all** — not because nobody thought it mattered, but because the type could
/// not be constructed in this target: it holds `NotificationService.shared`, whose init called
/// `UNUserNotificationCenter.current()`, which raises `NSInternalInconsistencyException` when there
/// is no bundle proxy and takes the whole runner down with it. Guarding that (see
/// `NotificationService.isRunningInAnApp`) is what made these possible, and this is the surface
/// that most deserved them: the live bug it shipped with — a group code answered as a plan code —
/// was in the branch below and nothing anywhere would have caught it.
final class OnboardingViewModelTests: XCTestCase {

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

    @MainActor
    private func viewModel() -> OnboardingViewModel {
        OnboardingViewModel()
    }

    // MARK: - Which step, and when you may leave it

    @MainActor
    func testYouCannotLeaveTheNameStepWithoutANameOnIt() {
        let model = viewModel()
        model.currentStep = .profile

        model.userName = ""
        XCTAssertFalse(model.canContinue)

        // Whitespace is not a name. Without the trim this passes, and the name that reaches the
        // user document is "   " — which is the exact state `AppState` now sends back here.
        model.userName = "   "
        XCTAssertFalse(model.canContinue, "spaces were accepted as a name")

        model.userName = "Derek"
        XCTAssertTrue(model.canContinue)
    }

    @MainActor
    func testCreatingAGroupNeedsNothingExtraButJoiningNeedsAWholeCode() {
        let model = viewModel()
        model.currentStep = .relationship

        model.pairingMode = .create
        XCTAssertTrue(model.canContinue)

        model.pairingMode = .join
        model.inviteCodeInput = ""
        XCTAssertFalse(model.canContinue)

        // Five characters is not a code. A floor rather than an exact length used to wave through
        // a pasted message body, which the server then rejected with a raw error.
        model.inviteCodeInput = "MG24K"
        XCTAssertFalse(model.canContinue)

        model.inviteCodeInput = Relationship.preview.inviteCode
        XCTAssertTrue(model.canContinue)
    }

    @MainActor
    func testAdvancingWalksTheStepsInOrderAndStopsAtTheEnd() {
        let model = viewModel()
        XCTAssertEqual(model.currentStep, .welcome)

        var seen: [OnboardingViewModel.Step] = [model.currentStep]
        for _ in 0..<10 {
            model.advance()
            seen.append(model.currentStep)
        }

        XCTAssertEqual(Array(seen.prefix(5)), OnboardingViewModel.Step.allCases)
        XCTAssertEqual(model.currentStep, .done, "advancing past the end left the flow")
    }

    // MARK: - Finishing it

    @MainActor
    func testFinishingWithANewGroupSavesTheNameAndHandsBackACode() async {
        let model = viewModel()
        model.userName = "  Derek  "
        model.pairingMode = .create
        model.selectedRelationshipType = .couple

        let user = await viewModel(from: model)

        XCTAssertEqual(user?.name, "Derek", "the name was stored untrimmed")
        XCTAssertNotNil(model.createdInviteCode, "nothing to share on the last step")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    private func viewModel(from model: OnboardingViewModel) async -> User? {
        await model.completeOnboarding()
    }

    /// The bug this flow shipped with. Your own group code is a group problem, and answering it
    /// with "that invite code doesn't match a plan" names a distinction the sender never made.
    @MainActor
    func testYourOwnCodeIsReportedAsYourOwnCode() async {
        let model = viewModel()
        model.userName = "Derek"
        model.pairingMode = .join
        // `MockRelationshipRepository` owns this code as `User.preview`, who is signed in.
        model.inviteCodeInput = Relationship.preview.inviteCode

        let user = await model.completeOnboarding()

        XCTAssertNil(user, "a failed join reported success")
        XCTAssertEqual(
            model.errorMessage,
            UserFacingError.message(for: RelationshipService.PairingError.ownCode)
        )
    }

    /// A code that names nothing must not name a kind either.
    @MainActor
    func testACodeThatMatchesNothingDoesNotBlameEitherKind() async {
        let model = viewModel()
        model.userName = "Derek"
        model.pairingMode = .join
        model.inviteCodeInput = "ZZZZZZ"

        _ = await model.completeOnboarding()

        XCTAssertEqual(
            model.errorMessage,
            UserFacingError.message(for: RelationshipService.PairingError.codeNotFound)
        )
    }

    /// A failure has to leave the flow where it was. Advancing anyway drops somebody on "you're
    /// all set" having joined nothing.
    @MainActor
    func testAFailedJoinDoesNotFinishTheFlow() async {
        let model = viewModel()
        model.userName = "Derek"
        model.pairingMode = .join
        model.inviteCodeInput = "ZZZZZZ"
        model.currentStep = .relationship

        _ = await model.completeOnboarding()

        XCTAssertEqual(model.currentStep, .relationship, "a failure walked on to the next step")
        XCTAssertFalse(model.isLoading, "the spinner was left running")
    }

    /// Nobody signed in cannot finish, and must say so rather than silently doing nothing.
    @MainActor
    func testFinishingWithoutASessionSaysSo() async {
        Container.shared.authService.register { MockAuthService(mockUser: nil) }
        let model = viewModel()
        model.userName = "Derek"

        let user = await model.completeOnboarding()

        XCTAssertNil(user)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    /// The last step exists to be read: the code is on it, and handing the user straight to
    /// `AppState` used to flip the root view before anybody could see it.
    @MainActor
    func testTheUserIsHeldUntilTheLastStepIsDismissed() async {
        let model = viewModel()
        model.userName = "Derek"
        model.pairingMode = .create
        // Where the button actually is. Called from `.welcome` this advances to `.permissions`,
        // which is what the first version of this test asserted against and why it failed.
        model.currentStep = .relationship

        _ = await model.completeOnboarding()

        XCTAssertNotNil(model.completedUser)
        XCTAssertEqual(model.currentStep, .done)
    }
}
