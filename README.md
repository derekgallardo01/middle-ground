# Middle Ground

> **Meet in the Middle.**

Middle Ground is an iOS app for shared decisions. It turns everyday requests — date nights, dinner plans, weekend logistics — into calm, collaborative workflows instead of drawn-out back-and-forth.

## Repository layout

| Path | Contents |
|------|----------|
| [`ios/MiddleGround/`](ios/MiddleGround/) | The SwiftUI app — Swift package, sample app target, and Firebase Cloud Functions. See its [README](ios/MiddleGround/README.md) for setup. |
| [`brand/`](brand/) | Brand and design system — logos, app icon, color palette, typography, and an HTML [preview](brand/preview.html). Start with [`design-system.md`](brand/design-system.md). |

## Stack

- **UI:** SwiftUI, iOS 17+ (`@Observable` MVVM)
- **DI:** Factory
- **Persistence:** SwiftData, offline-first with cached repositories
- **Backend:** Firebase — Auth, Firestore, Cloud Messaging
- **Functions:** Node.js Firebase Cloud Functions for push notifications

## Getting started

```bash
git clone https://github.com/derekgallardo01/middle-ground.git
cd middle-ground/ios/MiddleGround
open Package.swift
```

Firebase configuration (`GoogleService-Info.plist`) is intentionally not committed — follow the setup steps in [`ios/MiddleGround/README.md`](ios/MiddleGround/README.md) to supply your own. To run the UI without any backend, set `AppConfiguration.useMockRepositories = true`.

## Tests

```bash
cd ios/MiddleGround
swift test
```

## License

Not currently licensed for reuse. All rights reserved.
