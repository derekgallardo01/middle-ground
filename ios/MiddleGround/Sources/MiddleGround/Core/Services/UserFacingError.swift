import AuthenticationServices
import Foundation

/// Turns whatever was thrown into something worth showing somebody.
///
/// There was no such thing, and the split it left was exact: the four screens that use
/// `ErrorState` wrote human sentences, and the four that use `.alert("Oops")` passed the raw
/// error straight through. The alert screens are the action-oriented ones, so the failures people
/// actually hit were the ones that read
///
///     The operation couldn't be completed. (FIRFirestoreErrorDomain error 7.)
///
/// Nineteen sites could produce that. It says nothing a person can act on, and "error 7" is
/// permission-denied — which for this app almost always means the write was refused by a rule,
/// not that anything is broken.
///
/// Two rules shape everything here:
///
/// 1. **Never invent a diagnosis.** Only domains and codes with a known meaning get a specific
///    sentence; everything else gets a plain, honest fallback rather than a confident guess.
/// 2. **A cancellation is not an error.** `isCancellation` exists so callers can say nothing at
///    all, which is the correct response to somebody choosing not to continue.
enum UserFacingError {

    /// Whether this is somebody deciding not to proceed, rather than a failure.
    ///
    /// Tapping Cancel on the Sign in with Apple sheet used to raise an alert titled "Oops"
    /// reading "(com.apple.AuthenticationServices.AuthorizationError error 1001.)" — the very
    /// first thing a new person can do in the app, reported as a fault.
    static func isCancellation(_ error: Error) -> Bool {
        if let authorizationError = error as? ASAuthorizationError {
            return authorizationError.code == .canceled
        }
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain {
            return nsError.code == ASAuthorizationError.canceled.rawValue
        }
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    /// A sentence to show, or nil when there is nothing worth saying.
    ///
    /// Nil means the caller should stay silent — currently only cancellations.
    static func message(for error: Error) -> String? {
        if isCancellation(error) { return nil }

        // The app's own errors already say something considered; those are the good ones and
        // they are left exactly as written.
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }

        let nsError = error as NSError

        // Firestore's numeric codes, only the ones with an unambiguous meaning for this app.
        if nsError.domain == "FIRFirestoreErrorDomain" {
            switch nsError.code {
            case 7:
                // permission-denied. In an app where every write is rule-checked, this is far
                // more often "not your turn" or "not your plan" than an outage.
                return "You're not able to do that here. It may have already been answered."
            case 14, 4:
                // unavailable / deadline-exceeded — the offline and flaky-network cases.
                return "Couldn't reach the server. Check your connection and try again."
            case 5:
                return "That's no longer there — it may have been deleted."
            case 8:
                return "Too many attempts just now. Try again in a moment."
            default:
                break
            }
        }

        if nsError.domain == NSURLErrorDomain {
            return "Couldn't reach the server. Check your connection and try again."
        }

        // Everything else. Deliberately says nothing about the cause, because at this point
        // nothing here knows it — and a specific-sounding wrong reason is worse than a vague
        // right one.
        return "Something went wrong. Please try again."
    }
}
