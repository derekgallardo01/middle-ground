import XCTest
import Factory
@testable import MiddleGround

@MainActor
final class GamificationViewModelTests: XCTestCase {
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

    func testLoadGamificationDataPopulatesStats() async {
        let viewModel = GamificationViewModel()
        await viewModel.loadCurrentUser()
        await viewModel.loadGamificationData()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertGreaterThanOrEqual(viewModel.stats.level, 1)
    }

    func testProgressToNextLevelIsClamped() {
        let viewModel = GamificationViewModel()
        viewModel.stats = GamificationStats(streakDays: 0, relationshipXP: 1000, level: 1, growthScore: 0, nextLevelXP: 500)

        XCTAssertEqual(viewModel.progressToNextLevel, 1.0)
    }
}
