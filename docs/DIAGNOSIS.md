# Middle Ground — Codebase Diagnosis

**Audited:** 2026-07-29 against commit `35a0f2b` · **Scope:** 61 Swift files / 5,313 lines, plus brand system and Cloud Functions

> ## ⚠️ Status: mostly remediated
>
> This document records the state of the codebase **as audited**. Most findings have since
> been fixed in the working tree — see [`REMEDIATION.md`](REMEDIATION.md) for what changed,
> what was verified, and what is still outstanding.
>
> Current verified state: **package tests pass (40/40, zero warnings), the app shell builds
> to `Middle Ground.app`, and `swiftlint --strict` is clean.**
>
> Still open: no localization, brand fonts and app-icon assets not shipped, design tokens only
> partially adopted, and the Firestore rules tests have not yet been executed (they need a Java
> runtime for the emulator and will first run in CI).

## Summary

Middle Ground is an app for **shared decisions**: one person proposes something ("Date night Friday?"), recipients respond with one of six actions (accept / decline / negotiate / reschedule / counter / save), and each response appends a `NegotiationMessage` to a `negotiationChain` that drives the request's status. The domain model for that is genuinely good, the layering is clean and consistent, and the brand documentation is publication-quality.

The problem is that **none of it has ever been compiled.** A full iOS build produces **29 distinct compile errors across 10 files**, and they surface in **7 dependency layers** — fixing one layer reveals the next, which is why a casual look understates the total. Beyond compilation, three headline features (gamification, live sync, the AI tab) are wired but inert, and the primary user journey is blocked by a design gap rather than a bug.

This document is severity-ranked. Each finding gives evidence, why it matters, and a fix sketch.

### How this was verified

| | |
|---|---|
| Toolchain | Xcode 26.6 (17F113), Swift 6.3.2, iOS 26.5 SDK |
| Command | `xcodebuild -scheme MiddleGround -destination 'platform=iOS Simulator,name=iPhone 17' build` |
| Method | 8 build iterations on a **throwaway copy**; each layer's errors fixed minimally to reveal the next. The repository itself was never modified. |
| Result | Layer 8 reached `** BUILD SUCCEEDED **`, then `test` ran: **20 tests, 5 failures** |

Two claims that look plausible on inspection were **disproved** by the build; they are recorded in [Corrected assumptions](#corrected-assumptions) so nobody re-files them.

---

## P0 — The package does not compile

29 errors, 10 files, 7 layers. Xcode cancels sibling compile jobs on first failure, so each build reveals only the current layer.

| Layer | File | Line(s) | Error |
|---|---|---|---|
| 1 | `Core/Repositories/Firestore/FirestoreRequestRepository.swift` | 4 | conformance crosses into actor-isolated code |
| 1 | `Core/Repositories/RequestRepository.swift` | 11 | same (`MockRequestRepository`) |
| 1 | `Core/Services/AuthService.swift` | 18 | same (`AuthService`) |
| 1 | `Core/Services/AuthService.swift` | 77 | actor-isolated `continuation` mutated from a `Sendable` closure |
| 2 | `App/AppDelegate.swift` | 14 | `'async' call in a function that does not support concurrency` |
| 2 | `App/Dependencies.swift` | 13, 21, 29, 84 | `result values in '? :' expression have mismatching types` (×4) |
| 3 | `Features/RequestDetail/RequestDetailView.swift` | 105 | `'@Previewable' items must be at the beginning of the preview block` |
| 4 | `Core/Repositories/Cached/CachedRequestRepository.swift` | 4 | conformance crosses into actor-isolated code |
| 4 | `Core/Repositories/Cached/CachedRequestRepository.swift` | 78, 84, 91, 94, 99, 105, 107, 112, 114, 120, 121, 122 | `cannot find 'modelContext' in scope` (×12) |
| 5 | `Features/Onboarding/OnboardingViewModel.swift` | 120 | `cannot find 'withAnimation' in scope`; `cannot infer contextual base in reference to member 'spring'` |
| 6 | `Features/AIAssistant/AIAssistantView.swift` | 21 | `sheet(item:)` requires `RequestTemplate` to conform to `Identifiable` |
| 7 | `Features/Onboarding/OnboardingView.swift` | 105, 130, 171 | `missing argument for parameter 'systemImage'` (×3) |

Plus one in the **test target**, so `swift test` cannot run either:

| File | Line | Error |
|---|---|---|
| `Tests/MiddleGroundTests/Mocks/MockAuthService.swift` | 4 | conformance of `MockAuthService` to `AuthServiceProtocol` crosses into actor-isolated code |

### P0.1 — Actor conformance: sync protocol requirements on `actor` types

**Five errors, one root cause.** [`RequestRepository`](../ios/MiddleGround/Sources/MiddleGround/Core/Repositories/RequestRepository.swift#L3) and [`AuthServiceProtocol`](../ios/MiddleGround/Sources/MiddleGround/Core/Services/AuthService.swift#L11) each declare a **non-`async`** requirement returning an `AsyncStream`:

```swift
func observeRequests(for userID: String) -> AsyncStream<[Request]>   // RequestRepository
func authStateStream() -> AsyncStream<User?>                          // AuthServiceProtocol
```

Every conformer is an `actor`, so its implementation is actor-isolated — and an actor-isolated method cannot satisfy a synchronous protocol requirement. The compiler's own note says it: *"mark all declarations used in the conformance `nonisolated`."*

Note the asymmetry: `UserRepository` and `RelationshipRepository` declare **only** `async` requirements and compile fine. The two protocols that break are exactly the two with a synchronous stream accessor.

**Fix:** mark the stream methods `nonisolated` on each conformer (they don't need isolated state — they construct and return a stream). `AuthService` needs more care: `authStateStream()` assigns `self.continuation`, which is why line 77 also fails. Move the continuation into a small `nonisolated` box (or a `Mutex`/`nonisolated(unsafe)` holder) rather than actor state. `@preconcurrency` on the conformance silences all five but converts them to *runtime* races — acceptable as a stopgap, not as the fix.

### P0.2 — `CachedRequestRepository`: 12 references to a property that doesn't exist

The property is declared `context` at [line 13](../ios/MiddleGround/Sources/MiddleGround/Core/Repositories/Cached/CachedRequestRepository.swift#L13); twelve call sites use `modelContext`. Confirmed undeclared — no `var modelContext` anywhere in `Sources/`, and no `@ModelActor` macro that would synthesize one.

**Renaming is not the fix.** `context` is a *computed* property:

```swift
private var context: ModelContext { ModelContext(modelContainer) }
```

Every access mints a **brand-new** `ModelContext`. A blind rename would make `merge()` fetch on context A, mutate an object owned by A, then `save()` on context C — writes would silently vanish. The sibling files already do this correctly: `CachedUserRepository.swift:39` and `CachedRelationshipRepository.swift:29` bind `let ctx = context` once per method.

**Fix:** add `let ctx = context` as the first line of each of the five private methods (`fetchLocal`, `merge`, `insertLocal`, `markSynced`, `deleteLocal`) and use `ctx` throughout. Verified: this plus the conformance fix compiles, and `SyncTests.testCachedRequestRepositoryStoresRequestLocally` then passes.

### P0.3 — `Dependencies.swift`: the DI container's ternaries don't type-check

Four errors, lines 13, 21, 29, 84. The pattern is:

```swift
AppConfiguration.useMockRepositories ? MockRequestRepository() : FirestoreRequestRepository()
```

Swift infers a single type for `? :`; two distinct concrete types that merely share a protocol don't unify. **Fix:** cast one branch — `? MockRequestRepository() as RequestRepository : …` — or split into an `if/else` inside the factory closure.

This is worth calling out because `Dependencies.swift` is the DI root: every service and repository in the app resolves through this file.

### P0.4 — `PrimaryButton.systemImage` has no default, breaking onboarding

[`PrimaryButton`](../ios/MiddleGround/Sources/MiddleGround/DesignSystem/Buttons/PrimaryButton.swift#L5) declares `let systemImage: String?` — optional *type*, but no default *value*, so it is a required argument. Five of eight call sites pass it; the three in `OnboardingView` (lines 105, 130, 171) don't, and fail.

**Fix:** `var systemImage: String? = nil`. One character short of trivial, and it unblocks the app's first-run screen.

### P0.5 — Remaining single-file errors

- **`AppDelegate.swift:14`** — `notificationService.requestAuthorization()` is `async -> Bool` ([`NotificationService.swift:18`](../ios/MiddleGround/Sources/MiddleGround/Core/Services/NotificationService.swift#L18)) called bare. Fix: `Task { _ = await … }`.
- **`OnboardingViewModel.swift:120`** — calls `withAnimation(.spring(…))` but imports only `Foundation` and `Factory`. Fix: `import SwiftUI`. (Arguably the animation belongs in the view, not the view model.)
- **`RequestDetailView.swift:105`** — the `#Preview` body puts `AppConfiguration.useMockRepositories = true` *before* `@Previewable @Namespace var namespace`. Fix: `@Previewable` declarations must come first.
- **`AIAssistantView.swift:21`** — `.sheet(item:)` needs `RequestTemplate: Identifiable` ([`AIAssistantViewModel.swift:72`](../ios/MiddleGround/Sources/MiddleGround/Features/AIAssistant/AIAssistantViewModel.swift#L72)). **This error disappears entirely if the AI tab is removed** — see [P3](#p3--the-ai-tab-should-be-cut).

### P0.6 — Warnings: 17 in the clean build, and Swift 6 will re-break it

Once it compiles, the build is not quiet. Two warnings are explicitly *"an error in the Swift 6 language mode"*, so a `swift-tools-version` bump re-breaks the build:

- `Dependencies.swift:7` — main-actor-isolated `LocalStore.shared` referenced from a `Sendable` closure
- `AuthService.swift:24` — `handle` accessed in a `nonisolated` initializer

A third, `AuthService.swift:27` (actor-isolated `continuation` accessed from outside the actor), appears in the unpatched build; it is absent above only because the P0.1 stopgap suppressed it. A real fix must address all three.

The other notable cluster is **13× `no 'async' operations occur within 'await' expression`** across all three `Cached*` repositories — a smell worth reading as a design signal: those `await`s suggest the author expected the local-store calls to be async boundaries when they are not.

---

## P1 — The primary user journey is structurally blocked

**A real user can never create a request.** [`OnboardingViewModel.completeOnboarding()`](../ios/MiddleGround/Sources/MiddleGround/Features/Onboarding/OnboardingViewModel.swift#L100) builds the relationship with **only the current user** in it:

```swift
let relationship = Relationship(
    id: UUID().uuidString,
    participantIDs: [user.id],        // <- self only; partnerName is discarded
    type: selectedRelationshipType
)
```

The `partnerName` collected one screen earlier is never used, and **there is no invite, pairing, or deep-link flow anywhere in the repository.** Downstream, [`CreateRequestViewModel.loadCurrentUserAndPartners()`](../ios/MiddleGround/Sources/MiddleGround/Features/CreateRequest/CreateRequestViewModel.swift#L41) looks for a participant that isn't the current user:

```swift
if let firstPartner = relationships.first?.participantIDs.first(where: { $0 != userID }) {
    recipientID = firstPartner
}
```

It finds nothing, `recipientID` stays `""`, and `canSubmit` (line 32) requires it to be non-empty. So the compose button is permanently disabled. **For a two-person app, the two-person part does not exist.** This is the highest-value work item after P0 — nothing else in the product is demonstrable without it.

**Fix sketch:** the smallest honest version is a shared invite code. On onboarding, create the `Relationship` with `participantIDs: [user.id]` plus a short random `inviteCode`; add a "join with code" path that looks the relationship up and appends the second `user.id` via the existing `relationshipRepository.saveRelationship`. A universal-link share sheet is a nicer second iteration. Either way `partnerName` should either be persisted as a display label or removed from onboarding.

Two contradictions to clean up in the same pass:

- **The "optional" field that blocks the button.** `OnboardingViewModel.swift:44` requires `partnerName` to be non-empty for `canContinue`, while [`OnboardingView.swift:165`](../ios/MiddleGround/Sources/MiddleGround/Features/Onboarding/OnboardingView.swift#L165) labels that field `"Partner/friend name (optional)"`. "Get Started" stays disabled until the user fills in the field the UI calls optional.
- **Recipients are labeled by relationship type, not by person.** `CreateRequestView.swift:57` and `SpontaneousRequestView.swift:138` render `Text(relationship.type.displayName)`, so the picker reads "Couple", never "Sam".

---

## P2 — Features that render but do nothing

### Gamification never increments

`save(stats:)`, `save(achievements:)`, and `save(activities:)` ([`GamificationService.swift:44,50,56`](../ios/MiddleGround/Sources/MiddleGround/Core/Services/GamificationService.swift#L44)) have **exactly one caller in the repository**: `GamificationServiceTests.swift:32`. No app code path ever writes XP, streaks, or unlocks an achievement.

Consequence in production: every user is permanently level 1, 0 XP, 0-day streak, all four achievements locked. Accepting a request awards nothing. The Activities tab, the two stat cards on Home, and the level ring are decorative. This removes the Duolingo-style reward loop that `brand/design-system.md:30` names as a core design influence.

**Fix:** award on the response path. `RequestService`/`HomeViewModel` already know when a request is accepted — that's where XP and streak updates belong, followed by an achievement re-evaluation and a `save`.

### Live sync is unreachable

[`HomeViewModel.observeRequests()`](../ios/MiddleGround/Sources/MiddleGround/Features/Home/HomeViewModel.swift#L51) exists and is **never called** — `HomeView` only calls `loadRequests()`. Everything below it is therefore dead: `RequestService.swift:15` → `CachedRequestRepository.swift:50` → `FirestoreRequestRepository.swift:35` and its `addSnapshotListener`.

This makes the claim at `ios/MiddleGround/README.md:88` ("Firestore repositories stream live updates") false at runtime. Ironically the stream implementation is one of the better-written parts of the codebase — the `continuation.onTermination` listener teardown is correct.

**Fix:** call it from a `.task { await viewModel.observeRequests() }` on `HomeView` and drop the manual `loadRequests()`, or keep both with the load as a fast first paint.

### The cache returns stale data and never corrects itself — proven by a failing test

[`CachedRequestRepository.fetchRequests`](../ios/MiddleGround/Sources/MiddleGround/Core/Repositories/Cached/CachedRequestRepository.swift#L17) returns local data immediately and merges the remote result in a **detached `Task`**, with no mechanism to notify the caller when the merge lands:

```swift
let local = try fetchLocal()
Task { … try await merge(requests: remoteRequests) … }   // caller already returned
return local
```

`SyncTests.testCachedRequestRepositoryMergesRemoteUpdates` fails on exactly this — it seeds the remote, calls `fetchRequests`, and asserts 1 result but gets **0**. Combined with the dead `observeRequests`, the UI shows one-refresh-stale data until the user pulls again. Fixing live sync (above) also fixes this, since the stream path yields after merging.

### Smaller dead paths

| Finding | Evidence | Effect |
|---|---|---|
| Hardcoded weekly streak | `StreakView.swift:5` — `let weekDays: [Bool] = [true, true, true, true, false, true, true]` | A brand-new user with a 0-day streak sees 6 of 7 days lit |
| Spontaneous expiry is decorative | `SpontaneousRequestViewModel.swift:54` stores the expiry in `proposedTime`; `Request` has no expiry field and nothing expires anything | The whole "⚡ expires in 20 min" premise is cosmetic |
| Picker opens unselected | `SpontaneousRequestViewModel.swift:16` defaults `expiresInMinutes = 20`, but the picker offers only 15/30/60/120 (`SpontaneousRequestView.swift:79-82`) | Segmented control renders with nothing selected |
| `savedForLater` never set | Plumbed through model, DTO, and SwiftData entity; **never assigned `true`** anywhere | The heart button sets `status = .saved` instead; the field is vestigial |
| `SyncService` entirely unused | 47 lines; `grep syncService` over `Sources/` returns 1 hit — its own registration at `Dependencies.swift:67` | Dead code |
| Three dead Profile rows | `SettingRow` (`ProfileView.swift:116`) is a plain `HStack` with a chevron — no `Button`/`NavigationLink` | "Help & Support", "Privacy Policy", "Terms of Service" do nothing. **The missing Privacy Policy is an App Store submission blocker.** |
| Notification toggle is one-way | `ProfileView.swift:58-60` discards the setter value (`set: { _ in … }`); `ProfileViewModel.swift:45-47` has an empty `if notificationsEnabled { }` branch | Can only be turned on; turning off silently reverts. Needs `UIApplication.openSettingsURLString` |
| FCM token never persisted | `NotificationService.swift:45` — `// TODO: Persist token to Firestore user document` | The Cloud Functions read `user_tokens`, which nothing writes, so **push never reaches a device** |
| Celebration particles all spawn at one point | `CelebrationView.swift` — all 30 particles start at a hardcoded `CGPoint(x: 200, y: 300)` with an identical `0.05s` delay | Wrong origin on any device that isn't ~400pt wide, and no stagger |

Note the FCM row: it means the entire push-notification feature — two Cloud Functions, an `AppDelegate` hook, and a `NotificationService` — cannot deliver a single notification until that one TODO is done.

---

## P3 — The AI tab should be cut

[`AIAssistantViewModel`](../ios/MiddleGround/Sources/MiddleGround/Features/AIAssistant/AIAssistantViewModel.swift#L14) is three hardcoded `AISuggestion` literals ("You haven't had a date night in 3 weeks", "You've had pizza three times this week", "The weather looks perfect on Sunday"). `generateSuggestions()` fakes work and then re-loads the same three:

```swift
// TODO: Call Cloud Function with context (calendar, preferences, recent requests)
try? await Task.sleep(nanoseconds: 1_000_000_000)
loadMockSuggestions()
```

Refresh is a literal no-op. There is no LLM integration anywhere in the repository — no `URLSession`, no API client, no endpoint. This ships as one of five top-level tabs, which makes a placeholder look like a feature.

**Decision: remove it.** Delete `Features/AIAssistant/`, drop the tab from `MiddleGroundApp.swift:56-58`, and go to four tabs. This also eliminates one P0 compile error for free ([P0.5](#p05--remaining-single-file-errors)).

Worth preserving on the way out: `RequestTemplate` and the prefilled-`CreateRequestView` deep-link path are a reasonable seam if suggestions return later. And note that all three canned suggestions are **computable on-device from real request history** — "no `.relationship` request in 21 days" is a query, not an LLM call. That is the cheaper, more honest version of this feature whenever it comes back.

---

## P4 — Brand system: excellent document, ~40% implemented

`brand/design-system.md` is the strongest artifact in the repository — brand essence, personality keywords, design influences, full palette with usage columns, type scale, radii, shadows, motion curves, logo clear-space rules, app-icon export sizes, and a voice-and-tone table with before/after copy. The voice guidance is even followed in code (`HomeViewModel.swift:66` uses "Let's find a middle ground", matching `design-system.md:281` verbatim).

The Swift implementation diverges from it substantially.

| Documented | Implemented | Gap |
|---|---|---|
| Poppins (headings) + Inter (body), `design-system.md:98-101` | `Font.system(design: .rounded)` / `.default`, `Typography.swift:6-14` | Wrong typeface; **no font files in the repo at all** (`*.ttf`/`*.otf` → 0 hits). `brand/typography.css` loads them from Google Fonts — web only |
| Full dark palette, `brand/dark-mode.css` (75 lines) | **Nothing** — `grep colorScheme` over `Sources/` → **0 hits** | `Colors.swift:16` hardcodes `surface = Color.white`. System chrome (`Form`, `TabView`, nav bars) goes dark while every card stays `#FFFFFF` on `#F7F6F3` |
| Radius / shadow / motion tokens, `design-system.md:151-164, 203-205` | No Swift constants | `cornerRadius:` 16/18/20/24/28 inlined ad hoc; of 13 `.shadow(` calls, 9 are the identical `MGColors.slate.opacity(0.05), radius: 12, y: 4`; springs hand-tuned per site (`response:` 0.3/0.35/0.5/0.6) |
| Logo, app icon, splash, 5 export sizes (`design-system.md:255-260`) | **No `.xcassets`, no `.png`** | The 7 brand SVGs are never consumed. The "two figures with a coral heart" core metaphor (`design-system.md:37`) appears **nowhere in the app** — splash and onboarding both use `Image(systemName: "heart.fill")` |

**Fix sketch:** add `MGSpacing` / `MGRadius` / `MGShadow` / `MGMotion` alongside the existing `MGColors` / `MGFonts` (the namespacing pattern is already established and works well), then migrate call sites. For dark mode, the semantic layer is the leverage point: `MGColors.surface`/`sand`/`warm400` should become asset-catalog colors or `colorScheme`-aware, at which point most of the app adapts without touching feature code.

**Genuinely well done:** the component set is small, coherent, and consistently used — `PrimaryButton`/`GhostButton`/`ScaleButtonStyle`, `ResponseButton`, `RequestCard`/`StatusBadge`, `GamificationCard`, `ErrorState`, `LoadingSkeleton` (3 typed variants), `CelebrationView`. The semantic color mapping in `Colors.swift:53-77` covers all 8 `RequestStatus` cases and all 6 `ResponseType` cases and matches the doc's table exactly.

**Five declarations are defined and never used** — no reference anywhere outside their own definition: `GrowthRing` (`Cards/GamificationCard.swift:39`), `PulseEffect`/`.pulse()` (`Animations/PulseEffect.swift`), `AnyTransition.requestPush` and `.cardExpand` (`Animations/RequestTransition.swift`), and `MGFonts.heading` (`Typography.swift:4`).

---

## P5 — Accessibility: the strongest dimension, with one systemic hole

Credit where it's due — this is unusually thorough for a first commit, and it should not be lost in a refactor:

- **`accessibilityReduceMotion` is honored**, declared in 5 files across 14 usage sites (`PrimaryButton.swift:33`, `LoadingSkeleton.swift:12`, `HomeView.swift:10`, `SpontaneousRequestView.swift:6`, `GamificationView.swift:5`). `LoadingSkeleton` skips its shimmer entirely rather than just shortening it.
- 17 `accessibilityLabel`/`accessibilityHint` annotations on interactive controls.
- Correct grouping — `.accessibilityElement(children: .contain)` on `RequestCard`, `.combine` on `ErrorState`.
- Native `ContentUnavailableView` empty states inherit correct VoiceOver semantics.

**The hole: Dynamic Type is entirely unsupported.** `grep dynamicTypeSize|relativeTo:|ScaledMetric|sizeCategory` over `Sources/` → **0 hits**. Every size in `Typography.swift:6-14` is a fixed-point `Font.system(size: 48/36/28/22/18/16/14/12)` with no `relativeTo:`, so text does not scale for Larger Text users at all. Fixed frames compound it and will clip: `CalendarView.swift:189,203` (44/36pt), `AchievementsView.swift:28` (64pt circle with `lineLimit(2)`), `ActivityFeedView.swift:28` (44pt), `HomeView.swift:107` (60pt FAB), `GamificationView.swift:47` (80pt badge).

**Fix:** move `MGFonts` to `Font.system(size:relativeTo:)` — a contained change in one file that fixes text scaling app-wide — then convert the fixed frames to `@ScaledMetric`.

Secondary gaps:

- **Emoji as sole state signifier**, no text alternative: `ResponseType.emoji` is the only visual in `NegotiationBubble`'s status row (`NegotiationView.swift:79-83`); also `"🔥 \(streakDays)"` (`HomeView.swift:132`), `"⚡"`, `"🎉"`.
- `CelebrationView`'s 30 decorative particles lack `.accessibilityHidden(true)`, and the modal does no VoiceOver focus management.
- **Contrast below WCAG AA:** `MGColors.warm400 #A1A1AA` on `sand #F7F6F3` is ≈2.3:1, used for real text at `CalendarView.swift:194` and `ProfileView.swift:131`. The brand docs never mention contrast or WCAG.

---

## P6 — Nothing required to actually ship exists

**Good news first: no secrets are committed.** `.gitignore:22-28` correctly excludes `GoogleService-Info.plist`, `google-services.json`, `serviceAccountKey.json`, `.firebase/`, and `.env*` (with `!.env.example`), and `git ls-files` confirms none are tracked. There are no hardcoded keys or tokens anywhere in Swift or JS.

Everything else needed to ship is absent:

| Artifact | Status and consequence |
|---|---|
| `Info.plist` | **None** — zero `.plist` files in the repo. No `UIBackgroundModes: remote-notification`, which `AppDelegate.swift:22` depends on; no usage descriptions; no bundle identifier |
| `*.entitlements` | **None** — Sign in with Apple needs `com.apple.developer.applesignin`; push needs `aps-environment`. Both features are implemented; neither can run |
| `.xcodeproj` / `.xcworkspace` | **None.** SPM library only; `ios/MiddleGround/README.md:55-80` asks the developer to hand-build an app target |
| `firestore.rules` | **None.** `requests`, `users`, `relationships`, and `user_tokens` all live in shared root collections with no rules committed. **Treat this as a data-exposure risk, not a chore** — default-open rules on a multi-tenant schema means any authenticated user can read every couple's requests. This must land before real data does |
| `firebase.json` / `.firebaserc` | **None**, yet `CloudFunctions/README.md:30` says "or use the existing `firebase.json`" — so the documented `firebase deploy --only functions` fails as written |
| `firestore.indexes.json` | **None**, and the prose index in `ios/MiddleGround/README.md:44-51` is wrong — see below |
| `*.xcconfig` | **None** — no Debug/Release/Staging separation. `AppConfiguration` is 6 lines with one mutable global |
| Localization | **None** — no `.lproj`/`.strings`/`.xcstrings`, zero `LocalizedStringKey`. ~120 hardcoded English literals |
| `LICENSE` | **None**, though root `README.md:41` asserts "All rights reserved" |

### The documented Firestore index doesn't match the query

`ios/MiddleGround/README.md:44-51` documents **one** composite index: `creatorID` Asc / `recipientIDs` Array / `updatedAt` Desc. The actual query ([`FirestoreRequestRepository.swift:9-16`](../ios/MiddleGround/Sources/MiddleGround/Core/Repositories/Firestore/FirestoreRequestRepository.swift#L9)) is an **OR filter**:

```swift
.whereFilter(Filter.orFilter([
    Filter.whereField("creatorID", isEqualTo: userID),
    Filter.whereField("recipientIDs", arrayContains: userID)
]))
.order(by: "updatedAt", descending: true)
```

Firestore executes a disjunction as separate index scans, so this needs **two** indexes — `(creatorID Asc, updatedAt Desc)` and `(recipientIDs Array, updatedAt Desc)` — not one three-field index. Following the README will not make the query work.

### The documented mock mode crashes

Root `README.md:31` says *"To run the UI without any backend, set `AppConfiguration.useMockRepositories = true`."* But [`Dependencies.swift:77`](../ios/MiddleGround/Sources/MiddleGround/App/Dependencies.swift#L77) registers `authService` unconditionally:

```swift
var authService: Factory<AuthServiceProtocol> {
    Factory(self) { AuthService() }        // no mock branch — unlike lines 12, 20, 28, 84
}
```

`AuthService.init` calls `Auth.auth().addStateDidChangeListener` immediately, which traps without `FirebaseApp.configure()`. So the **10 previews that set the flag and construct a view model crash** (`HomeView.swift:188`, `CalendarView.swift:214`, `ProfileView.swift:139`, `GamificationView.swift:94`, `OnboardingView.swift:200`, `AIAssistantView.swift:117`, `CreateRequestView.swift:105`, `SpontaneousRequestView.swift:201`, `NegotiationView.swift:92`, `RequestDetailView.swift:104`). The other 11 previews are pure-presentation components and are fine. The test suite works around this by hand-registering `MockAuthService` — which is the tell that the production flag path was never exercised.

**Fix:** give `authService` a mock branch matching the other four factories. This is the cheapest high-leverage fix in the entire document — one factory, and the whole UI becomes previewable and demoable with no Firebase project.

### The app-target entry point can't compile as documented

`AppTarget/MiddleGroundApp.swift` is not part of any SPM target, so it never compiled in this verification. Reading it: it does `import MiddleGround` and references `AppDelegate`, but [`AppDelegate`](../ios/MiddleGround/Sources/MiddleGround/App/AppDelegate.swift#L6) is **`internal`** while `MiddleGroundRootView` is correctly `public`. Anyone following the README's copy-out instructions will hit "cannot find 'AppDelegate' in scope". **Fix:** make `AppDelegate` and its initializer `public`.

---

## P7 — Tests: 20 tests, and several cannot fail

Once the target compiles, `20 tests` run with `5 failures`.

| Suite | Result |
|---|---|
| `RequestTests` (4) | passed — the best file in the suite; tests real `addResponse` → status transitions |
| `CalendarViewModelTests` (3) | passed |
| `GamificationServiceTests` (3) | passed |
| `GamificationViewModelTests` (2) | passed |
| `HomeViewModelTests` (3) | passed |
| `CreateRequestViewModelTests` (3) | **2 failed** |
| `SyncTests` (2) | **1 failed** |

### The failures are real signal

- **`SyncTests.testCachedRequestRepositoryMergesRemoteUpdates`** — asserts 1 merged request, gets 0. This is the detached-refresh race in [P2](#the-cache-returns-stale-data-and-never-corrects-itself--proven-by-a-failing-test), caught by the one test that actually exercises a real code path.
- **`CreateRequestViewModelTests` ×2** — `canSubmit` never becomes true, and `createRequest()` returns nil. The proximate cause here is a **fixture ID mismatch**, not the onboarding bug: `MockAuthService` defaults to `User(id: "test_user")` while `Relationship.preview` has `participantIDs: [User.preview.id, User.preview2.id]` = `["user_1", "user_2"]`. `MockRelationshipRepository.fetchRelationships` filters on `participantIDs.contains(userID)`, matches nothing, so `recipientID` stays `""`. Fix by aligning the mock IDs. Worth noting precisely because it produces the *same symptom* as the P1 onboarding gap through a different mechanism — both leave `recipientID` empty.

### Assertions that can't fail

- `HomeViewModelTests.swift:32-33` and `CalendarViewModelTests.swift:35-36` assert only `isLoading == false` and `errorMessage == nil` — never that any data actually loaded, though the mock seeds 3 requests.
- `CalendarViewModelTests.swift:39-49` iterates `todaysEvents`, which is **empty** for the seeded fixtures (`Request.preview` is +3 days; the other two have no `proposedTime`). The loop body never executes — vacuously passing.
- `CreateRequestViewModelTests.swift:29` is named `…SetsErrorWhenNotSignedIn` but asserts only `XCTAssertNil(request)`; it never checks `errorMessage`, which `createRequest()` in fact never sets (`CreateRequestViewModel.swift:52` returns `nil` silently).

### An order-dependent test that passes exactly once

`GamificationServiceTests.swift:11,15` calls `UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")`. Under a test runner `Bundle.main.bundleIdentifier` is not the app's, so this is effectively a no-op. `testSaveAndLoadStats` then writes level 2 / 100 XP into real `UserDefaults` under `gamification_stats_test_user`, which `testDefaultStatsForNewUser:23-25` (asserting level 1 / 0 XP) will read on a later run. It passed here because of favourable ordering; it is a latent flake. **Fix:** inject a `UserDefaults(suiteName:)` into `GamificationService` instead of using `.standard`.

### Coverage gaps and shipped test doubles

**Untested:** all four `Firestore*` repositories, `FirestoreDTOs.swift` (147 lines of encode/decode), `CachedUserRepository`, `CachedRelationshipRepository`, `AuthService`, `SignInWithAppleManager` (including the nonce generator), `NotificationService`, `SyncService`, `AppState`, `OnboardingViewModel`, `ProfileViewModel`, `RequestDetailViewModel`, `SpontaneousRequestViewModel`, all three `*Entity.toModel()` round-trips, and `CloudFunctions/index.js`. No UI or snapshot tests.

**Mocks ship in the production target, ungated by `#if DEBUG`:** `MockRequestRepository` (`RequestRepository.swift:11`), `MockUserRepository`, `MockRelationshipRepository`, `MockGamificationService` (`GamificationService.swift:120` — returns a fixed level 8 / 2450 XP / 12-day streak), plus every `.preview` fixture. Note also that `ios/MiddleGround/README.md:26` documents a `Core/Repositories/Mock/` directory that **does not exist** — the mocks are appended to the bottom of each protocol file.

### No automation of any kind

No `.github/` (zero CI), no `.swiftlint.yml`/`.swiftformat`/`.editorconfig`, no `fastlane/`, no `Makefile`, no pre-commit hooks, and no lint or test config for `CloudFunctions/`. `Package.resolved` is gitignored (`.gitignore:16`) while dependencies use open ranges, so builds are not byte-reproducible across machines.

---

## Corrected assumptions

Two findings that a code-only review flags — and that this verification **disproved**. Recorded so they don't get re-filed.

**1. `FirebaseFirestoreSwift` is *not* broken.** It looks like a live hazard: the product was merged into `FirebaseFirestore` and removed in Firebase 11, and `Package.swift:12` uses an open range. But SPM's `from: "10.0.0"` means `>=10.0.0, <11.0.0` — it is bounded to major version 10. Resolution succeeds and pins **firebase-ios-sdk 10.29.0**, where `FirebaseFirestoreSwift` still exists. Nothing is broken today.

This makes the **Firebase 11+ upgrade elective modernization, not a fix.** When you take it: drop the `FirebaseFirestoreSwift` product from `Package.swift:21`, keep `import FirebaseFirestore` (the `@DocumentID` and `Timestamp` APIs `FirestoreDTOs.swift` relies on moved there intact), bump to `from: "11.0.0"`, and commit `Package.resolved` for reproducibility.

**2. The missing `Resources` directory does not fail the build.** `Package.swift:25` declares `resources: [.process("Resources")]` against target path `Sources/MiddleGround`, so it resolves to `Sources/MiddleGround/Resources` — which genuinely **does not exist** (the only `Resources/` is at the package root, is empty, and has zero tracked files, so it is absent from a fresh clone). Xcode 26.6 nonetheless builds without an error or even a warning. Still worth deleting the line as manifest hygiene, but it is not a blocker and not a P0.

---

## Recommended sequence

1. **Fix the 29 compile errors** (P0), in layer order. Budget for the fact that each fix reveals the next layer. Start with the actor-conformance root cause — it accounts for 5 of them plus the test target.
2. **Give `authService` a mock branch** ([P6](#the-documented-mock-mode-crashes)). One factory. Unlocks 10 previews and a full no-backend demo — by far the best effort-to-value ratio here.
3. **Build partner pairing** (P1). Nothing about the product is demonstrable until two people can share a relationship.
4. **Make the loop real:** award gamification on accept, and call `observeRequests()` so the UI is live and the stale-cache test passes.
5. **Cut the AI tab** (P3). Removes a placeholder from the top-level navigation and one compile error.
6. **Write `firestore.rules`** before any real user data exists (P6). This is a security item, not a polish item.
7. **Persist the FCM token** (`NotificationService.swift:45`) — until then the entire push feature cannot deliver anything.
8. **Ship-ability:** `Info.plist`, entitlements, an Xcode project, and a real Privacy Policy destination.
9. **Design-system truth-up:** tokens, dark mode, `relativeTo:` Dynamic Type, real app icon and logo assets.

## What is genuinely good

Worth protecting through the refactor:

- **The domain model.** [`Request.swift`](../ios/MiddleGround/Sources/MiddleGround/Core/Models/Request.swift) — 8 statuses, 6 response types, and a clean `addResponse` state machine that maps a response to a status. `RequestTests` covers exactly this and passes. The negotiation-chain concept is the product's actual differentiator and it is modeled well.
- **Consistent layering.** `View → @Observable ViewModel → Service → Repository protocol → Cached decorator → Firestore | Mock`, applied uniformly across 8 features with no shortcuts. The cached-decorator pattern is the right shape even though one implementation is broken.
- **The `AsyncStream` bridging.** `FirestoreRequestRepository.swift:35` wraps `addSnapshotListener` correctly, including `continuation.onTermination` listener removal — a detail that is commonly missed.
- **Accessibility instincts** — see [P5](#p5--accessibility-the-strongest-dimension-with-one-systemic-hole).
- **Secret hygiene** — the `.gitignore` was written deliberately and holds up.
- **`brand/design-system.md`** — the best-executed artifact in the repository. The implementation should be brought up to it, not the reverse.
