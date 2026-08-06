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

## Still open

- One `alertOnSignup` error from 2026-07-30 with no surviving log.
- Deep-link destinations, which need a real plan between two real accounts.
- 1.0 is in review with build `202608021918`, which predates every fix this week. Push does not
  work in it at all. Fixes land in 1.0.1.
- App Privacy → **Coarse Location**, collected, **linked** to the user, App Functionality, not
  tracking. Must be entered by hand; the App Store Connect API does not expose it.
