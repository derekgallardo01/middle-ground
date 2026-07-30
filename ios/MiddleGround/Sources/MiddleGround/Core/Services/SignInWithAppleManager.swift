import Foundation
import UIKit
import AuthenticationServices
import CryptoKit

enum AppleSignInError: LocalizedError {
    case nonceUnavailable

    var errorDescription: String? {
        switch self {
        case .nonceUnavailable:
            return "Couldn't start Sign in with Apple. Please try again."
        }
    }
}

@MainActor
final class SignInWithAppleManager: NSObject,
                                    ASAuthorizationControllerDelegate,
                                    ASAuthorizationControllerPresentationContextProviding {
    private var completionHandler: ((Result<AppleSignInResult, Error>) -> Void)?
    private var currentNonce: String?

    func signIn(completion: @escaping (Result<AppleSignInResult, Error>) -> Void) {
        guard let nonce = Self.randomNonceString() else {
            completion(.failure(AppleSignInError.nonceUnavailable))
            return
        }
        self.completionHandler = completion
        self.currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Return the key window; in production this should be injected from the view
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return UIWindow()
        }
        return window
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = appleIDCredential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let nonce = currentNonce else {
            completionHandler?(.failure(AuthError.invalidCredential))
            return
        }

        let authorizationCode = appleIDCredential.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }

        let result = AppleSignInResult(
            idToken: identityToken,
            nonce: nonce,
            fullName: appleIDCredential.fullName,
            authorizationCode: authorizationCode
        )
        completionHandler?(.success(result))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completionHandler?(.failure(error))
    }

    // MARK: - Helpers

    /// Returns `nil` if the system CSPRNG is unavailable. A failed sign-in is recoverable;
    /// crashing the app (the previous `fatalError`) is not — and silently substituting a
    /// weaker random source would undermine the nonce's whole purpose.
    static func randomNonceString(length: Int = 32) -> String? {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)

        while result.count < length {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                MGLog.auth.error("Unable to generate a sign-in nonce: the system random source is unavailable.")
                return nil
            }

            for byte in bytes where result.count < length {
                // Reject bytes outside the charset so every character stays equally likely.
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

struct AppleSignInResult {
    let idToken: String
    let nonce: String
    let fullName: PersonNameComponents?
    /// Single-use code required by `Auth.auth().revokeToken(withAuthorizationCode:)`.
    /// Apple mandates token revocation when a Sign in with Apple account is deleted.
    let authorizationCode: String?
}
