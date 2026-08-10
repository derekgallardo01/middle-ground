import Factory
import XCTest
@testable import MiddleGround

/// Getting out of a half-finished sign-up.
///
/// `signInWithApple` saves the user document at the **welcome** step, and "has a user" was the
/// whole test for "is onboarded" — so quitting anywhere before the profile step left somebody
/// signed in with no name, on Home, with nothing that could set one. Onboarding was the only
/// screen in the app that ever wrote a user's name, and Apple hands one over on the first sign-in
/// and never again, so that state was permanent: "Guest" to themselves and to everybody in every
/// group they later joined.
///
/// Two fixes, tested here: an account with no name resumes onboarding, and Profile can set a name
/// for anybody already in that state.
final class OnboardingRecoveryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppConfiguration.useMockRepositories = true
    }

    override func tearDown() {
        Container.shared.authService.reset()
        AppConfiguration.useMockRepositories = false
        super.tearDown()
    }

    private func signIn(as user: User?) {
        Container.shared.authService.register { MockAuthService(mockUser: user) }
    }

    private func nameless() -> User {
        var user = User.preview
        user.name = ""
        return user
    }

    // MARK: - Whether the flow is finished

    @MainActor
    func testAnAccountWithNoNameIsSentBackToFinishSigningUp() async {
        signIn(as: nameless())
        let state = AppState()

        await state.checkAuthState()

        XCTAssertFalse(
            state.isOnboarded,
            "a signed-in account with no name landed on Home, where nothing could give it one"
        )
    }

    /// Whitespace is not a name. Onboarding trims before checking, so this has to as well or the
    /// two disagree and somebody sits in a loop.
    @MainActor
    func testANameOfOnlySpacesIsNotAName() async {
        var user = User.preview
        user.name = "   "
        signIn(as: user)
        let state = AppState()

        await state.checkAuthState()

        XCTAssertFalse(state.isOnboarded)
    }

    /// And every account that finished is untouched, which is all of them.
    @MainActor
    func testAnAccountWithANameGoesStraightIn() async {
        signIn(as: .preview)
        let state = AppState()

        await state.checkAuthState()

        XCTAssertTrue(state.isOnboarded)
    }

    @MainActor
    func testNobodySignedInIsNotOnboardedEither() async {
        signIn(as: nil)
        let state = AppState()

        await state.checkAuthState()

        XCTAssertFalse(state.isOnboarded)
    }

    // MARK: - Fixing it from Profile

    @MainActor
    func testSomebodyWithNoNameIsToldSoAndCanFixIt() async {
        signIn(as: nameless())
        let viewModel = ProfileViewModel()
        await viewModel.loadUser()

        XCTAssertTrue(viewModel.hasNoName)
        XCTAssertEqual(viewModel.displayName, ProfileViewModel.unnamed)

        viewModel.beginEditingDisplayName()
        viewModel.displayNameInput = "Derek"
        await viewModel.commitDisplayName()

        XCTAssertEqual(viewModel.displayName, "Derek")
        XCTAssertFalse(viewModel.hasNoName)
        XCTAssertFalse(viewModel.isEditingDisplayName)
    }

    /// Saving an empty field must not put somebody back in the state this exists to escape.
    @MainActor
    func testClearingTheFieldDoesNotEraseYourName() async {
        signIn(as: .preview)
        let viewModel = ProfileViewModel()
        await viewModel.loadUser()

        viewModel.beginEditingDisplayName()
        viewModel.displayNameInput = "   "
        await viewModel.commitDisplayName()

        XCTAssertEqual(viewModel.displayName, User.preview.name)
        XCTAssertFalse(viewModel.hasNoName)
    }

    /// Long enough to be a name, short enough for the rows it appears in — the same cap group
    /// names carry, for the same reason.
    @MainActor
    func testAVeryLongNameIsTrimmedRatherThanRefused() async {
        signIn(as: nameless())
        let viewModel = ProfileViewModel()
        await viewModel.loadUser()

        viewModel.beginEditingDisplayName()
        viewModel.displayNameInput = String(repeating: "a", count: 200)
        await viewModel.commitDisplayName()

        XCTAssertEqual(viewModel.displayName.count, RequestLimits.groupName)
    }

    /// The editor opens on what is already there, not on an empty field — retyping your whole
    /// name to correct one letter is the small insult that stops people bothering.
    @MainActor
    func testTheEditorOpensOnYourCurrentName() async {
        signIn(as: .preview)
        let viewModel = ProfileViewModel()
        await viewModel.loadUser()

        viewModel.beginEditingDisplayName()

        XCTAssertEqual(viewModel.displayNameInput, User.preview.name)
    }
}
