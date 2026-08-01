import SwiftUI

/// Points riding on whether a plan actually happens.
///
/// Both people put in the same amount, and it resolves from the attendance confirmations — so
/// following through pays it back as a bonus and a plan that falls through costs both sides.
/// Never one at the other's expense: the record says whether it happened, not whose fault it
/// was, so there is no loser to pay a winner.
struct StakeRow: View {
    let state: RequestDetailViewModel.StakeState
    let partnerName: String
    let isBusy: Bool
    let onPropose: (Int) -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            switch state {
            case .available:
                offer
            case .awaitingThem(let points):
                line("\(points) points on it — waiting for \(partnerName) to agree", icon: "hourglass")
            case .awaitingYou(let points):
                accept(points)
            case .live(let points):
                line("\(points) points riding on this", icon: "flame.fill", tint: MGColors.coral)
            case .settled(let settlement, let points):
                line(
                    settlement == .kept
                        ? "\(settlement.displayName) — \(points) points each"
                        : "\(settlement.displayName) — you both lost \(points)",
                    icon: settlement == .kept ? "checkmark.seal.fill" : "xmark.seal",
                    tint: settlement == .kept ? MGColors.teal : MGColors.warm600
                )
            }
        }
        .mgSurfaceCard()
    }

    private var offer: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            Text("Put points on it?")
                .mgFont(.h3)
            Text("You both stake the same. Turn up and you each get it back as a bonus.")
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.warm600)

            HStack(spacing: MGSpacing.sm) {
                ForEach(Stake.options, id: \.self) { points in
                    Button {
                        onPropose(points)
                    } label: {
                        Text("\(points)")
                            .mgFont(.body)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, MGSpacing.sm)
                            .background(MGColors.warm100)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(isBusy)
                    .accessibilityLabel("Stake \(points) points")
                }
            }
        }
    }

    private func accept(_ points: Int) -> some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            Text("\(partnerName) put \(points) points on this")
                .mgFont(.body)
            Text("Match it and you both have something riding on turning up.")
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.warm600)

            Button {
                onAccept()
            } label: {
                Text("Match \(points)")
                    .mgFont(.body)
                    .foregroundStyle(MGColors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MGSpacing.sm)
                    .background(MGColors.indigo)
                    .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(isBusy)
        }
    }

    private func line(_ text: String, icon: String, tint: Color = MGColors.warm600) -> some View {
        HStack(spacing: MGSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.warm600)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: MGSpacing.lg) {
        StakeRow(state: .available, partnerName: "Sam", isBusy: false, onPropose: { _ in }, onAccept: {})
        StakeRow(state: .awaitingYou(points: 25), partnerName: "Sam", isBusy: false, onPropose: { _ in }, onAccept: {})
        StakeRow(state: .live(points: 25), partnerName: "Sam", isBusy: false, onPropose: { _ in }, onAccept: {})
        StakeRow(
            state: .settled(.kept, points: 25),
            partnerName: "Sam",
            isBusy: false,
            onPropose: { _ in },
            onAccept: {}
        )
    }
    .padding()
    .background(MGColors.sand)
}
