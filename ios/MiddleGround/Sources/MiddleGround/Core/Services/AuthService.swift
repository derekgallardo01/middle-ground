import Foundation
import FirebaseAuth
import Factory

enum AuthError: LocalizedError, Equatable {
    case notAuthenticated
    case invalidCredential
    case firebaseError(String)

    /// Without `LocalizedError`, every auth failure surfaced to users as
    /// "The operation couldn't be completed. (MiddleGround.AuthError error 0.)" —
    /// which says nothing and hides the underlying cause from logs too.
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You're not signed in."
        case .invalidCredential:
            return "That sign-in couldn't be verified. Please try again."
        case .firebaseError(let message):
            return message
        }
    }
}

protocol AuthServiceProtocol: Sendable {
    func currentUser() async -> User?
    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws -> User
    func signOut() async throws

    /// Permanently deletes the signed-in account.
    ///
    /// Required by App Store Guideline 5.1.1(v): any app that creates an account must let
    /// the user delete it in-app. Pass the `authorizationCode` from a *fresh* Sign in with
    /// Apple authorization so the Apple token can be revoked, which Apple also requires.
    /// Firestore data is purged by `AccountDataPurger` before the auth account goes, with the
    /// `onUserDeleted` Cloud Function as the durable backstop for what a client cannot reach.
    func deleteAccount(appleAuthorizationCode: String?) async throws

    /// Whether the signed-in user carries the server-issued `admin` custom claim.
    ///
    /// Read from the ID token, not from anything the client can set. The same claim is checked
    /// in `firestore.rules`, so a tampered build gains nothing — the backend still refuses.
    func isAdmin() async -> Bool

    func authStateStream() -> AsyncStream<User?>

    #if DEBUG
    /// Signs in a throwaway anonymous user. Exists so a second simulator can act as a
    /// *distinct* person during pairing tests without needing a second Apple ID —
    /// Sign in with Apple would otherwise return the same account and be rejected as
    /// `PairingError.ownCode`. Compiled out of release builds.
    func signInAsTestUser(named name: String) async throws -> User
    #endif
}

actor AuthService: AuthServiceProtocol {
    private let userRepository = Container.shared.remoteUserRepository()
    private let analytics = Container.shared.analyticsService()

    func currentUser() async -> User? {
        guard let firebaseUser = Auth.auth().currentUser else { return nil }
        return try? await fetchUser(id: firebaseUser.uid)
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws -> User {
        let credential = OAuthProvider.credential(
            providerID: .apple,
            idToken: idToken,
            rawNonce: nonce
        )

        do {
            let result = try await Auth.auth().signIn(with: credential)
            let firebaseUser = result.user

            let displayName = fullName?.formatted()
                ?? firebaseUser.displayName
                ?? "New User"

            let user = User(
                id: firebaseUser.uid,
                name: displayName,
                avatarURL: firebaseUser.photoURL
            )

            // Checked BEFORE the save, because saveUser creates the document. Sign in with
            // Apple runs on every subsequent sign-in too, so emitting unconditionally would
            // count a returning user as a new signup and make the funnel's first step
            // meaningless.
            let isNewAccount = (try? await userRepository.user(id: firebaseUser.uid)) == nil

            try await userRepository.saveUser(user)

            if isNewAccount {
                await analytics.track(.signedUp, userID: user.id)
            }
            return user
        } catch {
            throw AuthError.firebaseError(error.localizedDescription)
        }
    }

    func signOut() async throws {
        do {
            try Auth.auth().signOut()
        } catch {
            throw AuthError.firebaseError(error.localizedDescription)
        }
    }

    func deleteAccount(appleAuthorizationCode: String?) async throws {
        guard let firebaseUser = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }

        // Purge Firestore *first*: every one of those writes is authorised as this user, so
        // none of it is possible once the auth account is gone. Until Blaze is enabled the
        // `onUserDeleted` function does not run, and without this the account would be
        // deleted while all of its data stayed — which is exactly what Guideline 5.1.1(v)
        // forbids.
        await AccountDataPurger().purge(userID: firebaseUser.uid)

        // Revoke next: once the Firebase user is gone we can no longer authenticate the
        // revocation, and Apple requires the token to be revoked on deletion.
        if let code = appleAuthorizationCode, !code.isEmpty {
            do {
                try await Auth.auth().revokeToken(withAuthorizationCode: code)
            } catch {
                // A revocation failure must not strand the user with an undeletable account,
                // so deletion still proceeds — but it IS a compliance problem (Apple requires
                // the token to be revoked), and os.Logger output is unreadable in production.
                // Reported as a non-fatal so a misconfigured Apple key is visible rather than
                // silently skipping revocation on every deletion.
                MGLog.auth.error("Apple token revocation failed: \(error.localizedDescription, privacy: .public)")
                MGLog.recordNonFatal(error, context: "Apple token revocation during account deletion")
            }
        }

        do {
            try await firebaseUser.delete()
        } catch {
            throw AuthError.firebaseError(error.localizedDescription)
        }
    }

    /// Each stream owns its own Firebase listener and removes it when the stream terminates,
    /// so no auth-state is held as actor storage.
    nonisolated func authStateStream() -> AsyncStream<User?> {
        AsyncStream { continuation in
            let handle = Auth.auth().addStateDidChangeListener { _, firebaseUser in
                let uid = firebaseUser?.uid
                Task {
                    var user: User?
                    if let uid {
                        user = try? await self.fetchUser(id: uid)
                    }
                    continuation.yield(user)
                }
            }
            continuation.onTermination = { _ in
                Auth.auth().removeStateDidChangeListener(handle)
            }
        }
    }

    func isAdmin() async -> Bool {
        guard let firebaseUser = Auth.auth().currentUser else { return false }
        // forcingRefresh so a claim granted moments ago is picked up without a re-login.
        guard let result = try? await firebaseUser.getIDTokenResult(forcingRefresh: true) else {
            return false
        }
        return result.claims["admin"] as? Bool == true
    }

    #if DEBUG
    /// Deterministic email/password test account, so the same label always maps to the same
    /// Firebase user across runs. Signs in if the account exists, creates it otherwise.
    func signInAsTestUser(named name: String) async throws -> User {
        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let email = "\(slug)@middleground.test"
        let password = "MGtest-\(slug)-pw"

        let result: AuthDataResult
        do {
            result = try await Auth.auth().signIn(withEmail: email, password: password)
        } catch let signInError as NSError {
            // With email-enumeration protection (Firebase's default), a non-existent account
            // reports `invalidCredential` rather than `userNotFound` — deliberately
            // indistinguishable from a wrong password. So treat both as "might not exist yet"
            // and let the create attempt settle it.
            let mightNotExist = [
                AuthErrorCode.userNotFound.rawValue,
                AuthErrorCode.invalidCredential.rawValue,
                AuthErrorCode.wrongPassword.rawValue
            ].contains(signInError.code)

            guard mightNotExist else {
                MGLog.auth.error(
                    "test sign-in failed (code \(signInError.code)): \(signInError.localizedDescription, privacy: .public)"
                )
                throw AuthError.firebaseError(
                    "test sign-in failed [\(signInError.code)]: \(signInError.localizedDescription)"
                )
            }

            do {
                result = try await Auth.auth().createUser(withEmail: email, password: password)
            } catch let createError as NSError {
                if createError.code == AuthErrorCode.emailAlreadyInUse.rawValue {
                    // It existed after all, so the sign-in failure was a real credential
                    // mismatch rather than a missing account.
                    throw AuthError.firebaseError(
                        "test account \(email) exists but the password did not match"
                    )
                }
                throw AuthError.firebaseError(
                    "could not create test account [\(createError.code)]: \(createError.localizedDescription)"
                )
            }
        }

        let user = User(id: result.user.uid, name: name)
        try await userRepository.saveUser(user)
        return user
    }
    #endif

    private func fetchUser(id: String) async throws -> User? {
        try await userRepository.user(id: id)
    }
}
