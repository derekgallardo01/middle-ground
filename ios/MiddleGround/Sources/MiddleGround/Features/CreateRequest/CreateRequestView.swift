import SwiftUI

struct CreateRequestView: View {
    @State private var viewModel: CreateRequestViewModel
    /// The place being looked at. `nil` means the sheet is closed — `item:` rather than a boolean
    /// and a separate selection, which is how a sheet ends up showing the previously tapped place.
    @State private var inspectedPlace: DiscoveredPlace?
    @Environment(\.dismiss) private var dismiss
    var onCreated: ((Request) -> Void)?

    init(
        initialCategory: RequestCategory = .relationship,
        initialTitle: String = "",
        initialDetails: String = "",
        onCreated: ((Request) -> Void)? = nil
    ) {
        _viewModel = State(wrappedValue: CreateRequestViewModel(
            category: initialCategory,
            title: initialTitle,
            details: initialDetails
        ))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                // Only on a blank sheet. Once there is a title, offering to overwrite it is a
                // way to lose what someone just typed.
                if viewModel.title.isEmpty {
                    Section("Quick start") {
                        templateRow
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section("What kind of request?") {
                    // Through `chooseCategory` rather than straight at the property, so the
                    // view model can tell a person's choice from its own suggestion.
                    RequestTypePicker(selected: Binding(
                        get: { viewModel.category },
                        set: { viewModel.chooseCategory($0) }
                    ))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section("Details") {
                    TextField("Title", text: $viewModel.title)
                        .mgFont(.body)

                    TextField("Add a note (optional)", text: $viewModel.details, axis: .vertical)
                        .mgFont(.bodySmall)
                        .lineLimit(3...6)

                    // `location` has been on the model, the DTO and the security rules since the
                    // beginning and was rendered nowhere — stored on every request and readable
                    // by nobody. This is the field finally having a use.
                    TextField("Where? (optional)", text: $viewModel.location)
                        .mgFont(.bodySmall)
                        .textInputAutocapitalization(.words)

                    // Only on an empty field, and only for categories where a venue makes
                    // sense — offering "restaurant" for splitting the chores would be noise.
                    nearbyFinder

                    if viewModel.location.isEmpty {
                        placeSuggestions
                    }
                }

                Section("When?") {
                    Toggle("Suggest a time", isOn: $viewModel.includeTime)
                    if viewModel.includeTime {
                        DatePicker("Proposed time", selection: $viewModel.proposedTime)
                        CalendarClashRow(
                            availability: viewModel.availability,
                            accessGranted: viewModel.calendarAccessGranted
                        ) {
                            Task { await viewModel.enableCalendarChecks() }
                        }

                        // The other half of "is this time any good": your calendar, and then
                        // whether anybody else has already said they cannot make that day.
                        if let busy = viewModel.busyDay, let warning = busy.warning {
                            Label {
                                Text(warning).mgFont(.bodySmall)
                            } icon: {
                                Image(systemName: "person.crop.circle.badge.exclamationmark")
                                    .foregroundStyle(MGColors.warm600)
                            }
                            .foregroundStyle(MGColors.warm600)
                            .accessibilityLabel(warning)
                        }
                    }
                }

                Section("Who?") {
                    if viewModel.isLoadingPartners {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if viewModel.relationships.isEmpty || viewModel.needsPartner {
                        // Was a text block naming the Profile tab with no way to get there —
                        // from a modal sheet, that meant dismiss, switch tab, scroll, and
                        // start over. Sharing happens inline instead.
                        InvitePrompt(code: viewModel.inviteCode, compact: true)
                    } else {
                        // Tagged by relationship, not by a participant. Tagging by "the first
                        // person who is not me" gave a couple and a group containing that same
                        // person identical tags, so the group could not be chosen at all.
                        Picker("Recipient", selection: $viewModel.selectedRelationshipID) {
                            ForEach(viewModel.relationships) { relationship in
                                Text(viewModel.label(for: relationship))
                                    .tag(relationship.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(MGColors.slate)
                        .accessibilityLabel("Cancel creating request")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task {
                            if let request = await viewModel.createRequest() {
                                onCreated?(request)
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canSubmit || viewModel.isLoading)
                    .foregroundStyle(MGColors.indigo)
                    .fontWeight(.semibold)
                    .accessibilityLabel("Send request")
                }
            }
            .alert("Oops", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .sheet(item: $inspectedPlace) { place in
            PlaceDetailView(place: place) { chosen in
                viewModel.choose(chosen)
            }
        }
        .task {
            await viewModel.loadCurrentUserAndPartners()
            await viewModel.loadGroupAvailability()
        }
        // The recipient decides which group's availability applies, so switching person changes
        // the answer.
        .onChange(of: viewModel.selectedRelationshipID) { _, _ in
            viewModel.suggestCategoryFromRecipient()
            Task { await viewModel.loadGroupAvailability() }
        }
    }

    /// Prompts for the "Where?" field, by category.
    ///
    /// Curated named places first, then generic kinds of place.
    ///
    /// The objection to a curated list was that it goes stale, and that objection was right about
    /// a *hardcoded* one — a closed restaurant would have needed a code change and an App Store
    /// submission. Curated in Firestore instead, it is an edit. So real places lead here, because
    /// "Lucia's" is a decision already made and "Restaurant" is the same blank page with a
    /// category attached.
    ///
    /// The generic kinds stay, and are what shows when the list is empty, unreachable, or has
    /// nothing for this category. The field remains free text either way — tapping fills a
    /// starting point, it does not replace typing somewhere real.
    @ViewBuilder
    private var placeSuggestions: some View {
        let kinds = PlaceSuggestion.forCategory(viewModel.category)
        let places = viewModel.suggestedVenues
        if !kinds.isEmpty || !places.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MGSpacing.sm) {
                    // Real named places lead. "Lucia's" is a decision already made; "Restaurant"
                    // is the same blank page with a category attached.
                    ForEach(places) { venue in
                        chip(emoji: venue.emoji, label: venue.name, tinted: true) {
                            viewModel.location = venue.locationText
                        }
                        .accessibilityLabel("Set location to \(venue.name) in \(venue.city)")
                    }

                    ForEach(kinds) { place in
                        chip(emoji: place.emoji, label: place.name, tinted: false) {
                            viewModel.location = place.name
                        }
                        .accessibilityLabel("Set location to \(place.name)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// Somewhere near you, on request.
    ///
    /// Deliberately a button rather than a search that runs when the sheet opens. The privacy
    /// policy says location is off unless you ask for it, one time at a time — a screen that
    /// searches on appear makes that sentence false, and this is the sentence being kept.
    @ViewBuilder
    private var nearbyFinder: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            HStack(spacing: MGSpacing.sm) {
                Button {
                    Task {
                        viewModel.hasSearchedNearby = true
                        await viewModel.findNearby()
                    }
                } label: {
                    Label(
                        viewModel.hasSearchedNearby ? "Search again" : "Find somewhere near me",
                        systemImage: "location.magnifyingglass"
                    )
                    .mgFont(.caption, color: MGColors.onAccent)
                    .padding(.vertical, MGSpacing.xs)
                    .padding(.horizontal, MGSpacing.md)
                    .background(MGColors.indigo)
                    .clipShape(Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(viewModel.isSearchingNearby)

                if viewModel.isSearchingNearby {
                    ProgressView().controlSize(.small)
                }
            }

            if viewModel.hasSearchedNearby {
                // What to look for, and how far. Both only appear once somebody has asked, so the
                // compose sheet does not open covered in controls nobody wanted yet.
                Picker("What sort of place", selection: $viewModel.nearbyKind) {
                    ForEach(PlaceKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.nearbyKind) { _, _ in
                    Task { await viewModel.radiusChanged() }
                }

                HStack(spacing: MGSpacing.sm) {
                    Text("Within")
                        .mgFont(.caption)
                        .foregroundStyle(MGColors.warm600)
                    Slider(
                        value: $viewModel.nearbyRadiusMiles,
                        in: 1...CreateRequestViewModel.maxRadiusMiles,
                        step: 1
                    )
                    .accessibilityLabel("Search radius")
                    .accessibilityValue("\(Int(viewModel.nearbyRadiusMiles)) miles")
                    Text("\(Int(viewModel.nearbyRadiusMiles)) mi")
                        .mgFont(.caption)
                        .foregroundStyle(MGColors.slate)
                        .frame(width: 44, alignment: .trailing)
                        .monospacedDigit()
                }
                .onChange(of: viewModel.nearbyRadiusMiles) { _, _ in
                    Task { await viewModel.radiusChanged() }
                }
            }

            if let message = viewModel.nearbyMessage {
                // Said out loud rather than left as an empty row, which reads as a broken feature.
                Text(message)
                    .mgFont(.caption)
                    .foregroundStyle(MGColors.warm600)
            }

            if !viewModel.nearbyPlaces.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MGSpacing.sm) {
                        ForEach(viewModel.nearbyPlaces) { place in
                            nearbyChip(place)
                        }
                    }
                    .padding(.vertical, 2)
                }
                // A stable handle for the row itself. Scrolling it by grabbing the first chip
                // works exactly once — after that the chip is offscreen and the gesture fails
                // with "visible frame is empty".
                .accessibilityIdentifier("nearbyPlaces")
            }
        }
    }

    /// A found place: its name, and what it is and how far, so the choice is informed.
    private func nearbyChip(_ place: DiscoveredPlace) -> some View {
        Button {
            // Opens rather than chooses. A name, a category and a distance are enough to recognise
            // somewhere you already know and not enough to pick somewhere you do not — the picture,
            // the address and the phone number are behind this tap, and choosing is one more.
            inspectedPlace = place
            Haptics.shared.impact(.light)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .mgFont(.caption, color: MGColors.slate)
                    .lineLimit(1)
                if !place.subtitle.isEmpty {
                    Text(place.subtitle)
                        .mgFont(.caption, color: MGColors.warm600)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, MGSpacing.sm)
            .padding(.horizontal, MGSpacing.md)
            .background(
                viewModel.location == place.name
                    ? MGColors.indigo.opacity(0.14)
                    : MGColors.warm100
            )
            .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("\(place.name), \(place.subtitle)")
        .accessibilityHint("Shows more about this place")
        // A stable handle for tests. Matching on the name alone collided with a request card in
        // the feed behind the sheet — the fixtures include a plan called "Dinner at Lucia's".
        .accessibilityIdentifier("nearbyPlace")
    }

    private func chip(
        emoji: String,
        label: String,
        tinted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            Haptics.shared.impact(.light)
        } label: {
            HStack(spacing: MGSpacing.xs) {
                Text(emoji)
                Text(label)
                    .mgFont(.caption)
                    .foregroundStyle(MGColors.slate)
            }
            .padding(.vertical, MGSpacing.xs)
            .padding(.horizontal, MGSpacing.md)
            .background(tinted ? MGColors.lavender.opacity(0.25) : MGColors.warm100)
            .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }

    /// Says whether the chosen time clashes with the user's own calendar.
    ///
    /// Silent when the app cannot see the calendar. "I could not look" must never be shown as
    /// "you are free" — that is exactly how a plan gets double-booked.
    /// Prefills title and category, then leaves the user in the normal compose flow — the sheet
    /// stays open so they can add a note or a time before sending.
    private var templateRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MGSpacing.sm) {
                ForEach(RequestTemplate.all) { template in
                    Button {
                        viewModel.apply(template)
                        Haptics.shared.impact(.light)
                    } label: {
                        HStack(spacing: MGSpacing.xs) {
                            Text(template.emoji)
                            Text(template.title)
                                .mgFont(.bodySmall)
                                .foregroundStyle(MGColors.slate)
                        }
                        .lineLimit(1)
                        .padding(.vertical, MGSpacing.sm)
                        .padding(.horizontal, MGSpacing.md)
                        .background(MGColors.surface)
                        .clipShape(Capsule())
                        .mgShadow(MGShadow.sm)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel(template.title)
                    .accessibilityHint("Fills in the title and category for you")
                }
            }
            .padding(.horizontal, MGSpacing.lg)
            .padding(.vertical, MGSpacing.xs)
        }
    }

}

#Preview {
    AppConfiguration.useMockRepositories = true
    return CreateRequestView()
}
