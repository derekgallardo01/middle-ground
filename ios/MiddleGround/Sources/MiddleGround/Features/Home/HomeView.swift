import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var selectedRequest: Request?
    @State private var showCreateRequest = false
    @State private var showSpontaneous = false
    @Namespace private var animationNamespace

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var fabSize: CGFloat = 60

    var body: some View {
        NavigationStack {
            ZStack {
                MGColors.sand.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 20) {
                        header
                        statsRow
                        feedSection
                    }
                    .padding(.horizontal, 16)
                .mgReadableWidth()
                    .padding(.top, 12)
                    // Clear the tab bar and the floating action button, which previously
                    // covered the last card in the feed.
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await viewModel.loadRequests()
                }

                floatingButton

                if viewModel.showCelebration {
                    CelebrationView(
                        title: viewModel.celebrationTitle,
                        subtitle: "Great job working together."
                    ) {
                        viewModel.showCelebration = false
                    }
                }
            }
            .navigationTitle("Middle Ground")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $selectedRequest) { request in
                RequestDetailView(request: request, namespace: animationNamespace)
            }
            .sheet(isPresented: $showCreateRequest) {
                CreateRequestView { _ in
                    Task { await viewModel.loadRequests() }
                }
            }
            .sheet(isPresented: $showSpontaneous) {
                SpontaneousRequestView { _ in
                    Task { await viewModel.loadRequests() }
                }
            }
        }
        .task {
            // Fast first paint from cache, then stay subscribed to live updates.
            await viewModel.loadRequests()
            await viewModel.observeRequests()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveRequestNotification)) { notification in
            if let requestID = notification.userInfo?["request_id"] as? String,
               let request = viewModel.requests.first(where: { $0.id == requestID }) {
                if !reduceMotion {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        selectedRequest = request
                    }
                } else {
                    selectedRequest = request
                }
            }
        }
    }

    private var floatingButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Menu {
                    Button {
                        showCreateRequest = true
                        Haptics.shared.impact(.medium)
                    } label: {
                        Label("New Request", systemImage: "plus")
                    }

                    Button {
                        showSpontaneous = true
                        Haptics.shared.impact(.medium)
                    } label: {
                        Label("Spontaneous", systemImage: "bolt.fill")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(MGColors.onAccent)
                        .frame(width: fabSize, height: fabSize)
                        .background(MGColors.indigo)
                        .clipShape(Circle())
                        .mgShadow(MGShadow.glow(MGColors.indigo))
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel("Create new request or spontaneous invite")
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hello, \(viewModel.currentUser?.name ?? "there")")
                .mgFont(.h1)
            Text(activeRequestsSummary)
                .mgFont(.body)
                .foregroundStyle(MGColors.warm600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pluralises correctly, and reads as a sentence when there is nothing pending.
    private var activeRequestsSummary: String {
        let count = viewModel.requests.filter(\.isPending).count
        switch count {
        case 0: return "Nothing waiting on you"
        case 1: return "You have 1 active request"
        default: return "You have \(count) active requests"
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            GamificationCard(
                title: "Daily Streak",
                value: "\(viewModel.stats.streakDays)",
                subtitle: viewModel.stats.streakDays == 1 ? "day" : "days",
                icon: "flame.fill",
                color: MGColors.coral
            )
            GamificationCard(
                title: "Growth Score",
                value: "\(viewModel.stats.growthScore)",
                subtitle: viewModel.stats.growthScore > 0 ? "Great job!" : "Just getting started",
                icon: "chart.line.uptrend.xyaxis",
                color: MGColors.indigo
            )
        }
    }

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Requests")
                .mgFont(.h2)

            if viewModel.isLoading && viewModel.requests.isEmpty {
                LoadingSkeleton(type: .list)
            } else if let errorMessage = viewModel.errorMessage, viewModel.requests.isEmpty {
                // Only take over the feed when there is nothing to show. A failed *response*
                // used to wipe a perfectly good list.
                ErrorState(message: errorMessage) {
                    Task { await viewModel.loadRequests() }
                }
            } else if viewModel.requests.isEmpty {
                ContentUnavailableView {
                    Label("No requests yet", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Create your first request to get started.")
                }
                .background(MGColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(viewModel.requests) { request in
                    Button {
                        if !reduceMotion {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                selectedRequest = request
                            }
                        } else {
                            selectedRequest = request
                        }
                        Haptics.shared.impact(.light)
                    } label: {
                        // A nil closure hides the response buttons. Previously this was always
                        // non-nil, so a creator saw Accept/Decline on their own request.
                        RequestCard(
                            request: request,
                            onRespond: viewModel.canRespond(to: request)
                                ? { response in viewModel.respond(to: request, with: response) }
                                : nil
                        )
                        .matchedGeometryEffect(id: "card_\(request.id)", in: animationNamespace, properties: .frame, anchor: .topLeading)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Request: \(request.title), status \(request.status.displayName)")
                    .accessibilityHint("Double tap to open details")
                    .scrollTransition { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.6)
                            .scaleEffect(phase.isIdentity ? 1 : 0.95)
                    }
                }
            }
        }
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    return HomeView()
}
