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
│   │   ├── Cached/       // SwiftData cache wrappers
│   │   └── Mock/         // In-memory implementations for previews/tests
│   └── Storage/          // SwiftData entities + LocalStore
├── DesignSystem/     // Colors, typography, buttons, cards, animations
└── Features/         // Onboarding, Home, Requests, Calendar, etc.

AppTarget/
└── MiddleGroundApp.swift   // Sample @main app entry point

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
5. Add Firestore composite index for the requests query:
   - Collection: `requests`
   - Fields:
     - `creatorID` Ascending
     - `recipientIDs` Array
     - `updatedAt` Descending
   - Or just run the app once and click the link in the Xcode console error.

### 2. Xcode Project

**Option A: Swift Package Manager (recommended)**

1. Open `ios/MiddleGround` in Xcode 15+.
2. Create a new iOS App target in the same workspace (or add this package to an existing app).
3. Add `MiddleGround` as a local package dependency.
4. Copy `AppTarget/MiddleGroundApp.swift` into your app target as the `@main` entry point.
5. Add your `GoogleService-Info.plist` to the app target.
6. Build and run on iOS 17+ simulator or device.

**Option B: Direct Xcode Project**

1. Create a new iOS App project in Xcode.
2. Drag `Sources/MiddleGround` into the project.
3. Add the Factory and Firebase packages via Swift Package Manager.
4. Copy `AppTarget/MiddleGroundApp.swift` into the app target.
5. Add `GoogleService-Info.plist`.
6. Build and run.

## Offline-First Sync

The app uses a two-tier data layer:

1. **Local:** SwiftData entities (`RequestEntity`, `UserEntity`, `RelationshipEntity`) stored on device.
2. **Remote:** Firestore-backed repositories that stream live updates.

`Cached*Repository` classes merge remote data into SwiftData and return local data first, so the UI is never blocked by network latency. When the user creates or updates a request, the change is written locally first, pushed to Firestore, then marked as synced.

## Mock Mode

For UI previews and unit tests without Firebase configured, set:

```swift
AppConfiguration.useMockRepositories = true
```

All previews and tests in this package already do this. The app target uses Firestore by default once `FirebaseApp.configure()` runs.

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
