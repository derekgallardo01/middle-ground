import CoreLocation
import Foundation

/// Finding somewhere, at the moment "Where?" is still empty.
///
/// The chip row above the field already offered two things: places from a curated list that has
/// never held a document in production, and generic words like "Restaurant". Neither helps anybody
/// decide. This adds the third: places that are actually near you.
///
/// Split out of `CreateRequestViewModel` for the 500-line limit, the same way the booking link was
/// split out of `RequestDetailViewModel`.
extension CreateRequestViewModel {

    /// Miles. Twenty-five because that is what was asked for, and because nothing in the stack
    /// caps it any lower — Apple's search takes any region.
    static let maxRadiusMiles: Double = 25
    static let defaultRadiusMiles: Double = 5

    /// Whether to show the results area at all.
    var isShowingNearby: Bool { !nearbyPlaces.isEmpty || isSearchingNearby || nearbyMessage != nil }

    /// Asks for a location and searches — **only** when somebody taps.
    ///
    /// Never on appear. The privacy policy says location is off unless you ask for it, one time at
    /// a time, and a screen that searches the moment it opens makes that sentence false. The tap
    /// is the asking.
    func findNearby(kind: PlaceKind? = nil) async {
        if let kind { nearbyKind = kind }
        isSearchingNearby = true
        nearbyMessage = nil
        defer { isSearchingNearby = false }

        let coordinate: CLLocationCoordinate2D
        do {
            // Once per sheet. Asking again on every category tap and every mile of the slider was
            // both slow and more location-taking than the feature needs.
            if let known = nearbyOrigin {
                coordinate = known
            } else {
                coordinate = try await locationService.currentCoordinate()
                nearbyOrigin = coordinate
            }
        } catch {
            // A refusal is not a failure worth an alert — typing a place still works, and saying
            // so is more useful than an error.
            nearbyPlaces = []
            nearbyMessage = UserFacingError.message(for: error)
                ?? "Couldn't get your location. You can still type a place."
            return
        }

        do {
            let found = try await placeDiscovery.places(
                near: coordinate,
                radiusMiles: nearbyRadiusMiles,
                kind: nearbyKind,
                matching: nil
            )
            nearbyPlaces = found
            // An empty answer is information, and it needs saying — an empty row looks broken.
            nearbyMessage = found.isEmpty
                ? "Nothing \(nearbyKind.displayName.lowercased()) within \(Int(nearbyRadiusMiles)) miles."
                : nil
        } catch {
            nearbyPlaces = []
            nearbyMessage = "Couldn't search just now. You can still type a place."
        }
    }

    /// Re-runs after the radius changes, but only if a search already happened — otherwise moving
    /// the slider would ask for location without anybody having asked for anything.
    func radiusChanged() async {
        guard hasSearchedNearby else { return }
        await searchAgainShortly()
    }

    /// Waits for the changes to stop, then searches once.
    ///
    /// The radius is a stepped slider: a drag from 1 to 25 fired twenty-four searches, and the
    /// results flickered through all of them. Cancelling the pending one means a drag costs one
    /// search, and it is the *last* radius that gets searched rather than whichever reply happens
    /// to land last.
    func searchAgainShortly() async {
        nearbySearchTask?.cancel()

        // The spinner is deliberately left to `findNearby`. Raising it here would strand it: a
        // cancelled task never reaches the `defer` that lowers it, and a spinner that never stops
        // is a worse lie than 350ms of nothing.
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            await self.findNearby()
        }
        nearbySearchTask = task
        await task.value
    }

    /// Chooses a place: it becomes the plan's "Where?".
    func choose(_ place: DiscoveredPlace) {
        location = place.name
        chosenPlace = place
        // Apple already classified it, so the plan can wear the right face without anybody
        // being asked. Unrecognised categories leave the current choice alone rather than
        // reaching for a generic pin — the category's own emoji is a better answer than 📌.
        adoptEmoji(fromPlace: PlaceCategoryEmoji.forPointOfInterest(place.category))
    }

    /// The zone to record on the plan, if the chosen place is still the plan's place.
    ///
    /// `chosenPlace` is never cleared, so somebody who picks a restaurant in Barcelona and then
    /// types over the field would otherwise send a plan for "Joe's Diner" stamped `Europe/Madrid`
    /// — and every date on it would render an hour nobody meant, confidently. Only the place that
    /// is still in the field gets to say what time zone the plan is in.
    var placeTimeZoneID: String? {
        guard let chosenPlace,
              chosenPlace.name == location.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return typedPlaceTimeZoneID }
        return chosenPlace.timeZoneIdentifier
    }

    /// Looks up the zone for a place somebody typed, once they have stopped typing.
    ///
    /// Without this the zone could only ever be set from the nearby list, which searches from the
    /// user's *current* coordinate — so a trip to Barcelona composed at home found no Barcelona
    /// venues and the plan's zone stayed nil, for precisely the case the field exists for.
    ///
    /// Debounced the same way the nearby search is, and for the same reason: geocoding a keystroke
    /// is a request per letter for an answer that cannot be right yet.
    func lookUpTypedTimeZone() async {
        typedZoneTask?.cancel()
        let name = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard chosenPlace?.name != name else { return }
        typedPlaceTimeZoneID = nil
        guard !name.isEmpty else { return }

        let task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            let zone = await self.timeZoneLookup.timeZone(forPlaceNamed: name)
            guard !Task.isCancelled else { return }
            // Checked again on the way out: somebody who kept typing has a different place now,
            // and stamping the old answer on it is how a plan ends up on a clock nobody chose.
            guard self.location.trimmingCharacters(in: .whitespacesAndNewlines) == name else {
                return
            }
            self.typedPlaceTimeZoneID = zone?.identifier
        }
        typedZoneTask = task
        await task.value
    }
}
