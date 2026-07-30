import FirebaseFirestore
import Foundation

/// Deletes everything a signed-in user's client can reach in Firestore, before their auth
/// account is removed.
///
/// Guideline 5.1.1(v) requires in-app account deletion to delete the *data*, not just the
/// login. That cascade was written as the `onUserDeleted` Cloud Function, which cannot run
/// while the project is on the Spark plan — so deletion currently removes the Firebase Auth
/// user and leaves every document behind.
///
/// This closes that gap from the client. It is deliberately *not* a replacement for the
/// function: a client can be killed mid-purge, and there are documents it must not touch (a
/// request the other person created is also their data). `onUserDeleted` stays as the durable
/// backstop and re-runs the same cascade with admin privileges once Blaze is enabled.
///
/// Ordering matters: every write here is authorised as the user, so all of it must happen
/// before `firebaseUser.delete()`.
actor AccountDataPurger {
    private var db: Firestore { Firestore.firestore() }

    /// Firestore refuses a batch larger than this.
    private static let batchLimit = 450

    /// Removes what `userID` owns. Never throws: a partial purge must still let the account
    /// deletion proceed, otherwise a user who wants out is trapped by a transient failure.
    /// What is left behind is picked up by `onUserDeleted`.
    func purge(userID: String) async {
        await leaveAllRelationships(userID: userID)
        await deleteOwnRequests(userID: userID)
        await deleteOwnEvents(userID: userID)
        await deleteSingletons(userID: userID)
    }

    // MARK: - Relationships

    /// Removes the user from every group and retires any invite code they own, so a code
    /// they shared cannot outlive the account and let a stranger join whoever is left.
    private func leaveAllRelationships(userID: String) async {
        guard let snapshot = try? await db.collection("relationships")
            .whereField("participantIDs", arrayContains: userID)
            .getDocuments()
        else { return }

        for document in snapshot.documents {
            let data = document.data()
            let participants = (data["participantIDs"] as? [String]) ?? []

            try? await document.reference.updateData([
                "participantIDs": FieldValue.arrayRemove([userID])
            ])

            // Only the owner may delete the invite document, and only theirs exists.
            if participants.first == userID, let code = data["inviteCode"] as? String {
                try? await db.collection("invites").document(code).delete()
            }
        }
    }

    // MARK: - Requests

    /// Deletes only requests this user *created*.
    ///
    /// A request someone else created is their content as much as it is this user's, and the
    /// rules refuse the delete anyway (`allow delete: if resource.data.creatorID == uid()`).
    /// Scrubbing the departed user from those is the Cloud Function's job.
    ///
    /// The query filters on `allParticipantIDs` rather than `creatorID` because that is the
    /// shape `firestore.rules` can prove readable for a list — a `creatorID` query is denied.
    private func deleteOwnRequests(userID: String) async {
        guard let snapshot = try? await db.collection("requests")
            .whereField("allParticipantIDs", arrayContains: userID)
            .getDocuments()
        else { return }

        let mine = snapshot.documents.filter { $0.data()["creatorID"] as? String == userID }
        await deleteInBatches(mine.map(\.reference))
    }

    // MARK: - Events

    private func deleteOwnEvents(userID: String) async {
        guard let snapshot = try? await db.collection("events")
            .whereField("userID", isEqualTo: userID)
            .getDocuments()
        else { return }

        await deleteInBatches(snapshot.documents.map(\.reference))
    }

    // MARK: - Per-user documents

    private func deleteSingletons(userID: String) async {
        for collection in ["users", "gamification", "user_tokens"] {
            try? await db.collection(collection).document(userID).delete()
        }
    }

    // MARK: - Helpers

    private func deleteInBatches(_ references: [DocumentReference]) async {
        for chunk in stride(from: 0, to: references.count, by: Self.batchLimit) {
            let slice = references[chunk..<min(chunk + Self.batchLimit, references.count)]
            let batch = db.batch()
            for reference in slice {
                batch.deleteDocument(reference)
            }
            try? await batch.commit()
        }
    }
}
