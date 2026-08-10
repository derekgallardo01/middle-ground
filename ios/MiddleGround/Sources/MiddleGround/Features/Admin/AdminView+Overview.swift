import SwiftUI

/// The Overview section of the operator panel.
///
/// Split out of `AdminView.swift` for the 500-line limit, the same way the nearby search was split
/// out of `CreateRequestViewModel`. Nothing moved but the code.
extension AdminView {

    // MARK: - Overview

    var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("Users", "\(viewModel.overview.userCount)", "person.2", MGColors.indigo)
                metric("Groups", "\(viewModel.overview.relationshipCount)", "link", MGColors.teal)
                metric("Paired", viewModel.overview.pairedDisplay, "checkmark.circle", MGColors.teal)
                metric("Unpaired", "\(viewModel.overview.unpairedCount)", "clock", MGColors.sunshine)
                metric("Requests", "\(viewModel.overview.requestCount)", "bubble.left.and.bubble.right", MGColors.indigo)
                metric(
                    "Activated",
                    "\(Int(viewModel.overview.activationRate * 100))%",
                    "chart.line.uptrend.xyaxis",
                    MGColors.lavender
                )
                // Two different questions, and conflating them is what made the old figure
                // misleading: "did people get started" is not "did the groups they made fill up".
                metric(
                    "Active today",
                    viewModel.overview.dailyActiveDisplay,
                    "sun.max",
                    MGColors.sunshine
                )
                metric(
                    "Active this week",
                    viewModel.overview.weeklyActiveDisplay,
                    "calendar",
                    MGColors.indigo
                )
                metric(
                    "Groups paired",
                    "\(Int(viewModel.overview.groupPairingRate * 100))%",
                    "link.badge.plus",
                    MGColors.teal
                )
            }

            Text("Activated is the share of people in at least one paired group — with nobody to "
                 + "plan with, every screen is an empty state.")
                .mgFont(.caption, color: MGColors.warm600)

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
                    // Said plainly rather than left to be inferred from a bar that goes back up.
                    Text("Events, not people — one person can count more than once.")
                        .mgFont(.caption, color: MGColors.warm600)

                    let top = max(viewModel.overview.funnel.first?.count ?? 0, 1)
                    ForEach(viewModel.overview.funnel) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(step.label)
                                    .mgFont(.bodySmall, color: MGColors.warm600)
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

    func metric(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        adminCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(color)
                    Text(title)
                        .mgFont(.caption, color: MGColors.warm600)
                }
                Text(value).mgFont(.h1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
