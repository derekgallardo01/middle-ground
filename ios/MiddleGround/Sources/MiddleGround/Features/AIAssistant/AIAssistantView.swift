import SwiftUI

struct AIAssistantView: View {
    @State private var viewModel = AIAssistantViewModel()
    @State private var selectedTemplate: RequestTemplate?
    @State private var showCreateRequest = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    suggestionsList
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(MGColors.sand.ignoresSafeArea())
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedTemplate) { template in
                CreateRequestView(
                    initialCategory: template.category,
                    initialTitle: template.title,
                    initialDetails: template.details ?? ""
                )
            }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(MGColors.lavender.opacity(0.2))
                        .frame(width: 56, height: 56)
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundStyle(MGColors.lavender)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Need a hand?")
                        .font(MGFonts.h2)
                    Text("I can suggest ideas based on your calendar and habits.")
                        .font(MGFonts.bodySmall)
                        .foregroundStyle(MGColors.warm600)
                }
            }
        }
        .padding(20)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: MGColors.slate.opacity(0.05), radius: 12, x: 0, y: 4)
    }
    
    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggestions")
                .font(MGFonts.h2)
            
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(viewModel.suggestions) { suggestion in
                    SuggestionCard(suggestion: suggestion) {
                        selectedTemplate = suggestion.requestTemplate
                        Haptics.shared.impact(.light)
                    }
                }
            }
        }
    }
}

struct SuggestionCard: View {
    let suggestion: AISuggestion
    let onAction: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(suggestion.title)
                    .font(MGFonts.h3)
                Spacer()
                Image(systemName: "sparkles")
                    .foregroundStyle(MGColors.lavender)
            }
            
            Text(suggestion.message)
                .font(MGFonts.body)
                .foregroundStyle(MGColors.warm600)
            
            Button(action: onAction) {
                Text(suggestion.action)
                    .font(MGFonts.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(MGColors.indigo)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(MGColors.indigo.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(16)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: MGColors.slate.opacity(0.05), radius: 10, x: 0, y: 3)
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    return AIAssistantView()
}
