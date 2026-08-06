# Verification log

Every line here is a measurement, not a reading. The distinction matters in this codebase: three
separate bugs this week were in code that looked correct, was commented as correct, and had never
run — the events TTL that deleted analytics daily, the APNs callback declared on a class UIKit
never calls, and the notification tap that aborted the app on every tap.

A passing test is not evidence a feature works. Every UI suite except the two named below runs
under `-MGMockMode`, which substitutes in-memory repositories and never reaches Firestore, the
security rules, or a Cloud Function.

Generated during the audit of **2026-08-06**. Reproduce with the commands in each section.

---

## Cloud Functions

Execution counts from Cloud Monitoring (`cloudfunctions.googleapis.com/function/execution_count`),
30-day window. "Tested" means a test invokes the handler itself, not a module it calls.

| Function | Ran in production | Tested | Notes |
|---|---|---|---|
| `notifyNewRequest` | ✅ 47 | ✅ | |
| `notifyRequestResponse` | ✅ 40 | ✅ | includes per-recipient timezone rendering |
| `notifyPlanCancelled` | ✅ 1 | ✅ | |
| `notifyPlanMessage` | ✅ 1 | ✅ | **first execution ever 2026-08-06T15:35:23Z**, from the live pass |
| `promptForAttendance` | ✅ 111 | ✅ | hourly |
| `remindBeforePlan` | ✅ 24 | ✅ | hourly |
| `weeklyNudge` | ✅ 1 | ✅ | **first execution ever 2026-08-06T14:00Z** |
| `purgeStaleEvents` | ✅ 1 | ✅ | **first execution 2026-08-06T18:46:03Z**, triggered manually; nothing to purge, nothing lost |
| `dailyDigest` | ✅ 3 | ✅ | paused in Cloud Scheduler by request |
| `alertOnSignup` | ✅ 12 | ✅ | 1 error, 2026-07-30, no log retained |
| `alertOnPairing` | ✅ 11 | ✅ | |
| `alertOnReport` | ✅ 1 | ✅ | |
| `alertOnAccountDeleted` | ✅ 12 | ✅ | |
| `onUserDeleted` | ✅ 11 | ✅ | 1st-gen; no 2nd-gen auth-delete trigger exists |

**Before this audit, none of the fourteen had a test.** The 210 green "functions and rules" tests
covered `push.js`, `time.js`, `paging.js` and `firestore.rules` — the pure modules and the
permission layer. Every trigger body shipped unexecuted by CI. Now 235 tests.

`weeklyNudge`'s first run logged `Nudged 2 of 6 user(s)` with an empty status — the paging and
bounded fan-out written the same morning, working on first contact with real Firestore.

    node Scripts/check-push-readiness.mjs
    npx firebase-tools emulators:exec --only firestore "cd CloudFunctions && npm test"

---

## Roles

Driven by `Scripts/two-device-e2e.sh` across two simulators against **real** Firebase — no
`-MGMockMode`, real security rules, real Firestore.

| Role | Exercised by | Result |
|---|---|---|
| Signed-out → onboarded | both devices, full onboarding | ✅ |
| Group owner | A creates a relationship, publishes invite code `VUKMQ2` | ✅ |
| Joiner | B redeems that code | ✅ |
| Plan creator | B sends a request to its now-paired partner | ✅ |
| Recipient / turn-taking | A receives it live via the snapshot listener, accepts | ✅ |
| Reward loop | A's Activities tab reflects the XP earned | ✅ |

Live sync is the notable one: the request arrives on A with no interaction at all.

    MG_E2E_OUT=/tmp/e2e-audit ./Scripts/two-device-e2e.sh

**Not covered, by choice:** the admin surface (venues, reports, audit trail) and the
deletion/leaving cascade. `reports` and `venues` hold zero production documents, so admin remains
unverified. `onUserDeleted` has run 11 times, so deletion is at least live.

---

## Features reaching the backend

Zero-document collections were the audit's central finding: four of these five had **passing UI
tests** that never touch Firestore. All five have now been exercised by the real app, through the
real security rules, and the evidence is the document — not the test result.

| Feature | Collection | Before | After | Evidence |
|---|---|---|---|---|
| Plan chat | `messages` | ⬜ 0 | ✅ 5 | first message ever; fired `notifyPlanMessage` |
| Location sharing | `locations` | ⬜ 0 | ✅ 2 | written by the app, through the real rules |
| Shared availability | `availability` | ⬜ 0 | ✅ 2 | one per group — writing to all of them is intended |
| Read receipts | `reads` | ⬜ 0 | ✅ 3 | |
| Typing indicator | `presence` | ⬜ 0 | ➖ n/a | ephemeral: `stopTyping` deletes it on send |
| Plans | `requests` | ✅ 12 | ✅ 14 | |
| Pairing | `relationships` | ✅ 5 | ✅ 6 | |
| Analytics | `events` | ✅ 1 | ✅ 8 | |
| Push registration | `user_tokens` | ✅ 1 | ✅ 1 | |

`notifyPlanMessage` executed for the first time in the project's history at **2026-08-06T15:35:23Z**,
triggered by that first message. It is the clearest single proof that
app → Firestore subcollection → Cloud Function works end to end.

**Typing presence cannot be verified by counting.** `stopTyping` deletes the document and is called
on send and on leaving the screen, so an empty collection is the correct resting state. Reported
as `~` rather than a failure.

**Location sharing is repeatable.** It needs an accepted plan timed within an hour before and four
hours after now, which the pairing run does not produce. `Scripts/seed-location-fixture.mjs`
writes a **new** document for the purpose — re-dating an existing plan does not work, because
`CachedRequestRepository.merge` only overwrites a local row when the remote copy is strictly
newer, so the client keeps serving its own copy. Two further things had to be true and were each
found by being wrong first: the simulator needs a *simulated location* (without one CoreLocation
fails and the test reports "location was never shared", which points at the wrong thing), and the
Springboard permission alert needs an interruption monitor.

All of it is now one command:

    ./Scripts/run-live-features.sh

---

## Push, end to end

Proven on physical hardware on 2026-08-06, for the first time in the project's history.

| Step | Evidence |
|---|---|
| Device registers an FCM token | ✅ 1 device in `user_tokens`, 142-char token |
| Each of six push types delivered | ✅ all accepted by FCM and received |
| Tapping a notification | ✅ no longer crashes (was `SIGABRT` on every tap) |
| Deep link destinations | ✅ tapping opened the named plan, not just the app |

Deep links stayed unproven for a simple reason: every payload carried a mock fixture id like
`req_6`, which exists only in mock mode, so on a real account the tap correctly resolved to nothing
and stopped at Home. `send-test-push.mjs --request <id>` now targets a real plan; sending
`demo-negotiating` and tapping it opened "Movie night Saturday?".

The tap crash was diagnosed from three `.ips` reports symbolicated against a matching dSYM, not
inferred: `@objc closure #1 in NotificationService.userNotificationCenter(_:didReceive:)` on queue
`com.apple.root.user-initiated-qos.cooperative`, dying in a UIKit main-thread assertion.

---

## Bugs found and fixed during this audit

1. **Opening any plan silently took a GPS fix.** `LocationService` is registered unscoped, so
   `RequestDetailView.init` built a new one per plan opened; CoreLocation calls the authorization
   delegate on assignment, and the handler called `requestLocation()` unconditionally. Contradicted
   the file's own "one fix, on demand" comment and the Coarse Location answer for App Review.
2. **`pagedDocs` looped forever if its cursor stalled** — found by mutation testing, which hung
   instead of failing. In production that is an unbounded read loop until the function is killed.
3. **`two-device-e2e.sh` never created `MG_E2E_OUT`**, so a run with an explicit output directory
   died before its first test.
4. **A test run reported `** TEST SUCCEEDED **` having executed nothing.** The project is generated
   by XcodeGen, which collects sources by directory glob at generation time, so test files added
   since the last generate were absent and `-only-testing:` matched nothing — in 0.001 seconds,
   exit code 0. Caught only because the verdict was read from Firestore rather than from the test
   result. The harness now regenerates the project first.

Two of my own test assertions were also wrong in the direction of false confidence: one matched
text present *before* the action it was meant to verify, and one assumed a clean starting state on
an account that keeps whatever the last run left. Both were caught by the documents disagreeing
with the checkmarks.

---

---

## Infrastructure and configuration

Checked because the repo saying something and production doing it are different claims — an
index file that had never deployed was a real bug here once.

| Check | Result |
|---|---|
| Deployed security rules vs repo | ✅ identical (sha256 match), released 2026-08-05 |
| Composite indexes | ✅ 10 READY, and repo ↔ production now agree exactly |
| TTL policies | ✅ active on `events`, `locations`, `presence` |
| Secrets in git | ✅ none tracked; `GoogleService-Info.plist` and `.env` both ignored |
| Legal pages, AASA, `/join/*` | ✅ all 200; AASA serves `application/json` with the right app ID |
| App Check enforcement | ⚠️ **off — and must stay off**, see below |

**Three dead indexes were deleted.** `requests` carried composite indexes on `recipientIDs` and
`creatorID` — the query shape from before turn-taking. Nothing in the app, the functions or the
scripts queries those fields any more; everything moved to `allParticipantIDs`. They were absent
from `firestore.indexes.json`, so the repo was not the source of truth, and every write to a
request was updating three indexes that served no query.

**App Check must not be enforced yet.** Enforcement is `UNSPECIFIED` (off) for Firestore and
Storage, which matches the intent documented in `AppDelegate`. What is new is the evidence: across
all three App Check metrics there are **zero verifications in 14 days**, and **zero debug tokens**
are registered. App Attest *is* configured for the iOS app (1-hour TTL), and the entitlement
shipped today — but nothing has ever passed verification, including the physical device. Turning
enforcement on now would lock every client out of Firestore, including the build in App Review.
The simulator would fail too: it uses `AppCheckDebugProvider`, whose token is rejected while no
debug token is registered.

---

## Account deletion

Guideline 5.1.1(v). `onUserDeleted` has run 11 times in production, so the cascade is live.

| Data | Before | After |
|---|---|---|
| `users`, `user_tokens`, `gamification`, `notification_settings` | ✅ deleted | ✅ |
| `invites`, `relationships`, `requests`, `events`, `messages` | ✅ deleted | ✅ |
| `availability` (blocked days) | ❌ **survived, permanently — no TTL** | ✅ deleted |
| `locations` (coordinates) | ❌ **survived until TTL** | ✅ deleted |
| `reads`, `presence` | ❌ survived | ✅ deleted |
| `reports` | retained deliberately — a safety record about somebody else | unchanged |
| `plan_outcomes`, `booking_intents` | retained — anonymous by contract, no user or plan id | unchanged |

Four subcollections keyed by uid were never swept. No collection-group query can reach them,
because the uid is the document id rather than a field — which is why nothing caught it. Both
existing purge loops already visited the right parents, so the fix was four deletes inside loops
that were already running. Two tests cover it; both fail if the sweeps are removed.

---

## Admin surface

Every admin test runs under `-MGMockMode`, so the whole surface was UI-only. Production showed
exactly that shape: 17 `admin_audit` rows from viewing requests, and nothing in `venues` or
`reports`.

| Path | Evidence |
|---|---|
| Admin read | ✅ 17 `admin_audit` entries (16 `viewed_request`, 1 `verification`) |
| Admin write | ✅ a venue created through the real rules with a real custom claim |
| Report moderation | ⬜ still unexercised — `reports` is empty and filing one is a user action |

The write was proven by granting the claim to the test account temporarily. Both the test venue
and the claim were removed afterwards: a venue shows up as a suggestion when somebody fills in
"Where?", so a fake one is not harmless clutter.

---

---

## Second-pass audit

Dimensions the first two passes did not touch.

| Area | Result |
|---|---|
| Concurrency (the crash class) | ✅ only two `NotificationCenter.post` sites, both now `@MainActor` |
| Snapshot listeners | ✅ all five remove on stream termination — no leaks |
| Auth ↔ Firestore drift | ✅ 6 accounts, 6 user documents, every uid has both |
| Referential integrity | ⚠️ two demo plans reference a user who no longer exists |
| Dependency vulnerabilities | ⚠️ 7 moderate, all transitive — **do not fix on this Mac** |
| CI | ✅ green on main; ⚠️ **25 commits unpushed**, so it has seen none of this work |
| Accessibility: control labels | ✅ no icon-only control lacks a label |
| Accessibility: Dynamic Type | ✅ every text path scales; only decorative emoji are fixed |

**Two demo plans have a dangling participant.** `demo-negotiating` and `demo-waiting-on-them`
list `m9iBqmtR3gQTKqoTLnAKfhzhJSN2`, who exists in neither Firebase Auth nor `users`. The app
degrades gracefully — `name(for:)` falls back to "Someone" rather than showing a raw id — so this
is cosmetic, but it is real production data contradicting itself. `Scripts/check-data-integrity.mjs`
is what found it and will find the next one. Re-seeding the demo data
(`seed-demo-partner.mjs --clean`, then seed again) is the clean repair.

**The dependency warnings must not be fixed from this machine.** All seven trace to one `uuid`
advisory pulled in transitively through `teeny-request → retry-request → gaxios →
@google-cloud/storage`. Running `npm audit fix` here would resolve the tree for darwin only and
rewrite `package-lock.json` with deletions of every non-darwin optional binary, breaking CI on
`ubuntu-latest`. Fix it from the Windows machine or in CI, and never commit a lockfile diff that
is only deletions.

**Nothing from this work has been through CI.** The last run was 2026-08-05 on `main`; every
commit since is local. The new function tests would be picked up (`test/*.test.js` matches all
five files, and `test/support/` correctly is not), and no dependency was added — so the suite
should pass. It simply has not run anywhere but here.


---

## Third-pass audit: colour contrast

The app has shipped two contrast failures, from opposite causes. Black on indigo, because a
`foregroundStyle` applied after `mgFont` was silently dropped — the colour was *wrong*. And white
on teal at **2.49:1**, where the colour was exactly right and the surface could not carry it.
Neither is visible in review and neither breaks a screenshot test: both render a perfectly
composed screen that happens to be hard to read.

Every pair the app actually draws, measured in both schemes (WCAG 2.1: 4.5 body, 3.0 large/icons):

| Pair | Light | Dark | |
|---|---|---|---|
| `onAccent` on `indigo` — 8 buttons | 4.47:1 | 4.90:1 | ✅ passes for bold/large |
| `onAccent` on `teal` — "Yes, it did" | **2.49:1** → 5.47:1 | 7.86:1 | ✅ **fixed** |
| `onAccent` on `coral` — streak strip | **2.16:1** → 6.76:1 | **2.16:1** → 7.74:1 | ✅ **fixed** |
| `slate` on `sand` / `surface` / `warm100` | 9.0–10.4:1 | 7.2–14.0:1 | ✅ |
| `warm600` on `surface` | 4.83:1 | 6.97:1 | ✅ |
| `teal` as a status colour on `sand` | **2.30:1** → 5.06:1 | 7.86:1 | ✅ **fixed** |
| `indigo` as a link on `surface` | 4.13:1 | 4.90:1 | ✅ icons/large |

**Light-mode teal moved from `#14B8A6` (teal-500) to `#0F766E` (teal-700).** It is the only accent
used behind text, and it also reads as a status tint and a location pin, where 2.30:1 was below
even the floor for meaningful icons. Dark mode is untouched — `#2DD4BF` behind `onAccent` was
already 7.86:1.

`ColourContrastTests` resolves the palette in both schemes and computes the ratios. Reverting teal
makes three of its assertions fail with exactly the numbers above, so it is a regression test
rather than a decoration.

**A second defect, and a lesson about the tooling.** The streak strip drew white bold text on
coral at 2.16:1. It hid from the first scan because both the text colour *and* the fill are written
as ternaries, so a regex looking for `foregroundStyle(MGColors.` and `.background(MGColors.` matched
neither. Rewriting the scan to read every `MGColors` token on a line — rather than assuming the
syntax shape — found it. Three separate false negatives came from the same assumption today, and
one false positive claimed 1.08:1 on a pair the app never renders. Every candidate here was read in
the source before being called a defect.

**The first fix for it was wrong, and the test caught that.** `slate` on coral is 4.79:1 in light
and **1.81:1 in dark**, because slate flips to near-white while coral stays pale in both schemes.
Ink that flips is wrong in one scheme or the other, which is why `onLightAccent` exists — a fixed
dark ink for accents that do not flip, at 6.76:1 and 7.74:1. That is the argument for asserting
both schemes rather than the one on screen.

**Still open, and a design decision rather than a defect:** in light mode the remaining accents are
below 3:1 on the page background — coral 2.00:1, sunshine 1.42:1, lavender 2.52:1, sky 1.54:1.
That is fine behind dark text or in a confetti burst, and not fine for anything a reader must make
out. Twelve sites use them as foreground. The test records the numbers and deliberately does not
fail on them; darkening the palette changes how the app looks, which is yours to decide.


## Still open

- One `alertOnSignup` error from 2026-07-30 with no surviving log at any severity.
- App Attest has never produced a verified request. Enforcement stays off until it does.
- Report moderation, which needs a real report to work through.
- Two demo plans with a dangling participant; re-seeding the demo data clears them.
- Seven moderate transitive dependency advisories, to be fixed away from this Mac.
- 27 commits that CI has never seen.
- Four decorative accents below 3:1 in light mode, used as foreground in 12 places.
- The darker teal is computed but not yet eyeballed on a device.
- Deep-link destinations, which need a real plan between two real accounts.
- 1.0 is in review with build `202608021918`, which predates every fix this week. Push does not
  work in it at all. Fixes land in 1.0.1.
- App Privacy → **Coarse Location**, collected, **linked** to the user, App Functionality, not
  tracking. Must be entered by hand; the App Store Connect API does not expose it.
