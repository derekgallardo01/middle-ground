import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var selectedRequest: Request?
    @State private var showCreateRequest = false
    @State private var showSpontaneous = false

    /// Set when the feed's Negotiate button opened the detail screen, so it can open straight
    /// into the composer. Cleared on every other navigation.
    @State private var composingRequestID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    @ScaledMetric(relativeTo: .title) private var fabSize: CGFloat = 60

    var body: some View {
        NavigationStack {
            ZStack {
                MGColors.sand.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 20) {
                        // A placeholder rather than a default while the first load is in flight.
                        // This renders "Hello, there" before the user arrives, so the screen
                        // visibly rewrites itself a beat after opening.
                        header
                            .redacted(reason: viewModel.hasLoaded ? [] : .placeholder)
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
                RequestDetailView(request: request, startComposing: composingRequestID == request.id)
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
            // The single entry point for this screen's data.
            //
            // `loadRelationshipState` and `observeRequests` are concurrent because neither needs
            // the other, and `observeRequests` yields the current requests before it yields any
            // update — so the separate `loadRequests()` that used to run first was fetching data
            // the listener was about to deliver anyway.
            async let name: Void = viewModel.loadCurrentUser()
            async let relationship: Void = viewModel.loadRelationshipState()
            async let requests: Void = viewModel.observeRequests()
            _ = await (name, relationship, requests)
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveRequestNotification)) { notification in
            guard let requestID = notification.userInfo?["request_id"] as? String else { return }
            // Switching tabs is not optional: this handler lives on Home, so without it a tap
            // from Calendar or Profile pushed the detail onto a stack the user cannot see and
            // the notification appeared to do nothing.
            appState.selectedTab = .home
            appState.pendingRequestID = requestID
            openPendingRequestIfPossible()
        }
        // The feed usually has not loaded when a cold-launch push arrives, so resolution is
        // retried every time the requests change rather than attempted once and abandoned.
        .onChange(of: viewModel.requests) { _, _ in
            openPendingRequestIfPossible()
        }
    }

    private func openPendingRequestIfPossible() {
        guard let id = appState.pendingRequestID,
              let request = viewModel.requests.first(where: { $0.id == id }) else { return }
        appState.pendingRequestID = nil
        if reduceMotion {
            selectedRequest = request
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedRequest = request
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

    /// Pluralises correctly, and now counts the same thing the sentence claims to.
    ///
    /// "Nothing waiting on you" and "You have N active requests" were two different measures
    /// sharing one counter — the first is about your turn, the second about the feed. Both now
    /// report your turn, which is the only one the user can act on.
    private var activeRequestsSummary: String {
        switch viewModel.awaitingYouCount {
        case 0: return "Nothing waiting on you"
        case 1: return "1 request is waiting on you"
        case let count: return "\(count) requests are waiting on you"
        }
    }

    /// A menu rather than a segmented control: the feed is already busy, and this is a thing you
    /// reach for occasionally rather than a mode you sit in.
    private var filterMenu: some View {
        Menu {
            Picker("Show", selection: $viewModel.filter) {
                ForEach(HomeViewModel.Filter.allCases) { option in
                    if option == .saved, viewModel.savedCount > 0 {
                        Text("\(option.rawValue) (\(viewModel.savedCount))").tag(option)
                    } else {
                        Text(option.rawValue).tag(option)
                    }
                }
            }
        } label: {
            Label(viewModel.filter.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.indigo)
        }
        .accessibilityLabel("Filter requests, currently \(viewModel.filter.rawValue)")
    }

    private func open(_ request: Request) {
        if reduceMotion {
            selectedRequest = request
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedRequest = request
            }
        }
        Haptics.shared.impact(.light)
    }

    /// Negotiate opens the request instead of answering it.
    ///
    /// From the feed it used to send `.negotiate` with no text — a bubble reading "🤝 Negotiate"
    /// and nothing else. Worse, responding hands the turn over, so the composer the user needed
    /// was gone by the time they arrived: they could ask to negotiate but never say what they
    /// wanted. Accept and Decline are complete actions on their own and still send from here.
    private func respond(to request: Request, with response: ResponseType) {
        guard response == .negotiate else {
            viewModel.respond(to: request, with: response)
            return
        }
        composingRequestID = request.id
        open(request)
    }

    // The Daily Streak and Growth Score cards used to sit here, between the greeting and the
    // feed. Neither was actionable, and together they pushed the requests — the only thing on
    // this screen anyone can act on — most of a card further down. Both still live on the
    // Activities tab, where they are now tappable and explain how they were calculated.

    /// Two genuinely different empty states, because there are two genuinely different reasons
    /// the feed is empty — and only one of them is solved by writing a request.
    ///
    /// Before this, an unpaired user was told "Create your first request to get started",
    /// tapped the compose button, and landed on a sheet explaining they could not. This is the
    /// first screen after onboarding, and it pointed the wrong way.
    @ViewBuilder
    private var emptyFeed: some View {
        if viewModel.isPaired {
            ContentUnavailableView {
                Label("No requests yet", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Send one to get the conversation started.")
            }
            .background(MGColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous))
        } else {
            InvitePrompt(code: viewModel.inviteCode) {
                appState.selectedTab = .profile
            }
            .background(MGColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous))
        }
    }

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Requests")
                    .mgFont(.h2)
                Spacer()
                if viewModel.showsFilter { filterMenu }
            }

            // Gated on having loaded, not on `isLoading`. `isLoading` is false before the first
            // load starts, so the feed fell through to the empty state on the opening frame and
            // showed the invite prompt to people who are already paired.
            if !viewModel.hasLoaded && viewModel.requests.isEmpty {
                LoadingSkeleton(type: .list)
            } else if let errorMessage = viewModel.errorMessage, viewModel.requests.isEmpty {
                // Only take over the feed when there is nothing to show. A failed *response*
                // used to wipe a perfectly good list.
                ErrorState(message: errorMessage) {
                    Task { await viewModel.loadRequests() }
                }
            } else if viewModel.requests.isEmpty {
                emptyFeed
            } else if viewModel.visibleRequests.isEmpty {
                // The feed has requests, just none matching the filter — saying "no requests
                // yet" here would be a lie, and offering the invite prompt would be nonsense.
                ContentUnavailableView {
                    Label(
                        viewModel.filter == .saved ? "Nothing saved" : "Nothing on your turn",
                        systemImage: viewModel.filter == .saved ? "heart" : "checkmark.circle"
                    )
                } description: {
                    Text(viewModel.filter == .saved
                         ? "Requests you set aside for later show up here."
                         : "You're all caught up.")
                }
                .background(MGColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous))
            } else {
                ForEach(viewModel.visibleRequests) { request in
                    Button {
                        composingRequestID = nil
                        open(request)
                    } label: {
                        // A nil closure hides the response buttons. Previously this was always
                        // non-nil, so a creator saw Accept/Decline on their own request.
                        RequestCard(
                            request: request,
                            onRespond: viewModel.canRespond(to: request)
                                ? { response in respond(to: request, with: response) }
                                : nil,
                            isResponding: viewModel.isResponding(to: request)
                        )
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
