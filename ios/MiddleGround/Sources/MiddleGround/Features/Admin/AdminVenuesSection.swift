import SwiftUI

/// Curating the list of real places offered when someone fills in "Where?".
///
/// This screen is the argument for storing the list in Firestore rather than compiling it in: a
/// restaurant that closes is fixed here in seconds. Hardcoded, it would have been a code change,
/// a build, a review and a release — which is exactly why "a curated list goes stale" used to be
/// a fair objection and no longer is.
struct AdminVenuesSection: View {
    @Bindable var viewModel: AdminViewModel
    @State private var editing: Venue?
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.md) {
            HStack {
                Text("\(viewModel.venues.count) place\(viewModel.venues.count == 1 ? "" : "s")")
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)
                Spacer()
                Button {
                    isAdding = true
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .mgFont(.bodySmall)
                }
            }

            if viewModel.venues.isEmpty {
                Text("No places yet. Anything added here shows up as a suggestion when someone fills in “Where?”.")
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MGColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))
            }

            ForEach(viewModel.venues) { venue in
                Button {
                    editing = venue
                } label: {
                    row(venue)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $isAdding) {
            VenueEditor(venue: Venue(name: "", city: "")) { saved in
                Task { await viewModel.saveVenue(saved) }
            }
        }
        .sheet(item: $editing) { venue in
            VenueEditor(venue: venue) { saved in
                Task { await viewModel.saveVenue(saved) }
            } onDelete: {
                Task { await viewModel.deleteVenue(venue) }
            }
        }
    }

    private func row(_ venue: Venue) -> some View {
        HStack(spacing: MGSpacing.sm) {
            Text(venue.emoji)
            VStack(alignment: .leading, spacing: 2) {
                Text(venue.name)
                    .mgFont(.body)
                Text(subtitle(for: venue))
                    .mgFont(.caption)
                    .foregroundStyle(MGColors.warm600)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .mgFont(.caption)
                .foregroundStyle(MGColors.warm400)
        }
        .padding()
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))
    }

    /// An empty category list means the place is offered for every kind of plan, so it says so
    /// rather than showing a blank where the categories would be.
    private func subtitle(for venue: Venue) -> String {
        let kinds = venue.categories.isEmpty
            ? "Any plan"
            : venue.categories.map(\.displayName).joined(separator: ", ")
        return "\(venue.city) · \(kinds)"
    }
}

private struct VenueEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Venue
    private let onSave: (Venue) -> Void
    private let onDelete: (() -> Void)?

    init(venue: Venue, onSave: @escaping (Venue) -> Void, onDelete: (() -> Void)? = nil) {
        _draft = State(initialValue: venue)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.city.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    TextField("City", text: $draft.city)
                    TextField("Emoji", text: $draft.emoji)
                    TextField("Address (optional)", text: Binding(
                        get: { draft.address ?? "" },
                        set: { draft.address = $0.isEmpty ? nil : $0 }
                    ))
                }

                // Header and footer both as closures: `Section` has no overload taking a string
                // title alongside a footer.
                Section {
                    // `.unknown` is excluded from allCases, so a venue can never be tagged with
                    // the fallback category — it exists only for decoding something this build
                    // does not recognise.
                    ForEach(RequestCategory.allCases) { category in
                        Toggle(category.displayName, isOn: Binding(
                            get: { draft.categories.contains(category) },
                            set: { on in
                                if on {
                                    draft.categories.append(category)
                                } else {
                                    draft.categories.removeAll { $0 == category }
                                }
                            }
                        ))
                    }
                } header: {
                    Text("Suits")
                } footer: {
                    Text("Leave all off to offer this place for every kind of plan.")
                }

                Section("Order") {
                    Stepper("Rank \(draft.rank)", value: $draft.rank, in: 0...99)
                }

                if let onDelete {
                    Section {
                        Button("Remove this place", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(draft.name.isEmpty ? "New place" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var trimmed = draft
                        trimmed.name = draft.name.trimmingCharacters(in: .whitespaces)
                        trimmed.city = draft.city.trimmingCharacters(in: .whitespaces)
                        // An empty emoji renders as nothing at all in the compose chip, which
                        // looks like a broken row rather than a deliberate blank.
                        if trimmed.emoji.trimmingCharacters(in: .whitespaces).isEmpty {
                            trimmed.emoji = "📍"
                        }
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
