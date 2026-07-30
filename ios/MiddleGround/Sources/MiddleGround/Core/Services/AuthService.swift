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
    /// Firestore data is purged server-side by the `onUserDeleted` Cloud Function.
    func deleteAccount(appleAuthorizationCode: String?) async throws

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

            try await userRepository.saveUser(user)
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

        // Revoke first: once the Firebase user is gone we can no longer authenticate the
        // revocation, and Apple requires the token to be revoked on deletion.
        if let code = appleAuthorizationCode, !code.isEmpty {
            do {
                try await Auth.auth().revokeToken(withAuthorizationCode: code)
            } catch {
                // A revocation failure must not strand the user with an undeletable account.
                MGLog.auth.error("Apple token revocation failed: \(error.localizedDescription, privacy: .public)")
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
