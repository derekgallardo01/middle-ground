# Middle Ground — iOS App

A modular, robust, fast, and smooth iOS app for shared decisions.

## Architecture

- **UI:** SwiftUI, iOS 17+
- **State:** MVVM with `@Observable`
- **DI:** Factory
- **Persistence:** SwiftData (local cache, offline-first)
- **Backend:** Firebase (Auth, Firestore, Cloud Messaging)
- **Animations:** Native SwiftUI (`matchedGeometryEffect`, `phaseAnimator`, spring transitions)

## Project Structure

```
Sources/MiddleGround/
├── App/              // Root view, DI, global state, configuration
├── Core/             // Models, repositories, services, utilities
│   ├── Repositories/
│   │   ├── Firestore/    // Firebase-backed implementations
│   │   └── Cached/       // SwiftData cache wrappers
│   │                     // (mock implementations live at the bottom of each protocol file)
│   └── Storage/          // SwiftData entities + LocalStore
├── DesignSystem/     // Colors, typography, buttons, cards, animations
└── Features/         // Onboarding, Home, Requests, Calendar, etc.

App/
├── project.yml             // XcodeGen spec (Info.plist + entitlement keys live here)
└── MiddleGroundApp.swift   // @main app entry point

CloudFunctions/
├── index.js                // Firebase Cloud Functions for push notifications
└── package.json
```

## Setup

### 1. Firebase Configuration

1. Create a Firebase project at https://console.firebase.google.com/.
2. Add an iOS app and download `GoogleService-Info.plist`.
3. Add `GoogleService-Info.plist` to your app target (not the package).
4. Enable Firestore, Authentication, and Cloud Messaging in Firebase Console.
5. Deploy Firestore rules and indexes (both are committed at the package root):
   ```bash
   firebase deploy --only firestore:rules,firestore:indexes
   ```
   The requests query is an OR filter (`creatorID == uid` OR `recipientIDs` contains `uid`),
   which Firestore runs as separate index scans — so it needs **two** composite indexes, not
   one three-field index. Both are declared in `firestore.indexes.json`.

### 2. App target

The app target is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen),
so it is reproducible from source rather than assembled by hand:

```bash
brew install xcodegen
cd ios/MiddleGround/App
xcodegen generate
open MiddleGround.xcodeproj
```

The project is generated inside `App/` on purpose: an `.xcodeproj` sitting next to
`Package.swift` shadows the package's own scheme and breaks `xcodebuild ... test`.

Then:

1. Set `DEVELOPMENT_TEAM` in `project.yml` (or pick your team in Xcode's Signing pane) —
   Sign in with Apple and push notifications both require a real team.
2. Drop your `GoogleService-Info.plist` into the app target.
3. Build and run on an iOS 17+ simulator or device.

`App/` contains everything else the target needs:

| File | Purpose |
|------|---------|
| `project.yml` | XcodeGen spec — **the source of truth**, including all Info.plist and entitlement keys |
| `MiddleGroundApp.swift` | `@main` entry point |

`Info.plist` (with `UIBackgroundModes: remote-notification`) and `MiddleGround.entitlements`
(`com.apple.developer.applesignin`, `aps-environment`) are **generated from `project.yml`** on
every run, along with the `.xcodeproj`. All three are gitignored — edit `project.yml`, since
anything hand-written into the generated files is silently overwritten.

### Running the tests

The package targets iOS, so tests run against a simulator (`swift test` builds for the
host and cannot import UIKit):

```bash
cd ios/MiddleGround
xcodebuild -scheme MiddleGround -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Linting (`swiftlint lint --strict` from the repo root) and the Firestore rules tests both run
in CI; see `.github/workflows/ci.yml`.

### Testing the security rules

`firestore.rules` is covered by emulator tests — the privacy model is easy to get subtly
wrong and impossible to verify by reading:

```bash
cd CloudFunctions && npm install && cd ..
npx firebase-tools emulators:exec --only firestore "cd CloudFunctions && npm test"
```

Requires a Java runtime for the Firestore emulator.

## Offline-First Sync

The app uses a two-tier data layer:

1. **Local:** SwiftData entities (`RequestEntity`, `UserEntity`, `RelationshipEntity`) stored on device.
2. **Remote:** Firestore-backed repositories that stream live updates.

`Cached*Repository` classes merge remote data into SwiftData before returning, and fall back to the local cache when the network is unavailable. Live updates arrive through `observeRequests`, which `HomeView` subscribes to in its `.task`. When the user creates or updates a request, the change is written locally first, pushed to Firestore, then marked as synced.

## Mock Mode

For UI previews and unit tests without Firebase configured, set:

```swift
AppConfiguration.useMockRepositories = true
```

This swaps in in-memory repositories *and* a `PreviewAuthService`, so no Firebase project is
required — previews and tests run standalone. The app target uses Firestore by default once
`FirebaseApp.configure()` runs.

## Push Notifications

1. Enable **Cloud Messaging** in Firebase Console.
2. Upload your APNs authentication key (.p8) or certificates to Firebase.
3. Deploy the Cloud Functions in `CloudFunctions/`:
   ```bash
   cd CloudFunctions
   npm install
   firebase deploy --only functions
   ```
4. In the app, `AppDelegate` requests notification permission on launch and forwards the APNs token to FCM.
5. Store each user's FCM token in Firestore (e.g., `user_tokens/{userId}`) so the Cloud Function can target devices.
6. Tapping a notification posts `didReceiveRequestNotification`, and `HomeView` navigates to the relevant request.

## Notes

- The package includes Firestore-backed, cached, and mock repositories. Swap by changing `AppConfiguration.useMockRepositories` or overriding individual Factory registrations.
- Target iOS 17 to leverage `@Observable`, `ContentUnavailableView`, and `scrollTransition`.
- Notifications require a real device or a simulator running iOS 16.4+ with a valid APNs environment.
