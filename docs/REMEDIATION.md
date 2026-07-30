# Middle Ground — Remediation Record

Companion to [`DIAGNOSIS.md`](DIAGNOSIS.md): what was fixed, how it was verified, and what is
still outstanding.

**Verified state** (Xcode 26.6, iOS 26.5 SDK):

| Check | Result |
|---|---|
| `xcodebuild -scheme MiddleGround … test` | **51 tests, 0 failures**, 0 source warnings |
| UI walkthrough (`WalkthroughUITests`, mock mode) | **12 passed**, with screenshots |
| **Two-device E2E vs real Firebase** | **5/5 steps passed** — pair → send → live sync → accept → +25 XP |
| `swiftlint lint --strict` | **0 violations** |
| Dark mode | Verified on device in both appearances |

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
- **`firestore.indexes.json`** added. (Round 2 declared two indexes for an OR query; round 3
  replaced that query — see below — so one index now covers the request feed.)
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

## Round 3 — running it for real

Rounds 1–2 verified everything a *build* can verify. This round launched the app, and that
alone found bugs no compiler or unit test could reach.

### The app had never started

`AppDelegate` declared `NotificationService.shared` as a **stored property**, so
`NotificationService.init` — which called `Messaging.messaging()` — ran during
`AppDelegate.init`, *before* `FirebaseApp.configure()`. Firebase traps on that, so the process
aborted before drawing a frame. It would have crashed even with a valid
`GoogleService-Info.plist`. CI never caught it because CI only builds.

Also added a real `-MGMockMode` launch argument (previously mock mode could only be enabled by
editing source, and it did not gate Firebase init at all), so the UI is demoable with no backend.

### Five more bugs found by launching

| Bug | Why only a run could find it |
|---|---|
| SwiftData on-disk store failed — `Application Support` does not exist in a fresh container, so the offline cache silently degraded to memory | Visible only in device logs |
| Notification permission prompted on launch, preempting onboarding's own "Stay in sync" step and asking twice | Runtime sequencing |
| `confirmationDialog` presented as a popover exposing **no accessible buttons** — VoiceOver users could neither confirm nor cancel account deletion. Replaced with `.alert` | Found because XCUITest could not see the buttons either |
| Feed content ran under the tab bar and the FAB | Visual |
| "You have **1 active requests**" | Visual |

### Four backend bugs the two-device run exposed

Each one broke pairing or sync completely, and none was reachable without two real clients:

1. **Invite document written by the joiner.** `saveRelationship` always batch-wrote
   `invites/{code}` with `ownerID` = the owner's uid. When a *second* user joined, that write
   violated the invite rule and took the whole batch down. Now only the owner writes it.
2. **`immutable('createdAt')` could never hold.** The DTO round-trips `createdAt` through
   `Date`, losing the stored Timestamp's nanoseconds, so a full-document write always changed
   the value. Joining is now a targeted `arrayUnion` on `participantIDs` only.
3. **A joiner could not read the relationship they were joining.** `allow get` requires
   membership, so resolving an invite code by reading the relationship was always denied — and
   rules cannot verify "I know the code" on a read. Restructured so joining works entirely from
   the invite document (`RelationshipInvite`), never reading the relationship first.
4. **Rules/query mismatch on the request feed.** Rules authorise reads by `allParticipantIDs`,
   but the query used an OR over `creatorID`/`recipientIDs`. Firestore only permits a list
   query when the query's own constraints prove every match is readable, so the feed was denied
   outright. The query now filters `allParticipantIDs` — matching the rule, and needing one
   composite index instead of two.

Also: `AuthError` did not conform to `LocalizedError`, so **every** auth failure showed users
"The operation couldn't be completed. (MiddleGround.AuthError error 0.)". And the test-account
sign-in mishandled Firebase's email-enumeration protection, which reports a non-existent
account as `invalidCredential` rather than `userNotFound`.

### A product bug: the invite code was unreachable

`completeOnboarding()` advanced to the "done" step while the view simultaneously called
`appState.completeOnboarding(user:)`, which flipped the root to the main tabs. The done step —
**and the invite code on it** — flashed past unread, so a new user could never learn the code
needed to invite their partner. The done step now has its own explicit continue button.

### App Store blockers cleared

- **`Assets.xcassets`** with a 1024×1024 opaque `AppIcon` rasterised from `brand/app-icon.svg`
  (the "two figures with a coral heart" metaphor, which previously appeared nowhere in the app)
  and a `LaunchBackground` colour set. Without an icon, `CFBundleIconName` is never written and
  upload fails with `ITMS-90713` — a guaranteed rejection.
- **`PrivacyInfo.xcprivacy`** declaring `NSPrivacyAccessedAPICategoryUserDefaults` (`CA92.1`)
  and the four collected data types.
- **Apple's `SignInWithAppleButton`** replacing a custom capsule with a generic SF Symbol.
- **`UIBackgroundModes: remote-notification` removed** — declared but never implemented, an
  explicit Guideline 2.5.4 rejection.
- **`.xcodeproj` no longer copied into the app bundle** (`sources: - path: .` swept up the
  generated project).
- **Bundle ID `app.middleground.MiddleGround` registered** (team `9U3ZSABZG7`) with
  `APPLE_ID_AUTH` + `PUSH_NOTIFICATIONS`. Note the capability call reported success while
  silently not applying — Sign in with Apple needs a consent settings payload — so it was
  verified by re-querying rather than trusting the response.

### Verification

| Gate | Result |
|---|---|
| Package unit tests | 40 passed, 0 warnings |
| Hermetic UI walkthrough (`WalkthroughUITests`, mock mode) | 9 passed, with screenshots |
| **Two-device E2E against real Firebase** | **5/5 steps passed** |
| `swiftlint --strict` | 0 violations |
| Firestore rules, live | 4 unauthenticated probes all `403 PERMISSION_DENIED` |

The two-device run (`Scripts/two-device-e2e.sh`) proves the whole loop: device A creates a
relationship and shows its invite code → device B joins with it → B's compose picker shows A's
**name** → B sends a request → **A receives it live, untouched** → A accepts and earns +25 XP →
the Activities tab reflects it.

---

## Round 4 — legal, roles, and design fidelity

### The creator could answer their own request

Nothing validated the responder at any layer — model, service, view model, view, or security
rules. A could create a request for B, accept it, close the decision alone, and take the XP;
B simply lost the buttons. Now enforced at **four** layers so a modified client cannot bypass it:

- `Request.canRespond(as:)` / `isAwaitingResponse(for:)` / `canCancel(as:)`, with
  `addResponse` throwing `RequestError.notAllowedToRespond` rather than silently accepting.
- `RequestService.respond` rejects before writing, and gained `cancel(_:by:)`.
- The feed passes `onRespond: nil` for requests you may not answer (it was always non-nil), and
  the detail screen shows **"Waiting for <name>"** plus **Cancel request** to the creator.
- `firestore.rules` now requires `uid() in resource.data.recipientIDs` for updates, and pins
  `recipientIDs` immutable. Deployed and exercised by the two-device run.

Saving was ungated entirely — it could flip an already-accepted request to `.saved`, destroying
the state with no way back. It now follows the same rule.

### Cross-account data leak

`CachedRequestRepository.fetchLocal()` fetched every cached row with no user predicate, and
`merge` never deletes — so signing out and in as someone else on the same device showed the
previous user's requests. Reads are now scoped to the participant, and `LocalStore.purgeAll()`
runs on sign-out and on account deletion.

### Other role and flow fixes

| Was | Now |
|---|---|
| A user who quit mid-onboarding had **no path to ever pair** — relationships could only be created inside onboarding, which an authenticated user never sees again | Profile shows a Connect section (create a group / join with a code) whenever you have none |
| An unpaired owner got a permanently disabled "Send Now" in Spontaneous with nothing explaining why | Same guidance the compose sheet already had |
| Spontaneous send failures and account-deletion failures were **silent** — both view models set `errorMessage`, neither view read it | Both surface an alert |
| One failed response replaced the whole feed with an error card | The error only takes over when there is nothing to show |
| Tapping a greyed calendar day silently jumped the month; selecting a day only moved a highlight | Month is tracked independently, and the list narrows to the selected day |
| Expiry picker opened unselected (default 20, options 15/30/60/120) | Defaults to 30 |
| `.reschedule` was the only advertised response with **no trigger anywhere** | Built: a fourth response action opening a date picker. All six types are now reachable |

### Legal (App Review blocker)

`middleground.app` served the same "Coming Soon" page for every path, so all three in-app legal
links were dead. `docs/legal/` now contains a Privacy Policy, Terms and Support page written
from what the app actually does — the data table is derived from `PrivacyInfo.xcprivacy` and the
real Firestore paths, not boilerplate. `build.py` renders them to brand-styled, dependency-free
HTML ready to publish; the Markdown stays the source of truth.

The policy deliberately does **not** claim full erasure while `onUserDeleted` is undeployed —
it states that the account and device data go immediately and shared records follow when the
server-side purge runs.

### Design

- **Dark mode was broken in a way only a device shows.** `MGShadow` derived from
  `MGColors.slate`, which inverts to near-white — every card shadow was a glow. Added
  `MGColors.shadow` (true black in dark), `onAccent` for the 8 hardcoded whites that dropped to
  ~2.9:1 on lifted accents, and per-status `badgeForeground` tones (badges painted text in the
  same hue as their 12% fill, ~2.3:1). The scrim and the Sign in with Apple button now adapt.
- **The brand mark finally appears in the app.** `LogoMark` draws the two-figures-and-a-heart
  metaphor as Shapes — crisp at any size, adaptive, zero bundle cost — replacing the lone SF
  `heart.fill` on the splash and welcome screens.
- **Headings were pure black/white, not brand slate**: `.mgFont` set only the font and the
  colour-applying helpers had zero callers. The brand foreground is now part of `.mgFont`.
- `MGRadius` was a full step below the brand scale (md 16, lg 24, xl 32) and shadow radii ~2×
  too soft; both corrected against `design-system.md`, and `mgCard()` adds the spec's hairline.
- `GamificationCard` follows the spec's label → icon → value+unit order with a neutral unit
  (the accent colour made "days" read as a link), the Activities tab no longer renders a flame
  icon *and* a flame emoji, and "Great job!" no longer appears at a score of zero.
- `CelebrationView` bursts radially from the real view centre with a stagger and honours Reduce
  Motion; it previously fired from a hardcoded `CGPoint(x: 200, y: 300)`.
- Empty states added to Achievements and Activity.
- **`brand/design-system.md` now documents the shipped SF Pro Rounded / SF Pro faces** instead
  of specifying Poppins + Inter, which were never vendored — the spec no longer contradicts the
  product, and the note records how to swap them in later without touching a call site.

### Verification

| Gate | Result |
|---|---|
| Unit tests | **51 passed** (was 40) — role matrix, cancel rules, response mapping |
| UI walkthrough | **12 passed** (was 9) — including creator-sees-no-actions, waiting state, cancel confirmation |
| Two-device E2E vs real Firebase | **5/5** with the tightened rules deployed |
| `swiftlint --strict` | 0 violations |
| Dark mode | Verified on device, screenshots captured |

---

## Round 5 — admin panel and product tracking

Built at your direction after I flagged that it conflicts with the published privacy promises.
The conflict was real, so the policy was rewritten as part of this change rather than left to
contradict the product.

### Admin access is server-enforced, not a client flag

The panel ships inside a public binary, so a client-side `isAdmin` boolean would be worthless.
Admin status is a Firebase **custom claim**:

- `Scripts/grant-admin.mjs <email> [--revoke] | --list` sets it via the Identity Toolkit using
  the existing `firebase` CLI session — no service-account key needed.
- `AuthService.isAdmin()` reads it from the ID token (`forcingRefresh`, so a just-granted claim
  applies on relaunch). `AppState.isAdmin` drives whether the tab is rendered.
- **`firestore.rules` checks the same claim.** That is the actual enforcement — the UI gate is
  convenience. Verified against the live backend below.

### Audit trail — append-only by design

`admin_audit/{id}` records every admin view of user data (`adminID`, action, target, timestamp).
Rules permit `create` and `read` for admins and **forbid `update` and `delete` outright**, for
anyone. An audit log an admin can edit or erase is not an audit log. Non-admins cannot read it.

### Tracking

| Layer | What it gives |
|---|---|
| Aggregation queries | Users, groups, paired/unpaired, activation rate, requests by status and category — counted server-side without reading anyone's content |
| `events` collection | `signed_up`, `onboarding_completed`, `relationship_created`, `invite_redeemed`, `request_created`, `request_responded`, `request_cancelled`. Emitted from the service choke points, fire-and-forget so analytics can never fail a user action. A user may write only events attributed to themselves, and cannot read any |
| `gamification/{uid}` | XP, streak and achievements mirrored server-side. Also a genuine user fix: progress previously lived only in `UserDefaults` and was lost on device change |

### The panel — `Features/Admin/`

Overview (metrics + breakdowns), Users (searchable, with level/XP), User detail (their
relationships, requests **with content**, and event timeline — writes an audit entry on open),
Requests browser, Events feed, and the Audit trail itself. Built from the existing design
system, so it matches the app.

### Privacy policy rewritten

The published text said *"We do not track you… no analytics SDKs"* and *"Your requests are
visible only to you and the person you paired with."* Both would have become false. Now:

- States plainly that usage events are recorded, and that they capture the action, not the words
  a user wrote.
- States that authorised staff can access account records and content for support, safety and
  debugging; that the permission is server-side and cannot be obtained by modifying the app;
  that every access is logged to an append-only trail; and that a user can ask what that log
  shows about them.
- New data categories added to the table, and `PrivacyInfo.xcprivacy` declares
  `NSPrivacyCollectedDataTypeProductInteraction` so the App Store answers match.

### Verified against the live backend

Not just the UI — the rules themselves, with real tokens:

| Check | Result |
|---|---|
| Non-admin lists `users` / `events` / `admin_audit` | **403 denied** (all three) |
| Non-admin forges an audit entry | **403 denied** |
| User writes an event attributed to someone else | **403 denied** |
| Admin token carries `admin: true` | confirmed by decoding the JWT |
| Admin lists `users` / `requests` / `events` / `admin_audit` | **200 allowed** (all four) |
| Admin appends an audit entry | **200 allowed** |

Plus 51 unit tests, 12 UI tests (including "the Admin tab must not appear without the claim"),
17 new emulator rules cases, and `swiftlint --strict` clean.

A bug the tests caught: `FirestoreEventRepository` held `Firestore.firestore()` in a stored
property, so merely *constructing* it required `FirebaseApp.configure()` — the same shape as the
original launch crash. All three new repositories now resolve the handle lazily.

---

## Round 6 — ship readiness

A sweep for what stood between the app and an App Store submission, rather than between it and
compiling. Every claim below was verified against source before being acted on.

### Rejection risks that were real

1. **`ProfileView` never rendered `errorMessage`.** The view model set it for create-group,
   join-group, sign-out and delete-account; the view had one alert, for delete confirmation, and
   no binding to it. A wrong invite code stopped the spinner and did nothing else — on the exact
   flow App Review would be asked to use. Now bound with the same alert pattern as
   `OnboardingView`.
2. **No way to leave a group, report content, or block anyone.** `allow delete: if false` on
   relationships and nothing calling `removeParticipant` meant the only escape from an abusive
   partner was deleting your entire account — an App Review guideline 1.2 gap and an obvious
   product hole. Added `RelationshipService.leave`, a `reports` collection with an in-app Report
   action, and a Reports queue in the admin panel.
3. **Invite codes were permanent and single-use.** `isRedeemingInvite` requires
   `participantIDs.size() == 1`, so a code dies the moment it is redeemed — which would silently
   break a rejection/resubmit cycle. Codes can now be regenerated from Profile, and
   `Scripts/seed-review-data.mjs` mints several for the review notes.
4. **Account deletion did not delete data.** `onUserDeleted` cannot run on the Spark plan, so
   deletion removed the auth record and left every document. `AccountDataPurger` now performs
   the erasure client-side before the auth account goes, with the function kept as the durable
   backstop.
5. **`aps-environment` was hardcoded to `development`** with a comment claiming Xcode rewrites it
   for release — true only for Xcode-managed export. Split into per-configuration entitlements.
6. **`PrivacyInfo.xcprivacy` omitted Email**, which `SignInWithAppleManager` requests and the
   policy says is stored. Crash data added alongside it for Crashlytics.
7. **A missing composite index made an admin feature silently dead.**
   `events(forUser:)` needs `(userID, at DESC)`; `AdminViewModel` wraps the call in `try?`, so
   the user-detail Activity section always reported "No events recorded" rather than erroring.

### Two bugs introduced and caught here

- **`didSet` clamping recursed infinitely under `@Observable`.** The macro rewrites a stored
  property into a computed one, so assigning inside its own `didSet` re-enters the setter
  instead of being suppressed as plain Swift would. The test process died with SIGSEGV — a
  stack of `title.setter → _title.didset` repeated to overflow. Rewritten as computed
  properties over private storage. This is worth remembering: `didSet` that reassigns itself is
  not safe on an `@Observable` type.
- **XcodeGen's `entitlements:` block silently overrode per-configuration
  `CODE_SIGN_ENTITLEMENTS`**, so the first attempt at the fix above pointed *both* Debug and
  Release at the development file — the exact bug the split existed to prevent. The block was
  removed and both files are now committed and hand-maintained.

### Verified

- 65 unit tests (was 45 discoverable before this round), `swiftlint --strict` clean across 94
  files, Release configuration compiled for the first time.
- **64/64 Firestore rules tests pass against the emulator.** These had never been executed
  locally — a JDK was missing, and `npm test` (`node --test test/`) additionally died with
  MODULE_NOT_FOUND on Node 26, which resolves a bare directory as a module path. Both fixed.
- Legal pages live: `/privacy`, `/terms`, `/support` each return 200 with distinct real titles,
  and a nonsense path returns 404 — the previous host answered every path with the same
  "Coming Soon" placeholder.
- Rules and indexes deployed, including the two indexes the code needed and the project did not
  have.

### Archive: builds, but is not distributable

The archive had never been run. It failed first because the App ID
`app.middleground.MiddleGround` had **no capabilities enabled at all** — not Push, not Sign in
with Apple — so the provisioning profile could not cover the entitlements. Both were attached
via the App Store Connect API and the archive then succeeded.

It is still not an uploadable artifact: the machine has only an *Apple Development* certificate,
so automatic signing falls back to the development team profile and the archive comes out with
`get-task-allow: true` and `aps-environment: development` — the latter overriding the Release
entitlements file, because the profile type constrains the entitlement regardless of what the
file declares. An Apple Distribution certificate is needed, and creating one requires the
developer account.

Worth noting for anyone reading the entitlements comment: declaring `production` there is
necessary but not sufficient. The distribution *profile* is what makes it real.

### One thing that could not be deployed

A TTL policy on `events.at` requires Blaze; the `fieldOverride` returns HTTP 403 and fails the
entire `firebase deploy --only firestore`. It has been removed from `firestore.indexes.json`
with a comment explaining how to restore it. The published privacy policy briefly claimed 90-day
automatic expiry — that sentence was corrected before it could be untrue in production.

---

## Still outstanding

1. **Sign in with Apple is unexercised.** Simulators have no Apple ID (`AuthorizationError
   1000`), so the real SIWA path — and `revokeToken` during account deletion — needs one run on
   a physical device. It is the only sign-in method Release ships, and no test can cover it.
2. **Push notifications unexercised.** Cloud Functions need the Blaze plan to deploy, and APNs
   needs a key uploaded to Firebase. Account deletion no longer depends on them; delivery does.
3. **App Check enforcement is off.** The provider is wired, but App Attest cannot be exercised
   on a simulator and enabling enforcement unverified would lock every client out of Firestore.
4. **No App Store Connect record yet** — the API is read-only for app creation, so it has to be
   made in the web UI.
5. **No localization** — ~120 hardcoded English strings, zero `LocalizedStringKey`.
6. **`SWIFT_STRICT_CONCURRENCY: complete` is effectively a no-op.** It is set at project level,
   which reaches only the 12-line app shell; all 79 sources are in the SPM package, which
   declares no `swiftSettings`.
7. **Design tokens only partially adopted.** `MGSpacing`/`MGRadius` exist but call sites still
   inline most padding and corner radii.
8. **Spontaneous-request expiry is still decorative** — stored in `proposedTime`, and nothing
   expires anything, so a request set to "expire in 30 minutes" appears in Calendar as an event
   30 minutes from now.
9. **`needsSync` is written but never read.** No reconciliation on reconnect, no backoff, no
   retry — the field implies a sync engine that does not exist.
