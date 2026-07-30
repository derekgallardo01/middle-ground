import Foundation

enum AppConfiguration {
    /// Set to `true` for Xcode previews and unit tests when Firebase is not configured.
    static var useMockRepositories: Bool = false

    // MARK: - Legal & support destinations
    //
    // A reachable Privacy Policy is required for App Store review. These point at the
    // marketing site; update the host before submitting.

    private static let webRoot = URL(string: "https://middleground.app")!

    static let privacyPolicyURL = webRoot.appending(path: "privacy")
    static let termsURL = webRoot.appending(path: "terms")
    static let supportURL = webRoot.appending(path: "support")
}
