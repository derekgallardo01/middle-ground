import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var selectedRequest: Request?
    @State private var showCreateRequest = false
    @State private var showSpontaneous = false
    @Namespace private var animationNamespace
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
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
                    .padding(.vertical, 12)
                }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "bell")
                            .foregroundStyle(MGColors.slate)
                    }
                    .accessibilityLabel("Notifications")
                }
            }
            .navigationDestination(item: $selectedRequest) { request in
                RequestDetailView(request: request, namespace: animationNamespace)
            }
            .sheet(isPresented: $showCreateRequest) {
                CreateRequestView { request in
                    Task { await viewModel.loadRequests() }
                }
            }
            .sheet(isPresented: $showSpontaneous) {
                SpontaneousRequestView { request in
                    Task { await viewModel.loadRequests() }
                }
            }
        }
        .task {
            await viewModel.loadRequests()
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
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(MGColors.indigo)
                        .clipShape(Circle())
                        .shadow(color: MGColors.indigo.opacity(0.3), radius: 16, x: 0, y: 8)
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
                .font(MGFonts.h1)
            Text("You have \(viewModel.requests.filter(\.isPending).count) active requests")
                .font(MGFonts.body)
                .foregroundStyle(MGColors.warm600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var statsRow: some View {
        HStack(spacing: 12) {
            GamificationCard(title: "Daily Streak", value: "🔥 \(viewModel.stats.streakDays)", subtitle: "days", icon: "flame.fill", color: MGColors.coral)
            GamificationCard(title: "Growth Score", value: "\(viewModel.stats.growthScore)", subtitle: "Great job!", icon: "chart.line.uptrend.xyaxis", color: MGColors.indigo)
        }
    }
    
    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Requests")
                .font(MGFonts.h2)
            
            if viewModel.isLoading && viewModel.requests.isEmpty {
                LoadingSkeleton(type: .list)
            } else if let errorMessage = viewModel.errorMessage {
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
                        RequestCard(request: request) { response in
                            viewModel.respond(to: request, with: response)
                        }
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
