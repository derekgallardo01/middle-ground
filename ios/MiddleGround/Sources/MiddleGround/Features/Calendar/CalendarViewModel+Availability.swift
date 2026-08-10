import Foundation

/// Marking yourself unavailable, and seeing who else is.
///
/// Nothing here reads the device calendar. A block is authored by hand and carries only a start
/// and an end — see `UnavailableBlock` for why that boundary matters and what it protects.
///
/// Availability is stored per group, so "who is busy" is the union across every group the user
/// belongs to. Writing goes the other way: blocking out a day writes it to each of them, because
/// being away on Thursday is true regardless of who is asking.
extension CalendarViewModel {
    /// Everyone else's blocked time, keyed by the day it covers.
    func busyNames(on day: Date) -> [String] {
        guard let currentUserID = currentUser?.id else { return [] }
        var names: Set<String> = []
        for availability in othersAvailability where availability.userID != currentUserID {
            if availability.isBusy(on: day) {
                names.insert(participantNames[availability.userID] ?? "Someone")
            }
        }
        return names.sorted()
    }

    /// Whether *you* have blocked out this day.
    func isMarkedUnavailable(on day: Date) -> Bool {
        myBlocks.contains { $0.covers(day) }
    }

    /// Somebody in a group is away — used to mark the day in the grid.
    func someoneIsBusy(on day: Date) -> Bool {
        !busyNames(on: day).isEmpty
    }

    /// Blocks out a whole day, or clears it if it was already blocked.
    ///
    /// Written to every group, because being away is a fact about the day rather than about one
    /// audience. Sharing selectively is a setting worth having later; silently sharing with only
    /// one group would be a surprise.
    func toggleUnavailable(on day: Date) async {
        guard let currentUserID = currentUser?.id else { return }

        let blocksBeforeTheChange = myBlocks
        if let existing = myBlocks.first(where: { $0.covers(day) }) {
            myBlocks.removeAll { $0.id == existing.id }
        } else {
            myBlocks.append(.wholeDay(day))
        }

        let mine = SharedAvailability(userID: currentUserID, blocks: myBlocks)
        var savedToAtLeastOneGroup = false
        for group in groups {
            // Best effort per group: one failing write should not roll back the others or the
            // local state the user just changed.
            do {
                try await availabilityRepository.save(mine, forGroup: group.id)
                savedToAtLeastOneGroup = true
            } catch {
                MGLog.storage.error("Couldn't share availability with one group.")
            }
        }

        // Every write failed, so nobody can see this. Marking yourself away is a message to other
        // people — a day that looks blocked only on your own phone is the exact failure this
        // feature exists to prevent, and `try?` made it silent. Put it back and say so.
        if !groups.isEmpty && !savedToAtLeastOneGroup {
            myBlocks = blocksBeforeTheChange
            availabilityErrorMessage = "Couldn't share that. Check your connection and try again."
        }
    }

    /// Keeps the calendar current while it is open.
    ///
    /// `observeAvailability(forGroup:)` was written against a Firestore snapshot listener and
    /// never subscribed to, so someone blocking out Saturday while you had the tab open stayed
    /// invisible until you relaunched. One stream per group, merged: they arrive independently,
    /// so each group's last delivery is held separately rather than overwriting the union.
    ///
    /// Never returns. Call it last in a `.task`, which cancels it when the screen goes away.
    func observeAvailability() async {
        await withTaskGroup(of: Void.self) { tasks in
            for group in groups {
                tasks.addTask { [weak self] in
                    guard let self else { return }
                    for await shared in await self.availabilityRepository.observeAvailability(forGroup: group.id) {
                        await self.apply(shared, forGroup: group.id)
                    }
                }
            }
        }
    }

    private func apply(_ shared: [SharedAvailability], forGroup groupID: String) {
        availabilityByGroup[groupID] = shared
        othersAvailability = availabilityByGroup.values.flatMap { $0 }
        if let currentUserID = currentUser?.id {
            myBlocks = othersAvailability.first { $0.userID == currentUserID }?.blocks ?? myBlocks
        }
    }

    /// Loads the groups, everyone's blocked time, and the names to show it against.
    func loadAvailability() async {
        guard let currentUserID = currentUser?.id else { return }
        groups = (try? await relationshipRepository.fetchRelationships(for: currentUserID)) ?? []

        var everyone: [SharedAvailability] = []
        for group in groups {
            let shared = (try? await availabilityRepository.availability(forGroup: group.id)) ?? []
            availabilityByGroup[group.id] = shared
            everyone.append(contentsOf: shared)
        }
        othersAvailability = everyone
        myBlocks = everyone.first { $0.userID == currentUserID }?.blocks ?? []

        var names: [String: String] = [:]
        for id in Set(groups.flatMap(\.participantIDs)) where id != currentUserID {
            if let user = try? await userRepository.user(id: id) {
                names[id] = user.name
            }
        }
        participantNames = names
    }
}
