import Factory
import XCTest
@testable import MiddleGround

/// Reporting somebody, and disagreeing about what happened.
///
/// App Review guideline 1.2 requires an app carrying user-generated content to offer a way to
/// report it. `RequestDetailViewModel+Reporting.swift` came back at **0%** when coverage was first
/// measured — 92 lines, never executed by a test — and held two defects, both of which this file
/// exists to keep fixed.
///
/// The second one matters more than it looks. A report names a person. Getting the *wrong* person
/// into that field is not a cosmetic bug: it is an accusation filed against somebody who was not
/// chosen, by a person who thought they were choosing.
final class ReportingTests: XCTestCase {

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
    private func groupPlan() -> RequestDetailViewModel {
        var request = Request(
            creatorID: User.preview2.id,
            recipientIDs: [User.preview.id, User.preview3.id],
            category: .friends,
            title: "Sunday roast?"
        )
        request.status = .accepted
        return RequestDetailViewModel(request: request)
    }

    // MARK: - The control has to be there when it is needed

    /// The bug. `reportableParticipants` guarded on `currentUser`, which waits on a Firestore
    /// fetch of the display name, while everything else on this screen uses `currentUserID` from
    /// memory. For that half second `canReport` was false and the report control — the thing
    /// guideline 1.2 is about — was simply not in the toolbar.
    @MainActor
    func testReportingIsOfferedBeforeTheProfileFetchLands() {
        let model = groupPlan()
        // Exactly the state after launch: the ID is known, the profile document is not back yet.
        model.currentUser = nil

        XCTAssertNotNil(model.currentUserID, "the premise of this test no longer holds")
        XCTAssertTrue(
            model.canReport,
            "the report control was missing while the profile was still loading"
        )
    }

    @MainActor
    func testYouAreNeverOnTheListOfPeopleToReport() {
        let model = groupPlan()

        XCTAssertFalse(model.reportableParticipants.contains { $0.id == User.preview.id })
        XCTAssertEqual(model.reportableParticipants.count, 2)
    }

    /// A plan with nobody else on it has nobody to report, so the control stays away.
    @MainActor
    func testAPlanWithNobodyElseOffersNoReport() {
        var alone = Request(
            creatorID: User.preview.id,
            recipientIDs: [],
            category: .daily,
            title: "Bins"
        )
        alone.status = .accepted
        let model = RequestDetailViewModel(request: alone)

        XCTAssertFalse(model.canReport)
        XCTAssertTrue(model.reportableParticipants.isEmpty)
    }

    // MARK: - Who the report is about

    /// With two people the question has one answer, so asking it is noise.
    @MainActor
    func testATwoPersonPlanPreselectsTheOnlyPossibleSubject() {
        var pair = Request(
            creatorID: User.preview2.id,
            recipientIDs: [User.preview.id],
            category: .relationship,
            title: "Dinner?"
        )
        pair.status = .accepted
        let model = RequestDetailViewModel(request: pair)

        model.beginReport()

        XCTAssertEqual(model.reportedUserID, User.preview2.id)
        XCTAssertTrue(model.showReportSheet)
    }

    /// The second bug, and the one with teeth. `Cancel` only dismisses the sheet — it never
    /// cleared the selection — so a choice made and abandoned survived into the next visit, with
    /// Submit already enabled against somebody the person had not picked this time.
    @MainActor
    func testAnAbandonedChoiceDoesNotSurviveIntoTheNextReport() {
        let model = groupPlan()

        model.beginReport()
        model.reportedUserID = User.preview3.id   // picked...
        model.showReportSheet = false             // ...and dismissed without submitting

        model.beginReport()

        XCTAssertNil(
            model.reportedUserID,
            "a report reopened with somebody already selected from a previous sitting"
        )
    }

    /// And on a two-person plan, reopening still preselects — clearing must not break the case
    /// that has only one answer.
    @MainActor
    func testReopeningATwoPersonReportStillPreselects() {
        var pair = Request(
            creatorID: User.preview2.id,
            recipientIDs: [User.preview.id],
            category: .relationship,
            title: "Dinner?"
        )
        pair.status = .accepted
        let model = RequestDetailViewModel(request: pair)

        model.beginReport()
        model.showReportSheet = false
        model.beginReport()

        XCTAssertEqual(model.reportedUserID, User.preview2.id)
    }

    // MARK: - What a report will not accept

    /// A report has to name somebody who is actually on the plan. Without this check a stale or
    /// forged id would be filed against a person who was never here.
    @MainActor
    func testAReportAboutSomebodyNotOnThePlanIsRefused() async {
        let model = groupPlan()
        model.currentUser = .preview
        model.reportedUserID = "somebody-else-entirely"

        await model.submitReport()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.didSubmitReport)
    }

    @MainActor
    func testAReportWithNobodyChosenIsRefused() async {
        let model = groupPlan()
        model.currentUser = .preview
        model.reportedUserID = nil

        await model.submitReport()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.didSubmitReport)
    }

    @MainActor
    func testAValidReportIsFiledAndTheSheetCloses() async {
        let model = groupPlan()
        model.currentUser = .preview
        model.beginReport()
        model.reportedUserID = User.preview3.id
        model.reportNote = "  spam  "

        await model.submitReport()

        XCTAssertTrue(model.didSubmitReport)
        XCTAssertFalse(model.showReportSheet)
        XCTAssertNil(model.errorMessage)
        // Cleared afterwards, so the next report starts from nothing.
        XCTAssertNil(model.reportedUserID)
        XCTAssertTrue(model.reportNote.isEmpty)
        XCTAssertFalse(model.isSending, "the spinner was left running")
    }

    // MARK: - Disputes

    /// Only a plan the two of them remember differently can be disputed.
    @MainActor
    func testAnUndisputedPlanCannotBeDisputed() {
        let model = groupPlan()

        XCTAssertFalse(model.request.isDisputed)
        XCTAssertFalse(model.canDispute)
    }

    @MainActor
    func testADisputeCannotBeRaisedTwice() async {
        var contested = Request(
            creatorID: User.preview2.id,
            recipientIDs: [User.preview.id],
            category: .friends,
            title: "Coffee"
        )
        contested.status = .accepted
        contested.proposedTime = Date().addingTimeInterval(-86_400)
        contested.confirmations = [
            User.preview.id: .happened,
            User.preview2.id: .didNotHappen
        ]
        let model = RequestDetailViewModel(request: contested)
        model.currentUser = .preview
        XCTAssertTrue(model.canDispute, "the premise of this test no longer holds")

        await model.raiseDispute()

        XCTAssertTrue(model.didRaiseDispute)
        XCTAssertFalse(model.canDispute, "the same plan could be disputed a second time")
        XCTAssertFalse(model.showDisputeSheet)
    }
}
