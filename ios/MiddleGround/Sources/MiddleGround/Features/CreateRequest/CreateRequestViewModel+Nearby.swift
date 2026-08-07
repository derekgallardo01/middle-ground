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
    }
}
