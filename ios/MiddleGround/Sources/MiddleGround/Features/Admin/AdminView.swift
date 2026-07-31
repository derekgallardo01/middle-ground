import SwiftUI

/// Operator panel. Only rendered when the signed-in account carries the `admin` custom claim —
/// and every read behind it is independently enforced by `firestore.rules`, so forcing this view
/// open in a modified build shows nothing but permission errors.
struct AdminView: View {
    @State private var viewModel = AdminViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $viewModel.section) {
                    ForEach(AdminViewModel.Section.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .mgReadableWidth()
                .padding(.bottom, 8)
                .padding(.top, 4)

                content
            }
            .background(MGColors.sand.ignoresSafeArea())
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, prompt: "Search name or ID")
            .refreshable { await viewModel.load() }
            .navigationDestination(item: $viewModel.selectedUser) { user in
                AdminUserDetailView(user: user, viewModel: viewModel)
            }
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.section) { _, _ in
            Task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            Spacer()
            ProgressView()
            Spacer()
        } else if let errorMessage = viewModel.errorMessage {
            ScrollView {
                ErrorState(message: errorMessage) {
                    Task { await viewModel.load() }
                }
                .padding(16)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    switch viewModel.section {
                    case .overview: overviewSection
                    case .users: usersSection
                    case .requests: requestsSection
                    case .reports: reportsSection
                    case .events: eventsSection
                    case .audit: auditSection
                    }
                }
                .padding(.horizontal, 16)
                .mgReadableWidth()
                .padding(.bottom, 96)
            }
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("Users", "\(viewModel.overview.userCount)", "person.2", MGColors.indigo)
                metric("Groups", "\(viewModel.overview.relationshipCount)", "link", MGColors.teal)
                metric("Paired", viewModel.overview.pairedDisplay, "checkmark.circle", MGColors.teal)
                metric("Unpaired", "\(viewModel.overview.unpairedCount)", "clock", MGColors.sunshine)
                metric("Requests", "\(viewModel.overview.requestCount)", "bubble.left.and.bubble.right", MGColors.indigo)
                metric(
                    "Activation",
                    "\(Int(viewModel.overview.activationRate * 100))%",
                    "chart.line.uptrend.xyaxis",
                    MGColors.lavender
                )
            }

            funnelCard

            breakdown("Requests by status", viewModel.overview.requestsByStatus)
            breakdown("Requests by category", viewModel.overview.requestsByCategory)

            adminCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Events")
                        .mgFont(.h3)
                    row("Last 24 hours", "\(viewModel.overview.eventsLast24h)")
                    row("Last 7 days", "\(viewModel.overview.eventsLast7d)")
                }
            }
        }
    }

    /// Signup → activation, in order, so where people drop off is visible at a glance.
    ///
    /// The bar is drawn relative to the first step rather than to the largest, because the
    /// point is retention *through* the funnel — a later step can never legitimately exceed
    /// the first, and drawing relative to the max would hide that if it ever did.
    @ViewBuilder
    private var funnelCard: some View {
        if !viewModel.overview.funnel.isEmpty {
            adminCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Funnel").mgFont(.h3)

                    let top = max(viewModel.overview.funnel.first?.count ?? 0, 1)
                    ForEach(viewModel.overview.funnel) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(step.label)
                                    .mgFont(.bodySmall)
                                    .foregroundStyle(MGColors.warm600)
                                Spacer()
                                Text("\(step.count)").mgFont(.bodySmall).monospacedDigit()
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(MGColors.indigo.opacity(0.12))
                                    Capsule()
                                        .fill(MGColors.indigo)
                                        .frame(
                                            width: geo.size.width
                                                * min(1, Double(step.count) / Double(top))
                                        )
                                }
                            }
                            .frame(height: 6)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(step.label): \(step.count)")
                    }
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        adminCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(color)
                    Text(title)
                        .mgFont(.caption)
                        .foregroundStyle(MGColors.warm600)
                }
                Text(value).mgFont(.h1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func breakdown(_ title: String, _ values: [String: Int]) -> some View {
        if !values.isEmpty {
            adminCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).mgFont(.h3)
                    ForEach(values.sorted { $0.value > $1.value }, id: \.key) { key, value in
                        row(key.capitalized, "\(value)")
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).mgFont(.bodySmall).foregroundStyle(MGColors.warm600)
            Spacer()
            Text(value).mgFont(.bodySmall)
        }
    }

    // MARK: - Users

    private var usersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.filteredUsers.isEmpty {
                emptyNote("No users match.")
            }
            ForEach(viewModel.filteredUsers) { user in
                Button {
                    Task { await viewModel.openUser(user) }
                } label: {
                    adminCard {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name).mgFont(.body)
                                Text(user.id)
                                    .mgFont(.caption)
                                    .foregroundStyle(MGColors.warm600)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let stats = viewModel.statsByUser[user.id] {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("L\(stats.level)").mgFont(.caption)
                                    Text("\(stats.relationshipXP) XP")
                                        .mgFont(.caption)
                                        .foregroundStyle(MGColors.warm600)
                                }
                            }
                            Image(systemName: "chevron.right")
                                .foregroundStyle(MGColors.warm400)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Requests

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.filteredRequests.isEmpty {
                emptyNote("No requests match.")
            }
            ForEach(viewModel.filteredRequests) { request in
                adminCard {
                    AdminRequestRow(request: request)
                }
                .task { await viewModel.auditRequestView(request) }
            }
        }
    }

    // MARK: - Reports

    /// Abuse reports. The queue that makes the in-app Report button mean something — App Review
    /// guideline 1.2 asks for reports to be acted on, not merely collected.
    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reported content. Newest first — review within 24 hours.")
                .mgFont(.caption)
                .foregroundStyle(MGColors.warm600)

            if viewModel.reports.isEmpty {
                emptyNote("Nothing reported.")
            }
            ForEach(viewModel.reports) { report in
                adminCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(report.reason.displayName, systemImage: "flag.fill")
                                .mgFont(.bodySmall)
                                .foregroundStyle(MGColors.coral)
                            Spacer()
                            Text(report.at.formatted(date: .abbreviated, time: .shortened))
                                .mgFont(.caption)
                                .foregroundStyle(MGColors.warm600)
                        }
                        if let note = report.note, !note.isEmpty {
                            Text(note)
                                .mgFont(.bodySmall)
                                .foregroundStyle(MGColors.slate)
                        }
                        row("Reported user", report.reportedUserID)
                        row("Reported by", report.reporterID)
                        row("Request", report.requestID)
                    }
                }
            }
        }
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.events.isEmpty {
                emptyNote("No events recorded yet.")
            }
            ForEach(viewModel.events) { event in
                adminCard {
                    HStack(spacing: 12) {
                        Image(systemName: event.type.iconName)
                            .foregroundStyle(MGColors.indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.type.displayName).mgFont(.bodySmall)
                            Text(event.userID)
                                .mgFont(.caption)
                                .foregroundStyle(MGColors.warm600)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(event.at.formatted(date: .abbreviated, time: .shortened))
                            .mgFont(.caption)
                            .foregroundStyle(MGColors.warm600)
                    }
                }
            }
        }
    }

    // MARK: - Audit

    private var auditSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Every admin view of user data is recorded here. Entries cannot be edited or deleted.")
                .mgFont(.caption)
                .foregroundStyle(MGColors.warm600)

            if viewModel.auditEntries.isEmpty {
                emptyNote("No admin access recorded yet.")
            }
            ForEach(viewModel.auditEntries) { entry in
                adminCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(entry.action) · \(entry.targetType)").mgFont(.bodySmall)
                        Text(entry.targetID)
                            .mgFont(.caption)
                            .foregroundStyle(MGColors.warm600)
                            .lineLimit(1)
                        Text(entry.at.formatted(date: .abbreviated, time: .shortened))
                            .mgFont(.caption)
                            .foregroundStyle(MGColors.warm600)
                    }
                }
            }
        }
    }

    // MARK: - Shared

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .mgFont(.bodySmall)
            .foregroundStyle(MGColors.warm600)
            .padding(.vertical, 8)
    }

    private func adminCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MGColors.surface)
            .mgCard(radius: MGRadius.md)
    }
}

/// One request, with its full content — this is the part that requires the policy disclosure.
struct AdminRequestRow: View {
    let request: Request

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(request.title).mgFont(.body)
                Spacer()
                StatusBadge(status: request.status)
            }
            if let details = request.details, !details.isEmpty {
                Text(details)
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)
            }
            Text("\(request.category.displayName) · \(request.negotiationChain.count) message(s)")
                .mgFont(.caption)
                .foregroundStyle(MGColors.warm600)
            Text(request.id)
                .mgFont(.caption)
                .foregroundStyle(MGColors.warm400)
                .lineLimit(1)
        }
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    return AdminView()
}
