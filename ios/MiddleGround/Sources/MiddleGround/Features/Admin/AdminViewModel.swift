import Factory
import Foundation

/// Backs the admin panel.
///
/// Every read here is additionally gated by `isAdmin()` in `firestore.rules`, so this view model
/// cannot grant access the backend would refuse — if the claim is missing, these calls fail.
///
/// Viewing an individual user's data writes an audit entry. That is deliberate and must not be
/// made conditional: an audit trail with exceptions is not an audit trail.
@MainActor
@Observable
final class AdminViewModel {
    private let userRepository = Container.shared.userRepository()
    private let requestRepository = Container.shared.requestRepository()
    private let relationshipRepository = Container.shared.relationshipRepository()
    private let eventRepository = Container.shared.eventRepository()
    private let gamificationRepository = Container.shared.gamificationRepository()
    private let authService = Container.shared.authService()
    private let adminRepository = Container.shared.adminRepository()
    private let venueRepository = Container.shared.venueRepository()
    private let planOutcomeRepository = Container.shared.planOutcomeRepository()
    private let disputeRepository = Container.shared.disputeRepository()

    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case users = "Users"
        case requests = "Requests"
        case reports = "Reports"
        case disputes = "Disputes"
        case outcomes = "Outcomes"
        case events = "Events"
        case venues = "Venues"
        case audit = "Audit"

        var id: String { rawValue }
    }

    var section: Section = .overview
    var isLoading = false
    var errorMessage: String?
    var searchText = ""

    // Overview
    var overview = AdminOverview()

    // Collections
    var users: [User] = []
    var requests: [Request] = []
    var events: [AnalyticsEvent] = []
    /// Whose invites brought somebody in — derived from `events`, so it costs no extra read.
    var referrals = ReferralSummary(inviters: [], unattributed: 0)
    var auditEntries: [AdminAuditEntry] = []
    var reports: [ContentReport] = []
    var disputes: [PlanDispute] = []
    var venues: [Venue] = []
    /// The follow-through record, and what it adds up to. Collection began 2 August 2026 — there
    /// is no history before that and it cannot be reconstructed.
    var outcomes: [PlanOutcome] = []
    var outcomeSummary = OutcomeSummary(
        agreed: 0, attended: 0, cancelledEarly: 0, cancelledLate: 0, noShowed: 0, disputed: 0
    )
    var statsByUser: [String: GamificationStats] = [:]

    // Detail
    var selectedUser: User?
    var selectedUserRequests: [Request] = []
    var selectedUserEvents: [AnalyticsEvent] = []

    var filteredUsers: [User] {
        guard !searchText.isEmpty else { return users }
        let query = searchText.lowercased()
        return users.filter {
            $0.name.lowercased().contains(query) || $0.id.lowercased().contains(query)
        }
    }

    var filteredRequests: [Request] {
        guard !searchText.isEmpty else { return requests }
        let query = searchText.lowercased()
        return requests.filter {
            $0.title.lowercased().contains(query) || $0.id.lowercased().contains(query)
        }
    }

    /// Records what was decided about a report.
    ///
    /// The queue quoted a 24-hour review promise over a list nothing could be marked done on, so
    /// a hundred unread reports and a hundred handled ones looked identical. Optimistic, then
    /// reloaded: the rules are the enforcement, and a refused write must not leave the screen
    /// claiming otherwise.
    /// Records what was decided about a contested plan. Same shape as resolving a report, and
    /// deliberately a different queue — see `PlanDispute`.
    func resolve(_ dispute: PlanDispute, as resolution: ReportResolution) async {
        guard let adminID = authService.currentUserID else { return }
        do {
            try await disputeRepository.resolveDispute(id: dispute.id, as: resolution, by: adminID)
            disputes = try await disputeRepository.recentDisputes(limit: 200)
        } catch {
            errorMessage = "Couldn't record that: \(error.localizedDescription)"
        }
    }

    func resolve(_ report: ContentReport, as resolution: ReportResolution) async {
        guard let adminID = authService.currentUserID else { return }
        do {
            try await eventRepository.resolveReport(id: report.id, as: resolution, by: adminID)
            reports = try await eventRepository.recentReports(limit: 200)
        } catch {
            errorMessage = "Couldn't record that: \(error.localizedDescription)"
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            switch section {
            case .overview:
                overview = try await adminRepository.overview()
            case .users:
                users = try await adminRepository.allUsers(limit: 200)
                statsByUser = (try? await gamificationRepository.allStats(limit: 200)) ?? [:]
            case .requests:
                requests = try await adminRepository.allRequests(limit: 200)
            case .reports:
                reports = try await eventRepository.recentReports(limit: 200)
            case .disputes:
                disputes = try await disputeRepository.recentDisputes(limit: 200)
            case .outcomes:
                outcomes = try await planOutcomeRepository.recentOutcomes(limit: 500)
                outcomeSummary = OutcomeSummary.from(outcomes)
            case .events:
                events = try await eventRepository.recentEvents(limit: 200)
                // Free: the referral picture is folded out of the events already in hand. The
                // `invitedBy` edge has been written on every group join since pairing shipped and
                // read by nothing until now.
                referrals = ReferralSummary.from(events: events)
            case .venues:
                venues = try await venueRepository.venues()
            case .audit:
                auditEntries = try await eventRepository.recentAudit(limit: 200)
            }
        } catch {
            errorMessage = Self.loadFailureMessage(for: error)
        }
    }

    /// What to say when a section fails to load.
    ///
    /// This used to say "This account may not have admin access" for *every* failure, on the
    /// reasoning that a missing claim was the likeliest cause. It was a confident diagnosis with
    /// nothing behind it, and the first time it was wrong it cost real time: the overview was
    /// failing because a query wanted a composite index nobody had deployed, and the screen
    /// spent that whole time insisting the signed-in admin was not an admin.
    ///
    /// Only permission-denied gets the access sentence now, because only permission-denied is
    /// evidence of it. Everything else defers to `UserFacingError`, which says what it knows and
    /// no more. The underlying description stays appended either way — this panel is for people
    /// who can act on it.
    static func loadFailureMessage(for error: Error) -> String {
        let nsError = error as NSError
        let isPermissionDenied = nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7
        let lead = isPermissionDenied
            ? "Couldn't load. This account may not have admin access."
            : UserFacingError.message(for: error) ?? "Couldn't load."
        return "\(lead)\n\n\(error.localizedDescription)"
    }

    // MARK: - Curating the venue list
    //
    // Deliberately not audited, unlike opening a user's record. The audit trail exists because
    // reading someone's private data is a thing that should leave a mark; editing a list of
    // restaurants is not, and burying real access records under routine edits would make the
    // trail harder to read for the one thing it is for.

    func saveVenue(_ venue: Venue) async {
        do {
            try await venueRepository.save(venue)
            venues = try await venueRepository.venues()
        } catch {
            errorMessage = "Couldn't save that venue.\n\n\(error.localizedDescription)"
        }
    }

    func deleteVenue(_ venue: Venue) async {
        do {
            try await venueRepository.delete(id: venue.id)
            venues.removeAll { $0.id == venue.id }
        } catch {
            errorMessage = "Couldn't remove that venue.\n\n\(error.localizedDescription)"
        }
    }

    /// Opens one user's full record — and records that it happened.
    func openUser(_ user: User) async {
        selectedUser = user
        selectedUserRequests = []
        selectedUserEvents = []

        await recordAudit(action: "viewed_user", targetType: "user", targetID: user.id)

        selectedUserRequests = (try? await adminRepository.requests(forUser: user.id, limit: 100)) ?? []
        selectedUserEvents = (try? await eventRepository.events(forUser: user.id, limit: 100)) ?? []
    }

    func auditRequestView(_ request: Request) async {
        await recordAudit(action: "viewed_request", targetType: "request", targetID: request.id)
    }

    private func recordAudit(action: String, targetType: String, targetID: String) async {
        guard let admin = await authService.currentUser() else { return }
        await eventRepository.recordAudit(
            AdminAuditEntry(
                adminID: admin.id,
                action: action,
                targetType: targetType,
                targetID: targetID
            )
        )
    }
}

/// Aggregate counts for the Overview section. Computed with Firestore aggregation queries, so
/// no user documents are read to produce them.
struct AdminOverview: Equatable, Sendable {
    var userCount = 0
    var relationshipCount = 0
    var pairedCount = 0
    /// False when `pairedCount` hit the paging ceiling — the UI shows "N+" rather than a
    /// confidently wrong figure. See `FirestoreAdminRepository.countPairedRelationships`.
    var pairedCountIsExact = true
    /// People in at least one paired group — the numerator activation should always have had.
    var activatedUserCount = 0
    var requestCount = 0
    var requestsByStatus: [String: Int] = [:]
    var requestsByCategory: [String: Int] = [:]
    var eventsLast24h = 0
    var eventsLast7d = 0
    /// Distinct people who opened the app in the last day and week.
    ///
    /// `app_opened` was collected from the start and aggregated nowhere; the nearest number was
    /// "events in 24h", which sums every type and is dominated by this one.
    var dailyActiveUsers = 0
    var weeklyActiveUsers = 0
    /// False when the read hit its ceiling, so the UI can say "N+" rather than a low number it
    /// cannot support.
    var activeUserCountsAreExact = true

    /// Ordered funnel steps. Empty until the Overview section loads.
    ///
    /// A struct rather than a tuple: `AdminOverview` is Equatable, and Swift cannot synthesise
    /// that for an array of tuples.
    var funnel: [FunnelStep] = []

    var unpairedCount: Int { max(0, relationshipCount - pairedCount) }

    var pairedDisplay: String { pairedCountIsExact ? "\(pairedCount)" : "\(pairedCount)+" }

    var dailyActiveDisplay: String {
        activeUserCountsAreExact ? "\(dailyActiveUsers)" : "\(dailyActiveUsers)+"
    }

    var weeklyActiveDisplay: String {
        activeUserCountsAreExact ? "\(weeklyActiveUsers)" : "\(weeklyActiveUsers)+"
    }

    /// One step of the signup → activation funnel.
    struct FunnelStep: Equatable, Sendable, Identifiable {
        let label: String
        let count: Int
        var id: String { label }
    }

    /// The share of **people** who got to a working state.
    ///
    /// Was paired groups over all groups, which is a fact about groups. Somebody who made three
    /// groups and paired none counted against it three times; somebody who paired on their first
    /// try counted once. Since the denominator was never people, the number was never about them
    /// — and it is the one figure that answers whether the product works at all.
    ///
    /// A person is activated when any group they are in has somebody else in it. Nothing else in
    /// the app is usable until then: with nobody to plan with, every screen is an empty state.
    var activationRate: Double {
        guard userCount > 0 else { return 0 }
        return Double(activatedUserCount) / Double(userCount)
    }

    /// The old figure, kept because it answers a different and still useful question: of the
    /// groups people made, how many found a second person. A group abandoned before anybody
    /// joined is a different problem from a person who never got started.
    var groupPairingRate: Double {
        guard relationshipCount > 0 else { return 0 }
        return Double(pairedCount) / Double(relationshipCount)
    }
}
