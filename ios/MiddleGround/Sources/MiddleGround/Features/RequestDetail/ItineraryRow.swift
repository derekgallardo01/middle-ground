import SwiftUI

/// A trip, day by day.
///
/// Shown only on a multi-day plan. A dinner does not need an itinerary — it *is* one — and an
/// empty "Day 1" card under every plan in the app would make every screen longer without making
/// anything easier.
///
/// Every day appears, including the empty ones, because a gap is information: "nothing on
/// Wednesday yet" is a thing somebody can act on, and a list that quietly skips days reads as a
/// pile of items rather than a plan.
struct ItineraryRow: View {

    let days: [ItineraryDay]
    let unscheduled: [ItineraryItem]
    /// Items a change of dates left outside the trip. Shown, never silently dropped.
    let stranded: [ItineraryItem]
    let dayLabel: (ItineraryDay) -> String
    let timeLabel: (ItineraryItem) -> String
    let canRemove: (ItineraryItem) -> Bool
    let onAdd: () -> Void
    let onRemove: (ItineraryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Itinerary")
                    .mgFont(.h3)
                Spacer()
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                        .mgFont(.bodySmall)
                }
                .accessibilityLabel("Add something to the itinerary")
            }

            ForEach(days) { day in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Day \(day.number)")
                            .mgFont(.bodySmall)
                            .fontWeight(.semibold)
                        Text(dayLabel(day))
                            .mgFont(.caption)
                            .foregroundStyle(MGColors.warm600)
                    }

                    if day.items.isEmpty {
                        Text("Nothing yet")
                            .mgFont(.caption)
                            .foregroundStyle(MGColors.warm600)
                    } else {
                        ForEach(day.items) { item in
                            entry(item)
                        }
                    }
                }
            }

            if !unscheduled.isEmpty {
                section("No time yet", items: unscheduled)
            }

            if !stranded.isEmpty {
                // The dates moved and these did not. Naming that is the whole point — hidden,
                // they are lost work; filed under day one, they are a booking on the wrong
                // morning.
                VStack(alignment: .leading, spacing: 6) {
                    Label("Outside the trip dates", systemImage: "exclamationmark.triangle")
                        .mgFont(.bodySmall)
                        .foregroundStyle(MGColors.sunshineText)
                    ForEach(stranded) { item in
                        entry(item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mgSurfaceCard()
    }

    private func section(_ title: String, items: [ItineraryItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .mgFont(.bodySmall)
                .fontWeight(.semibold)
            ForEach(items) { item in
                entry(item)
            }
        }
    }

    private func entry(_ item: ItineraryItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(timeLabel(item))
                .mgFont(.caption)
                .monospacedDigit()
                .foregroundStyle(MGColors.warm600)
                // A fixed width so the titles line up into a column somebody can scan down,
                // rather than a ragged edge that moves with every time.
                .frame(width: 68, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .mgFont(.bodySmall)
                if let location = item.location, !location.isEmpty {
                    Text(location)
                        .mgFont(.caption)
                        .foregroundStyle(MGColors.warm600)
                }
            }

            Spacer(minLength: 0)

            if canRemove(item) {
                Button {
                    onRemove(item)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(MGColors.warm600)
                }
                .accessibilityLabel("Remove \(item.title)")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Adding one thing to a trip.
///
/// A time is optional, and the toggle defaults to off: "somewhere for lunch on the last day" is a
/// real item and a real thing to agree on, and making people pick an hour invents a precision
/// nobody has yet.
struct AddItineraryItemSheet: View {

    let dayRange: ClosedRange<Date>?
    let onAdd: (String, Date?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var location = ""
    @State private var hasTime = false
    @State private var when: Date

    init(dayRange: ClosedRange<Date>?, onAdd: @escaping (String, Date?, String?) -> Void) {
        self.dayRange = dayRange
        self.onAdd = onAdd
        // Opens on the first day of the trip rather than today, which is usually weeks earlier
        // and outside the range the picker allows.
        _when = State(initialValue: dayRange?.lowerBound ?? Date())
    }

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What is it?", text: $title)
                        .accessibilityIdentifier("itineraryTitle")
                    TextField("Where? (optional)", text: $location)
                }

                Section {
                    Toggle("At a particular time", isOn: $hasTime)
                    if hasTime {
                        if let dayRange {
                            DatePicker("When", selection: $when, in: dayRange)
                        } else {
                            DatePicker("When", selection: $when)
                        }
                    }
                } footer: {
                    Text("Leave this off for something you have not pinned down yet.")
                }
            }
            .navigationTitle("Add to itinerary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(title, hasTime ? when : nil, location.isEmpty ? nil : location)
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
    }
}
