import SwiftUI

/// Plans two people remember differently, and somebody asked us to look at.
///
/// Its own queue rather than a row in Reports. That queue means abuse and carries a stated
/// 24-hour review promise; a disagreement about whether Tuesday happened is neither, and filing
/// one there would both dilute the promise and read as reporting somebody's conduct.
///
/// Nothing here decides anything about the plan. A contested plan already scores nothing either
/// way and pays no stake — the outcome recorded here is a record that a person looked.
struct AdminDisputesSection: View {
    let disputes: [PlanDispute]
    let onResolve: (PlanDispute, ReportResolution) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plans people remember differently. Nothing is decided until somebody reads one.")
                .mgFont(.caption)
                .foregroundStyle(MGColors.warm600)

            if disputes.isEmpty {
                Text("Nothing disputed.")
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mgSurfaceCard()
            }

            ForEach(disputes) { dispute in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(dispute.planTitle, systemImage: "questionmark.circle")
                            .mgFont(.bodySmall, color: MGColors.slate)
                        Spacer()
                        Text(dispute.at.formatted(date: .abbreviated, time: .shortened))
                            .mgFont(.caption)
                            .foregroundStyle(MGColors.warm600)
                    }

                    if let note = dispute.note, !note.isEmpty {
                        Text(note)
                            .mgFont(.bodySmall)
                            .foregroundStyle(MGColors.slate)
                    }

                    row("Raised by", dispute.raisedBy)
                    row("Plan", dispute.requestID)

                    if let resolution = dispute.resolution {
                        let when = dispute.resolvedAt?
                            .formatted(date: .abbreviated, time: .shortened) ?? ""
                        row(resolution.displayName, "\(dispute.resolvedBy ?? "someone") · \(when)")
                    } else {
                        decisionButtons(for: dispute)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .mgSurfaceCard()
            }
        }
    }

    private func decisionButtons(for dispute: PlanDispute) -> some View {
        HStack(spacing: 8) {
            Button {
                onResolve(dispute, .actioned)
            } label: {
                // A `Label`, and the colour passed into `mgFont` — see `mgFont(_:color:)`, which
                // exists because setting it afterwards is silently dropped.
                Label("Actioned", systemImage: "checkmark")
                    .mgFont(.bodySmall, color: MGColors.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(MGColors.indigo)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                onResolve(dispute, .dismissed)
            } label: {
                Label("Dismiss", systemImage: "xmark")
                    .mgFont(.bodySmall)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(MGColors.indigo.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .mgFont(.caption)
                .foregroundStyle(MGColors.warm600)
            Spacer()
            Text(value)
                .mgFont(.caption)
                .foregroundStyle(MGColors.warm600)
        }
    }
}
