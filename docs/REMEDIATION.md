# Middle Ground — Remediation Record

Companion to [`DIAGNOSIS.md`](DIAGNOSIS.md): what was fixed, how it was verified, and what is
still outstanding.

**Verified state** (Xcode 26.6, iOS 26.5 SDK):

| Check | Result |
|---|---|
| `xcodebuild -scheme MiddleGround … test` | **TEST SUCCEEDED** — 40 tests, 0 failures, 0 source warnings |
| `xcodegen generate && xcodebuild -scheme MiddleGroundApp … build` | **BUILD SUCCEEDED** — produces `Middle Ground.app` |
| `swiftlint lint --strict` | **0 violations** |

Before: the package did not compile (29 errors), the test target did not compile, and no user
could create a request. Test count went 20 → 40.

---

## P0 — Compilation: all 29 errors fixed

| Finding | Fix |
|---|---|
| Actor conformance crossing isolation (5 errors, incl. the test mock) | Root cause was `RequestRepository.observeRequests` and `AuthServiceProtocol.authStateStream` being **synchronous** requirements witnessed by actor-isolated methods. Marked the stream factories `nonisolated` on every conformer. `AuthService` was restructured so each stream owns its own Firebase listener and removes it on termination — deleting the stored `handle`/`continuation` that caused three of the diagnostics. |
| `CachedRequestRepository`: 12 × `cannot find 'modelContext'` | Bound `let ctx = context` once per method (the pattern the sibling repositories already used). A blind rename would have kept the latent bug: `context` is a *computed* property that mints a new `ModelContext` per access, so fetch/mutate/save would each hit a different one. |
| `Dependencies.swift`: 4 × ternary type mismatch | Explicit protocol casts (`MockRequestRepository() as RequestRepository`). |
| `OnboardingView`: 3 × missing `systemImage` | `PrimaryButton.systemImage` now defaults to `nil`. |
| `AppDelegate:14` async call | Wrapped in `Task`. |
| `OnboardingViewModel:120` `withAnimation` | Added `import SwiftUI`. |
| `RequestDetailView:105` `@Previewable` ordering | Moved the declaration to the top of the preview block. |
| `AIAssistantView:21` `Identifiable` | Resolved by removing the AI tab. |

**Warnings: 17 → 0.** Included three that were hard errors under Swift 6: `LocalStore` no longer
`@MainActor` (a `ModelContainer` is `Sendable`), `FirestoreRequestRepository` builds Firestore
locally inside its `nonisolated` stream, `SignInWithAppleManager` is explicitly `@MainActor`.
Also replaced the deprecated `OAuthProvider.credential(withProviderID:)` and removed a
force-unwrap crash path in the nonce generator.

---

## P1 — Partner pairing: the blocked journey now works

Onboarding created a relationship containing only its owner and discarded `partnerName`, so
`recipientID` stayed empty and `canSubmit` could never be true.

- `Relationship` gained an `inviteCode` (6 chars, ambiguous characters `O/0/I/1/L` excluded so
  it can be read aloud), plus `isPaired` and `partnerID(excluding:)`.
- New `RelationshipService` owns create/join, with typed `PairingError` cases for unknown code,
  already joined, and redeeming your own code.
- Onboarding now offers **Invite someone** or **I have a code**; the final step shows the code
  with a `ShareLink`. Profile shows the same code until someone joins.
- The "(optional)" partner-name field that silently gated the Get Started button is gone.
- Recipient pickers now show the partner's **name** instead of the relationship type, falling
  back to the type only when nobody has joined.
- Compose shows "No one has joined yet" with a pointer to the invite code, instead of an
  empty picker.

Covered by `RelationshipServiceTests` (8 tests).

---

## P2 — Inert features made real

- **Gamification now writes.** `save(stats:)` previously had no caller outside tests. Added
  `recordResponse(_:to:for:)`, called from both `HomeViewModel` and `RequestDetailViewModel`.
  It awards XP per response type, extends the streak (same-day responses don't double-count),
  recomputes level and growth score, unlocks achievements, and appends to the activity feed.
  Achievement criteria match their own copy — "Weekend Warrior" counts accepts whose
  `proposedTime` actually falls on a weekend. Covered by `GamificationRewardTests` (11 tests).
- **Live sync is reachable.** `HomeView.task` now subscribes to `observeRequests()`, so the
  whole `AsyncStream` → `addSnapshotListener` chain is live rather than dead code.
- **Stale cache fixed.** `fetchRequests` merged the remote in a detached `Task` and returned a
  stale snapshot. It now merges before returning and falls back to cache when offline.
- **Streak strip is real.** `StreakView`'s hardcoded `[true, true, true, true, false, true, true]`
  is replaced by `weeklyCompletion(for:)`, derived from days the user actually earned XP.
- **Push can now deliver.** The `NotificationService` TODO is implemented: FCM tokens are
  written to `user_tokens/{uid}` (the exact path the Cloud Functions read), re-attached after
  sign-in, and detached on sign-out.
- **Profile rows work.** Help / Privacy / Terms are real `Link`s to URLs in `AppConfiguration`;
  the notification toggle no longer discards its value and opens Settings when disabling.
- **Dead code removed.** `SyncService` (47 lines, never resolved) deleted.

---

## P3 — AI tab removed

`Features/AIAssistant/` deleted and the tab dropped (5 → 4). It was three hardcoded strings
with a `Task.sleep` faking work and a refresh that was a literal no-op. `RequestTemplate` and
the prefilled-compose deep link went with it; if suggestions return, note that all three canned
examples are computable on-device from real request history — no LLM required.

---

## P4/P5 — Design system and accessibility

- **Dynamic Type now supported.** This was the systemic accessibility hole: every size was a
  fixed `Font.system(size:)`, which has no `relativeTo:` overload and does not scale. Replaced
  with `MGTextStyle` + a `@ScaledMetric`-backed `.mgFont(_:)` modifier that keeps the brand's
  exact sizes while tracking the reader's setting. All 91 call sites migrated; no unscaled path
  remains.
- **Dark mode implemented.** `MGColors` tokens are now adaptive (`Color(light:dark:)`), ported
  from the brand's own `dark-mode.css`. Previously `surface` was hardcoded `Color.white`, so
  system chrome went dark while every card stayed white.
- **Contrast fixed.** `warm400` (~2.3:1 on sand, below WCAG AA) is no longer used for text;
  readable copy uses `warm600`. It remains for decorative/disabled chrome only.
- **Design tokens added.** `MGSpacing` / `MGRadius` / `MGShadow` / `MGMotion` in `Tokens.swift`,
  matching the brand doc. The card shadow that was retyped nine times is now `MGShadow.md`.

---

## P6 — Backend configuration

- **`firestore.rules` written** (previously absent — every user's data sat in shared root
  collections with no rules). Requests are readable only by participants; relationships only by
  members; `user_tokens` unreadable by clients entirely; explicit deny-all fallthrough.
- **Invite redemption is secure by design.** Codes live in their own `invites/{code}` collection
  where rules allow `get` but deny `list`, so a code you were told can be redeemed but codes
  cannot be enumerated. A non-member may add *only themselves*, *only once*, and only to an
  unpaired relationship — enforced in rules, not just client code.
- **`firestore.indexes.json`** declares the **two** composite indexes the OR query actually
  needs. The README previously documented one three-field index that would not have worked.
- **`firebase.json`** added — `CloudFunctions/README.md` referenced it but it never existed, so
  the documented deploy command failed.
- **`Package.resolved` is now committed** (un-ignored) since dependencies use open ranges.
- **Firebase upgraded 10.29 → 11.15**, dropping the `FirebaseFirestoreSwift` product that was
  merged into `FirebaseFirestore`. Note this was *elective*: `from: "10.0.0"` bounds to `<11`,
  so nothing was broken beforehand (see "Corrected assumptions" in the diagnosis).
- **`AppDelegate` made `public`** so the documented copy-out app-target actually compiles.

---

## P7 — Tests: 20 → 40, all passing

- **Fixture incoherence fixed.** `MockAuthService` returned `test_user` while
  `Relationship.preview` contained `user_1`/`user_2`, so partner lookup found nobody. The mock
  now signs in as `User.preview`.
- **`authService` finally has a mock branch.** It was the only factory without one and called
  `Auth.auth()` in `init`, so all 10 previews that set `useMockRepositories` crashed. Added a
  DEBUG-gated `PreviewAuthService` — unlike the pre-existing mocks, it does not ship in release.
- **Vacuous assertions replaced.** The calendar test looped over an always-empty collection;
  it now anchors on a date known to have an event and asserts the empty case separately. Load
  tests now assert data actually arrived, not just that no error was set.
- **Order-dependent test fixed.** `GamificationServiceTests` wrote to `UserDefaults.standard`
  and passed only once per machine. `GamificationService` now takes an injectable `UserDefaults`,
  and each test gets a fresh suite.
- **`SyncTests` rewritten** to assert on specific requests rather than total counts (the mock
  remote seeds its own fixtures, and merging them is correct), plus new coverage for
  newer-remote-wins and the observe stream.

---

## Round 2 — app shell, tooling, and the rest of accessibility

**The app now builds as a real app.** `App/project.yml` is an XcodeGen spec that generates the
`.xcodeproj`, `Info.plist` (including `UIBackgroundModes: remote-notification`) and entitlements
(`com.apple.developer.applesignin`, `aps-environment`). Verified end-to-end: it produces
`Middle Ground.app` with the right keys embedded and Firebase linked.

Two traps found while doing it, both worth knowing:

- **XcodeGen overwrites `Info.plist` and the entitlements on every run.** Hand-written versions
  were silently clobbered — the first generated pair had *empty* entitlements and no background
  mode. All keys now live in `project.yml`, and the generated files are gitignored so nobody
  edits them by mistake.
- **An `.xcodeproj` next to `Package.swift` shadows the package's own scheme**, which broke
  `xcodebuild -scheme MiddleGround test` ("not configured for the test action"). The app shell
  therefore lives in its own `App/` directory. `AppTarget/` was renamed to `App/`.

**Dynamic Type is now complete.** Round 1 made fonts scale; their containers still didn't, so
large text would have clipped. `@ScaledMetric` now drives the achievement badge, activity icon
wells, calendar day cells, level badge, profile avatar, settings icon column, the send button
and the FAB.

**Linting and CI.** `.swiftlint.yml` plus a three-job workflow (package tests, app-shell build,
Firestore rules). Getting to `--strict` clean meant fixing **503 violations** — mostly
pre-existing trailing whitespace, auto-fixed — and then 29 genuine ones by hand, including:

- `print` → `os.Logger` (`MGLog`); `print` is invisible in release builds.
- The `fatalError` in the Sign in with Apple nonce generator now returns `nil` and surfaces a
  recoverable error — a failed sign-in should not kill the app.
- `colors.randomElement()!` in `CelebrationView` removed.
- The dead notification-bell button (an empty `Button(action: {})`) deleted.

**Firestore rules are now tested.** `CloudFunctions/test/rules.test.js` covers 25 cases against
the emulator — participant-only reads, authorship spoofing, invite redemption adding *only*
yourself, and critically that invite codes are gettable but **not** listable. **These were not
run locally: the Firestore emulator needs a Java runtime, which this machine lacks.** They are
syntax-checked and wired into CI, but their first real execution will be on GitHub Actions.

**`LocalStore` no longer crashes on launch.** A failed on-disk container falls back to
in-memory (the cache is derived data; Firestore is the source of truth) and exposes
`isEphemeral`.

### A regression I introduced and caught

While reformatting fixtures for the linter, a text splice overwrote `defaultAchievements` with
`MockGamificationService`'s *unlocked* values — every new user would have started with three
achievements already earned. `testDefaultAchievementsAreLocked` and
`testNegotiatingTenTimesUnlocksGreatCommunicator` both failed, which is exactly what those
tests are for. Fixed and re-verified.

---

## Still outstanding

1. **Privacy Policy content.** The link resolves to `middleground.app/privacy`; that page must
   exist before App Store submission. `DEVELOPMENT_TEAM` in `App/project.yml` is also still empty.
2. **Rules tests unexecuted locally** — see above; needs Java or a CI run.
3. **No localization** — ~120 hardcoded English strings, zero `LocalizedStringKey`.
4. **Brand assets not shipped** — no `.xcassets`, no app icon, no Poppins/Inter font files. The
   type scale still uses the system rounded face, and the "two figures with a coral heart" logo
   still does not appear in the app (splash uses `Image(systemName: "heart.fill")`).
5. **Design tokens only partially adopted.** `MGSpacing`/`MGRadius` exist but call sites still
   inline most padding and corner radii; only the shadow and one motion token were migrated.
6. **`CelebrationView` particles** still spawn from a hardcoded `CGPoint(x: 200, y: 300)` with
   no stagger, so the origin is wrong on any device that isn't ~400pt wide.
7. **Spontaneous-request expiry is still decorative** — stored in `proposedTime`, and nothing
   expires anything.
