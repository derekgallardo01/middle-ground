import Foundation

enum AppConfiguration {
    /// Launch argument that runs the app with in-memory repositories and no Firebase.
    ///
    /// Pass it in a scheme's "Arguments Passed On Launch", or:
    ///   `xcrun simctl launch <device> app.middleground.MiddleGround -MGMockMode`
    static let mockModeLaunchArgument = "-MGMockMode"

    /// Set to `true` for Xcode previews and unit tests when Firebase is not configured.
    ///
    /// Defaults from the launch arguments so a real app run can opt in without a recompile —
    /// previously this could only be flipped by editing source.
    static var useMockRepositories: Bool =
        ProcessInfo.processInfo.arguments.contains(mockModeLaunchArgument)

    /// Launch argument selecting a deterministic DEBUG test identity, e.g. `-MGTestUser A`.
    ///
    /// Two-device pairing needs two *distinct* accounts. Passing a different label to each
    /// simulator makes an automated pairing run reproducible instead of depending on two
    /// Apple IDs being signed in.
    static var testUserLabel: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-MGTestUser"), index + 1 < args.count else {
            return nil
        }
        return args[index + 1]
    }

    /// Shows the per-type notification switches without the OS permission being granted.
    ///
    /// Those switches are deliberately hidden until iOS has granted push permission — with
    /// notifications off at the system level they control nothing, and a row of switches that
    /// change nothing is worse than no row. A simulator under UI test never grants that
    /// permission, so the feature is unphotographable without this.
    ///
    /// Narrow on purpose: it only affects whether the switches are *visible*, never what they
    /// do, and it is inert unless the argument is passed at launch.
    static var forcesNotificationSettingsVisible: Bool =
        ProcessInfo.processInfo.arguments.contains("-MGShowNotificationSettings")

    /// Whether Firebase may be configured and used.
    ///
    /// Everything that touches Firebase must check this first; in mock mode there is no
    /// `GoogleService-Info.plist` and `FirebaseApp.configure()` would abort the process.
    static var isBackendEnabled: Bool { !useMockRepositories }

    // MARK: - Legal & support destinations
    //
    // A reachable Privacy Policy, Terms and Support page are required for App Store review,
    // and these links are also surfaced in-app from Profile → About.
    //
    // These pointed at middleground.app, where every path — including nonsense ones — served
    // the same "Coming Soon" placeholder, so all three links were effectively dead. The pages
    // in `docs/legal/` are now published to Firebase Hosting, which needs no billing and no
    // DNS (see the `hosting` block in firebase.json).
    //
    // To move to middleground.app later: add it as a custom domain in the Firebase console,
    // then change this one constant. Nothing else refers to the host.

    private static let webRoot = URL(string: "https://middle-ground-8fd13.web.app")!

    static let privacyPolicyURL = webRoot.appending(path: "privacy")
    static let termsURL = webRoot.appending(path: "terms")
    static let supportURL = webRoot.appending(path: "support")

    /// The App Store listing, shared alongside an invite code.
    ///
    /// Without this the invite is unusable by the one person it is aimed at: someone who does
    /// not have the app receives a six-character code and no indication of what to do with it.
    /// Searching by name does not reliably help either — the listing is "Middle Ground: Decide
    /// Together" and an unrelated "Middle Ground Resolve" already ranks for the bare phrase.
    ///
    /// The numeric id form works before a listing is public and survives any later rename;
    /// a slug-based URL would break the moment the name changed.
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6796479061")!
}
