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

    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case users = "Users"
        case requests = "Requests"
        case reports = "Reports"
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
    var auditEntries: [AdminAuditEntry] = []
    var reports: [ContentReport] = []
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
            case .outcomes:
                outcomes = try await planOutcomeRepository.recentOutcomes(limit: 500)
                outcomeSummary = OutcomeSummary.from(outcomes)
            case .events:
                events = try await eventRepository.recentEvents(limit: 200)
            case .venues:
                venues = try await venueRepository.venues()
            case .audit:
                auditEntries = try await eventRepository.recentAudit(limit: 200)
            }
        } catch {
            // The most likely cause by far is a missing admin claim, so say that rather than
            // showing a raw Firestore permission error.
            errorMessage = "Couldn't load. This account may not have admin access.\n\n\(error.localizedDescription)"
        }
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
    var requestCount = 0
    var requestsByStatus: [String: Int] = [:]
    var requestsByCategory: [String: Int] = [:]
    var eventsLast24h = 0
    var eventsLast7d = 0

    /// Ordered funnel steps. Empty until the Overview section loads.
    ///
    /// A struct rather than a tuple: `AdminOverview` is Equatable, and Swift cannot synthesise
    /// that for an array of tuples.
    var funnel: [FunnelStep] = []

    var unpairedCount: Int { max(0, relationshipCount - pairedCount) }

    var pairedDisplay: String { pairedCountIsExact ? "\(pairedCount)" : "\(pairedCount)+" }

    /// One step of the signup → activation funnel.
    struct FunnelStep: Equatable, Sendable, Identifiable {
        let label: String
        let count: Int
        var id: String { label }
    }

    var activationRate: Double {
        guard relationshipCount > 0 else { return 0 }
        return Double(pairedCount) / Double(relationshipCount)
    }
}
