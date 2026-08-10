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


## 2026-08-08 — correctness pass

Five defects, none of which failed a test. Each was found by auditing a claim rather than by
running the suite, which is the point worth recording.

| Found | Evidence it is real |
|---|---|
| A settled plan paid out again after a reinstall | `settledPlanIDs` absent from `GamificationStatsDTO`; the guard restored empty. Mutation-checked: removing the fix fails `testTheWireFormatCarriesEverythingAReinstallNeeds` |
| The first test written for it proved nothing | It went through `MockGamificationRepository`, which keeps the struct in memory and never converts — it passed with the fix removed |
| `seats` dropped by the relationship cache | Third field caught this way; survived the `name` fix in `9ff2d97` |
| Cache and server disagreed on legacy groups | The entity passed a missing value through and `Relationship.init` read it as the *type's* limit — eight, where the rules enforce two |
| `invite_shared` fired from 1 share button of 8 | It is the funnel denominator, so reported pairing conversion was far too high |
| `invitedBy` written since pairing shipped, read by nothing | Now folded out of events the admin panel already loads |
| A joiner could read others' live location, nobody told | `inPlan()` is membership of `allParticipantIDs`, which `isJoiningPlan` lets a code-holder add themselves to. No function reacted to the write |

Also corrected: Terms said groups hold two people (the code allows eight); the support page said XP
never leaves the device while the privacy policy said it is mirrored.

**Still unproven here:** the Firestore rules tests do not run on this Mac — the emulator needs Java,
which is not installed. CI is the only place they run. The rules themselves compile clean against
Firebase (`deploy-firestore-rules.mjs --dry-run`), which checks syntax and semantics but not
behaviour.

**Also worth knowing:** CI runs no UI tests. `xcodebuild -scheme MiddleGround test` is the SPM
package, and `MiddleGroundApp` is only ever built. All 104 UI tests are local-only. And three of the
five `RealBackendFeatureTests` skip when their fixture is missing, so a green run there is not
proof — `Scripts/verify-live-features.mjs` is the verdict.

---

## 2026-08-09 — a plan abroad, and what Apple will tell you

**MapKit supplies the time zone, but only on a search result.** A locally-built `MKMapItem` — one
constructed from a placemark you made yourself — returns `nil` for both `MKMapItem.timeZone` and
`MKPlacemark.timeZone`. A real `MKLocalSearch` near Barcelona returns `Europe/Madrid`. That is the
difference between the feature working and the field being permanently empty, it is not documented
anywhere obvious, and it is now asserted by `LookAroundProbeTests` rather than assumed — the same
reason the Look Around tier probe exists.

`Request.timeZoneID` is set from that, and everything on a plan abroad renders on the plan's clock:
the dates, the night count and a new line naming the hour there. Proven on a screenshot rather than
only in a test — the trip detail shows "6:21 PM Central European Time" under "Sep 4–8 · 4 nights".

Two mutations were tried and both were caught: `dateSummary` ignoring the plan's zone, and the
SwiftData entity dropping the field on the way through the cache.

**CI has now seen everything.** The PR runs Build & Test, SwiftLint and the Firestore rules tests
(the rules suite cannot run on this Mac at all — no emulator — so it is the only place the new
`immutable('timeZoneID')` branches are exercised). 474 unit tests, 91 Cloud Function tests outside
the emulator, 0 lint violations across 243 files.


## 2026-08-09 — closing the gaps

**The support address published in eleven places could not receive mail.** `support@middleground.app`
is named in the privacy policy, the terms, the support page, the site footer, the homepage and the
App Review notes. `dig` says `middleground.app` resolves to Squarespace — it is somebody else's
domain — and has **no MX records at all**. `seekmiddleground.com` had none either. So the address
Apple would use, the address the terms name for exercising data rights, and the address behind
"reports are reviewed within 24 hours" all pointed at a mailbox that does not exist. Every
occurrence now reads `support@seekmiddleground.com`, and CI fails if the old one comes back.
**This is not finished until Cloudflare Email Routing is switched on** — the address is correct and
still undeliverable until then.

**Somebody who quit onboarding early was "Guest" permanently.** `signInWithApple` saves the user
document at the *welcome* step and `isOnboarded` was `currentUser != nil`, so quitting before the
profile step left an account with no name. Onboarding was the **only** screen in the app that ever
wrote one, and Apple supplies a name on the first Sign in with Apple and never again — so there was
no way back, to yourself or to anybody in any group you later joined. Fixed twice over: an account
with no name resumes onboarding, and Profile can now set a name.

**`NotificationService.shared` made two of the most important types untestable.** Any type holding
it could not be constructed in the unit target: `UNUserNotificationCenter.current()` raises
`NSInternalInconsistencyException` when there is no bundle proxy, which kills the runner rather
than failing a test. That is why `AppState` and `ProfileViewModel` had no tests — not because
nobody tried. Guarded on whether the main bundle is an `.app`, so both are testable now.

**The join page shows the invite code.** It used to tell people to read six characters out of their
browser's address bar. The CSP permits exactly one script by SHA-256 hash — no `unsafe-inline`, no
host, no `'self'` — and `site/verify-join-page.py` recomputes the hash in CI, because a drifted
hash fails silently: the page renders, the fallback copy is there, and the code just quietly stops
appearing.

**Coral and sunshine were foreground colours at 2.00:1 and 1.42:1.** Thirteen views used them for
something a person had to make out — the saved heart, the report button, the streak flame, "you are
sharing your location", and the two warning triangles whose whole job is to be noticed. Darkening
them was not an option (they are also fills, under dark ink), so `coralText` and `sunshineText`
carry the light-mode-darkened variants at 5.82:1 and 4.65:1. Dark mode is untouched: pale coral on
a dark page was already 7.74:1.

**CI now runs UI tests and checks the website**, neither of which it had ever done.


## 2026-08-09 — the itinerary, and what a realistic fixture found

A trip can now say what is on which day: `requests/{id}/itinerary/{itemID}`, a subcollection for
the reason `messages` is one — a five-day trip with four people adding items is exactly the shape
that pushes a document towards the 1 MB ceiling. Days are **derived**, never stored, so an item
cannot end up filed under a day the trip no longer has; they are computed in the plan's own zone,
which is what `timeZoneID` was for. Items outside the dates are surfaced rather than dropped,
because moving a trip strands everything already arranged and hiding that loses work people did.

**Two defects came from the screenshot, not the tests.** The first fixture used
`Date().addingTimeInterval(86_400 * 26 + 3_600 * 11)` — eleven hours after *now*, not eleven
o'clock — so "Dinner at Bar Cañete" rendered at 10:38 AM in one run and 4:38 AM in another, and
every test passed both times because a time is a time. Fixed with `PreviewClock.trip(daysFromNow:
hour:)`.

Realistic hours then exposed a real one: **`nightCount` counted elapsed 24-hour periods**, so a
trip landing at 15:40 on the 4th and flying home at 11:00 on the 8th reported "3 nights" directly
under its own "Four nights, flights not booked yet." Nights are what a hotel counts, and a hotel
counts dates. Now measured between the days.

**CI's UI tests moved to a job of their own.** Bolted onto Build & Test they took it from twenty
minutes to fifty-eight, in series, for no reason — nothing there depends on the Release build. Run
alongside it, the wall clock is the slower of the two rather than their sum.


## 2026-08-09 — a colour the code asks for and the screen does not use

`mgFont(_:)` applies its own `foregroundStyle`, and SwiftUI resolves the **innermost** one — so

    Text("S").mgFont(.caption).foregroundStyle(MGColors.onLightAccent)

renders slate and discards the colour. `mgFont(_:color:)` exists for exactly this and says so in
its own doc comment. **161 sites use the broken spelling**, and two of them were real failures:

| | intended | shipped |
|---|---|---|
| Calendar selected day | white on indigo, 4.47:1 | slate on indigo, **2.32:1** |
| Streak pill, dark mode | 7.74:1 | near-white on pale coral, **1.81:1** |

The comment above the streak pill quotes 1.81:1 as the number it had avoided, while the code
produced it. The status badge was a third: legible on its 12% tint, but every status rendered
slate, and the colour *is* the information.

**None of this was findable from the tests.** `ColourContrastTests` checks the colour constants,
and the constants were correct — the view simply never used them. It was found by sampling the
pixels of a screenshot: `#334155` where `#1E293B` was asked for. An impression from a downscaled
image was wrong in both directions, first suggesting a failure that was not there and then missing
the one that was; the pixel values settled it.

Fixed in the three places where the colour carries meaning. **The remaining ~158 are `warm600`
rendering as slate** — secondary text looking primary. Legible, so not an accessibility failure,
but the app does not look as designed. The fix is mechanical; it changes the appearance of most
screens at once, so it is recorded here rather than done quietly.

**A red that was not a bug.** `test_20_creatorIsOfferedNoResponses` failed once in CI: it asserts
Accept is absent, and absence is indistinguishable from "the screen has not arrived yet" — so on a
slow runner it was checking the feed, where a request awaiting you carries its own Accept button.
`openPlan` now waits for the detail screen.


### The sweep, done

All 159 remaining sites rewritten to `mgFont(_:color:)` across 45 files, and a SwiftLint custom
rule (`mg_font_discards_colour`) added so the broken spelling cannot return. The rule was checked
against both shapes — the plain one and the `.fontWeight` interleaved one a naive regex misses —
by reintroducing each and watching it fail.

What changed on screen is worth stating, because it is the whole point: the status badge is teal
again rather than slate (the colour *is* the status), and the app has typographic hierarchy where
every secondary line previously rendered at the same weight as the headings it sat under.

Verified: 534 unit tests, 65 UI tests, 0 lint violations across 251 files.


## 2026-08-10 — Sign in with Apple, proven on hardware

Confirmed working on a physical device by Derek. It is the **only** production sign-in path —
`signInAsTestUser` is `#if DEBUG` and compiles out of Release — so until now the one thing every
real user must do first had never been done on real hardware by anyone.

Worth one more look on `202608101337`, and only because the gate around it moved today:
`AppState.checkAuthState` no longer treats "has a user" as onboarded, so an account with no name
now resumes the flow rather than landing on Home. That changes what happens *after* a first
sign-in, not the sign-in itself, and it is covered by `OnboardingRecoveryTests` in the simulator.


## 2026-08-10 — a device pass on `202608101337`

Confirmed by Derek on a physical device, on the build now in review:

- **Push arrives.** The important one. Push was proven on hardware on 6 August, but the build
  sitting in the review queue until today was `202608021918`, whose entitlement is
  `aps-environment: development` — push could not have worked in it for anybody. This is the first
  build carrying `production` that has been installed and had a notification land on it.
- **Deep links open where they should.** An invite link opens to joining with the code already
  filled in, which is the path the whole `/join/{code}` page exists to feed.
- **The darker teal reads correctly on a real screen**, not only as a computed ratio. That closes
  the last of the colour work — teal-700 was chosen to clear 3:1 on sand and 4.5:1 under white,
  and the numbers are now backed by somebody looking at it.

Not yet done on hardware: **a plan abroad**. The time zone is proven in the simulator, in the
rules tests and by a live MapKit probe, but no plan has been created by a person choosing a place
in another zone and read back with its own clock.


## 2026-08-10 — the recordings, brought up to the build in review

An audit of all eight capture suites found **zero** hits for "Barcelona", "trip", "itinerary" or
"energy". The newest full tour was six days old, the newest nearby tour three, the site shots nine,
and the App Store screenshot set did not exist on this machine at all. So the answer to "do we have
video of every action on the latest version" was no, and not marginally.

Re-recorded against the build now in review:

- **Full tour** — 66 screenshots, 8m22s. Eight new scenes: the trip range on the feed, nights and
  the time-zone line, the itinerary day by day, adding an item, "Over several days" in compose and
  the end-date picker, the group energy card, the join-by-code field, and the report menu and sheet.
  The last two long predate this week; the tour had only ever shown *issuing* a plan code, never
  redeeming one, and had never shown the report flow at all — which Guideline 1.2 requires.
- **Nearby tour** — 619s, 18,572 frames, all eight walkthrough clips split correctly (72–80s each).
  A previous run produced seven of eight, and an earlier one a 262-byte clip of nothing, so both
  were checked: clip sizes, per-clip durations, and a sampled frame showing the app rather than the
  home screen.

**Four harness faults, three of them found only by running it.** The one worth remembering:
`full-tour.sh` printed "the tour reported failures" and then **exited 0**. The first attempt aborted
eight scenes early — no report flow, no admin panel — and returned success. A tour that files a
truncated recording as evidence is worse than no tour. It now exits with its own verdict.

The others: the invite field was queried by its placeholder when its accessibility label differs,
so `typeText` threw and ended the run; the group energy section searched for the word "energy",
which appears nowhere on that card; and `record-tour.sh` printed the duration before computing it,
so every run ever recorded reported an empty value in its summary line.

**Not fixed, and worth stating:** there is still no coverage measurement anywhere in this repo —
no `-enableCodeCoverage`, no xccov, no percentage in any document. The substitute remains what it
has been: evidence that a path has actually run.


## 2026-08-10 — coverage, measured for the first time, and the two bugs it found

Coverage had never been measured in this repo: no `-enableCodeCoverage`, no xccov, no percentage
in any document. That was a deliberate position — "coverage would not have caught one bug found
this week" — and it is right about coverage as a *target*. It was wrong as a reason not to look.

The numbers:

| | |
|---|---|
| iOS, everything | **19.1%** |
| iOS, non-view logic | **44.2%** (132 files) |
| iOS, views | 0.3% (47 files — exercised by UI tests, which do not run in this measurement) |
| Cloud Functions | **94.9% line, 71.0% branch** |

The contrast is the finding. The backend logic is thoroughly tested; the iOS side is under half on
logic, and the gap is not evenly spread — it is concentrated in files nothing has ever executed.

**`SpontaneousRequestViewModel` came back at 0%: 111 lines of a user-facing feature no test had
ever run. It held two live bugs.**

1. **An arbitrary group's invite code.** `relationships.first { !$0.isPaired }?.inviteCode` — the
   exact line both `ProfileViewModel` and `CreateRequestViewModel` carry a comment explaining they
   fixed. With more than one unpaired group this screen offered a code for a group the person was
   not thinking about, and whoever redeemed it landed somewhere nobody chose. The third copy was
   simply missed, and nothing was watching it.
2. **A recipient picker that named people after their group.** `displayLabels` is keyed by
   *relationship* and describes the whole thing — "Sam and Priya" for a group of three — and each
   member was labelled with it. Two rows, the same name, in the picker whose only job is saying who
   you are asking. `displayLabels`' own comment warns about the mirror image of this mistake.

Both fixed, both mutation-checked: restoring either fails exactly the test written for it.

Coverage is now reported by CI as a notice and by `Scripts/coverage.sh` locally, which names every
non-view file with 40+ lines that no unit test has ever executed. **Deliberately not a threshold.**
A percentage that must not fall is a percentage people write tests to protect rather than to find
anything — and this repo has already been bitten by tests that passed for the wrong reason.

`RequestDetailViewModel+Reporting.swift` was the next 0% file, and it held two more — see below. The Firestore repositories are also 0% by design — they are only
exercised against the real backend, which is what `verify-live-features.mjs` is for.


## 2026-08-10 — the reporting path, and two more the same method found

`RequestDetailViewModel+Reporting.swift` was the largest non-view file still at 0%: 92 lines,
never executed, implementing the thing App Review guideline 1.2 is about. It held two defects.

**The report control was missing while the profile loaded.** `reportableParticipants` guarded on
`currentUser`, which waits on a Firestore fetch of the display name — while everything else on that
screen uses `currentUserID`, which is in memory. The view model already carries a comment
explaining this exact trap and why the response row was moved off `currentUser`:

> "for that half second the view believed it was nobody, so the response row was missing"

The report control was never moved. So on any slow connection, the one control guideline 1.2
requires was absent from the toolbar for the first moments of every plan.

**An abandoned choice survived into the next report.** `Cancel` on the sheet only dismisses it —
`reportedUserID` was never cleared — so opening the sheet again showed somebody already selected,
with Submit enabled, chosen during a different sitting. `beginReport()`'s own note says "guessing
is how a report lands on the wrong person"; a stale selection is a guess made by the last visit.
This one is not cosmetic: a report names a person, and filing one against somebody who was not
chosen is an accusation nobody made.

Both fixed, both mutation-checked — restoring either fails five tests between them.

Coverage after: non-view logic **45.1%** (was 44.2%), everything 19.5%. 556 unit tests.

That is four real bugs in two days from one method: measure, find a file nothing has executed,
read it, and check what it does against what its own comments say it should.


## Still open

- One `alertOnSignup` error from 2026-07-30 with no surviving log at any severity.
- App Attest has never produced a verified request. Enforcement stays off until it does.
- Report moderation, which needs a real report to work through.
- Seven moderate transitive dependency advisories, to be fixed away from this Mac.
- **Cloudflare Email Routing for `support@seekmiddleground.com`.** The address is published and
  correct; nothing will arrive until the route exists. Cloudflare → seekmiddleground.com → Email →
  Email Routing → enable, add `support` as a custom address, forward to a real inbox, accept the
  MX records it offers. Two minutes, and it is the contact Apple uses.
- No plan abroad has been created against the real backend — the zone is proven in the
  simulator and in the rules tests, never yet written by a person choosing a place.
- 1.0 is in review with build `202608021918`, which predates every fix this week. Push does not
  work in it at all. Fixes land in 1.0.1.
- App Privacy → **Coarse Location**, collected, **linked** to the user, App Functionality, not
  tracking. Must be entered by hand; the App Store Connect API does not expose it.
