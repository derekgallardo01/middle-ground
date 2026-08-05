import SwiftUI

/// Says whether the device calendar already has something at the chosen time.
///
/// Shared by every screen where a time is picked, so the warning reads identically whether you are
/// proposing a plan, suggesting a new time, or countering with one. It used to exist on the first
/// of those only.
///
/// Silent when the answer is "could not look" — see `CalendarClashChecker`. A row saying nothing
/// is honest; a row implying the slot is free when the app never checked is not.
struct CalendarClashRow: View {
    let availability: CalendarAvailability
    let accessGranted: Bool
    /// Asks for calendar permission. Only reached by an explicit tap.
    let onRequestAccess: () -> Void

    var body: some View {
        switch availability {
        case .busy(let title):
            Label {
                Text(title.map { "You're busy — \($0)" } ?? "You already have something then")
                    .mgFont(.bodySmall)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MGColors.sunshine)
            }
            .accessibilityLabel(
                title.map { "Warning: your calendar already has \($0) at this time" }
                    ?? "Warning: your calendar is already busy at this time"
            )

        case .free:
            Label("Your calendar is free then", systemImage: "checkmark.circle")
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.warm600)

        case .unknown where !accessGranted:
            Button(action: onRequestAccess) {
                Label("Check my calendar for clashes", systemImage: "calendar")
                    .mgFont(.bodySmall)
            }
            .accessibilityHint("Asks permission to read your calendar, on this device only")

        case .unknown:
            EmptyView()
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: MGSpacing.md) {
        CalendarClashRow(availability: .busy("Dentist"), accessGranted: true) {}
        CalendarClashRow(availability: .free, accessGranted: true) {}
        CalendarClashRow(availability: .unknown, accessGranted: false) {}
    }
    .padding()
    .background(MGColors.sand)
}
