import SwiftUI

struct SpontaneousRequestView: View {
    @State private var viewModel = SpontaneousRequestViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onCreated: ((Request) -> Void)?

    let quickIdeas = [
        "I'm grabbing tacos in 20 minutes. Who's in?",
        "Drinks in 30?",
        "Movie night tonight?",
        "Park walk in 15?",
        "Game night at 8?"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(MGColors.sunshine.opacity(0.2))
                            .frame(width: 80, height: 80)
                        Text("⚡")
                            .font(.system(size: 40))
                    }

                    Text("Spontaneous Mode")
                        .mgFont(.h1)
                    Text("One tap. Quick decisions. No overthinking.")
                        .mgFont(.body)
                        .foregroundStyle(MGColors.warm600)
                        .multilineTextAlignment(.center)
                }

                TextField("What are you doing?", text: $viewModel.title, axis: .vertical)
                    .mgFont(.h2)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(MGColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick ideas")
                        .mgFont(.h3)

                    FlowLayout(spacing: 8) {
                        ForEach(quickIdeas, id: \.self) { idea in
                            Button {
                                if !reduceMotion {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        viewModel.title = idea
                                    }
                                } else {
                                    viewModel.title = idea
                                }
                                Haptics.shared.impact(.light)
                            } label: {
                                Text(idea)
                                    .mgFont(.bodySmall)
                                    .foregroundStyle(MGColors.slate)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(MGColors.warm100)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .accessibilityLabel("Use idea: \(idea)")
                        }
                    }
                }

                HStack {
                    Text("Expires in")
                        .mgFont(.body)
                    Spacer()
                    Picker("Expires in", selection: $viewModel.expiresInMinutes) {
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                .padding()
                .background(MGColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                recipientSection

                Spacer()

                PrimaryButton(title: "Send Now", systemImage: "paperplane.fill") {
                    Task {
                        if let request = await viewModel.sendRequest() {
                            onCreated?(request)
                            dismiss()
                        }
                    }
                }
                .disabled(!viewModel.canSubmit || viewModel.isLoading)
                .accessibilityLabel("Send spontaneous request")
            }
            .padding()
            .background(MGColors.sand.ignoresSafeArea())
            .navigationTitle("Spontaneous")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(MGColors.slate)
                        .accessibilityLabel("Cancel spontaneous request")
                }
            }
            // This view had no alert at all, so both failures the view model can produce —
            // "Couldn't load partners." and "Failed to send spontaneous request." — were set
            // and never rendered. Send Now simply did nothing: the sheet stayed open, the
            // error haptic fired, and nothing explained why.
            .alert("Oops", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task {
            await viewModel.loadCurrentUserAndPartners()
        }
    }

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who's in?")
                .mgFont(.h3)

            if viewModel.isLoadingPartners {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if viewModel.relationships.isEmpty || viewModel.needsPartner {
                // Without this an unpaired owner got a one-segment picker tagged "" and a
                // permanently disabled Send Now, with nothing explaining why. The prompt now
                // also offers the share sheet, rather than naming a tab it cannot open.
                InvitePrompt(code: viewModel.inviteCode, compact: true)
            } else {
                Picker("Recipient", selection: $viewModel.recipientID) {
                    ForEach(viewModel.relationships) { relationship in
                        Text(viewModel.label(for: relationship))
                            .tag(partnerID(from: relationship) ?? "")
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding()
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func partnerID(from relationship: Relationship) -> String? {
        guard let currentUserID = viewModel.currentUser?.id else { return nil }
        return relationship.participantIDs.first { $0 != currentUserID }
    }
}

// Simple flow layout helper
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
                self.size.width = max(self.size.width, x)
            }
            self.size.height = y + lineHeight
        }
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    return SpontaneousRequestView()
}
