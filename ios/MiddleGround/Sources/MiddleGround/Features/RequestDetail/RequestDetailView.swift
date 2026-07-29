import SwiftUI

struct RequestDetailView: View {
    @State private var viewModel: RequestDetailViewModel
    @Environment(\.dismiss) private var dismiss
    var namespace: Namespace.ID
    
    init(request: Request, namespace: Namespace.ID) {
        _viewModel = State(wrappedValue: RequestDetailViewModel(request: request))
        self.namespace = namespace
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                
                if viewModel.request.isPending {
                    quickResponseRow
                }
                
                NegotiationView(viewModel: viewModel)
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(MGColors.sand.ignoresSafeArea())
        .navigationTitle(viewModel.request.category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.saveForLater() }
                } label: {
                    Image(systemName: viewModel.request.status == .saved ? "heart.fill" : "heart")
                        .foregroundStyle(MGColors.coral)
                }
                .accessibilityLabel(viewModel.request.status == .saved ? "Saved for later" : "Save for later")
            }
        }
        .alert("Oops", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: viewModel.request.category.iconName)
                    .foregroundStyle(MGColors.indigo)
                Spacer()
                StatusBadge(status: viewModel.request.status)
            }
            
            Text(viewModel.request.title)
                .font(MGFonts.h1)
            
            if let details = viewModel.request.details, !details.isEmpty {
                Text(details)
                    .font(MGFonts.body)
                    .foregroundStyle(MGColors.warm600)
            }
            
            if let time = viewModel.request.proposedTime {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(time, style: .date)
                        .font(MGFonts.bodySmall)
                }
                .foregroundStyle(MGColors.warm600)
            }
        }
        .padding(20)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: MGColors.slate.opacity(0.05), radius: 12, x: 0, y: 4)
        .matchedGeometryEffect(id: "card_\(viewModel.request.id)", in: namespace, properties: .frame, anchor: .topLeading, isSource: false)
    }
    
    private var quickResponseRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Respond")
                .font(MGFonts.h3)
            
            HStack(spacing: 10) {
                ResponseButton(type: .accept) {
                    Task { await viewModel.respond(with: .accept) }
                }
                ResponseButton(type: .negotiate) {
                    Task { await viewModel.respond(with: .negotiate) }
                }
                ResponseButton(type: .decline) {
                    Task { await viewModel.respond(with: .decline) }
                }
            }
        }
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    @Previewable @Namespace var namespace
    return NavigationStack {
        RequestDetailView(request: .previewNegotiating, namespace: namespace)
    }
}
