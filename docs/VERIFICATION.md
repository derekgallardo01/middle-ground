# Verification log — end to end on the simulator

**Run:** 04 August 2026, 15:31 EDT
**Commit:** `1336e09` on `fix/build-pairing-and-tooling`
**Machine:** macOS 26.5 (arm64) · Xcode 26.6
**Simulator:** iPhone 17 Pro · **Java:** 26.0.2

Every row below was driven on a running simulator. Nothing here is inferred from code
reading, and nothing is reported as verified that was not observed.

## Totals

| Suite | Tests | Result |
|---|---|---|
| Firestore security rules (emulator) | 181 | **all passed** |
| Swift unit | 240 | **all passed** |
| UI, on the simulator | 77 | **all passed** |
| SwiftLint `--strict` | — | **0 violations** |
| Cloud Functions syntax | — | **ok** |
| Recorded tour | 41 frames | **every frame distinct** |

**518 automated tests. 0 failures.**

## What this run added

The previous log reported totals. This one is itemised, and it closes two real holes:

- **The operator role had no coverage at all, and could not have had any.** In mock mode
  `PreviewAuthService.isAdmin()` returned false, so the Admin tab was never built and every
  section behind it was unreachable on a simulator — including the reports queue and the
  follow-through figures shipped this week. `-MGAdmin` exists for that now, mock-mode only,
  and it confers nothing real: `firestore.rules` checks a server-issued claim.
- **Several actions were only ever checked for presence.** Confirming a plan happened,
  staking points, cancelling with a reason, creating and revoking a plan code, and changing
  a notification switch were all asserted as "the control is there". They are now pressed.

## Per test

### The operator role

`E2EAdminUITests` — 13 tests, all passed

| Test | Result |
|---|---|
| Tab Is Present Only For An Admin | pass |
| Overview | pass |
| Users | pass |
| Requests | pass |
| Reports Queue Offers A Decision | pass |
| A Report Can Be Closed | pass |
| Events | pass |
| Venues | pass |
| Audit | pass |
| A Decided Report Shows Who Decided It | pass |
| Outcomes Show Follow Through | pass |
| Outcomes Break Down By Party Size And Kind | pass |
| Outcomes Say When Collection Began | pass |

### Actions — driven, not just present

`E2EActionsUITests` — 8 tests, all passed

| Test | Result |
|---|---|
| Confirming A Plan Happened | pass |
| Saying A Plan Did Not Happen | pass |
| Putting Points On A Plan | pass |
| Cancelling Asks Why And Takes An Answer | pass |
| Creating And Revoking A Plan Invite | pass |
| Notification Switches Can Be Changed | pass |
| Reporting In A Group Asks Who | pass |
| The Feed Can Be Filtered | pass |

### Roles — who may do what

`ActionCoverageUITests` — 18 tests, all passed

| Test | Result |
|---|---|
| Every Tab Reachable | pass |
| Recipient Is Offered Every Response | pass |
| Recipient Can Save For Later | pass |
| Recipient Can Reach The Report Control | pass |
| Recipient Can Accept And The Status Moves | pass |
| Creator Is Offered No Responses | pass |
| Creator Is Not Offered Save | pass |
| Creator Can Also Report The Other Participant | pass |
| Creator Can Cancel Their Own Plan | pass |
| Creator Can Compose A New Plan | pass |
| Group Plan Shows Who Is In And Who Is Owed | pass |
| Composer Is Available Even When It Is Not Your Turn | pass |
| Sending A Message Adds It To The Transcript | pass |
| Asking A Question Does Not Unpick An Agreed Plan | pass |
| Calendar Renders | pass |
| Activities Show Progress | pass |
| Account Deletion Is Reachable | pass |
| Profile Shows Groups And Invite Code | pass |

### Features — does each one render and work

`FeatureCoverageUITests` — 26 tests, all passed

| Test | Result |
|---|---|
| Activities: reliability And Progress Render | pass |
| Activities: shows How Often Your Plans Happen | pass |
| Availability: says What It Shares | pass |
| Availability: shows When Someone Else Is Not Free | pass |
| Availability: you Can Block Out A Day And Clear It | pass |
| Booking: find A Table Is Offered On An Agreed Plan With A Place | pass |
| Booking: is Absent On A Plan Nobody Has Agreed To | pass |
| Calendar: shows A Plan With A Time | pass |
| Chat: a Sent Message Joins An Existing Conversation | pass |
| Chat: shows The Existing Conversation | pass |
| Create: full Flow Reaches A Sendable State | pass |
| Group: shows Who Is In And Who Is Owed | pass |
| Plan Invite creator Can Open The Invite Row | pass |
| Profile: shows Groups Invite Code And Notification Settings | pass |
| Read Receipts seen By Line Is Shown | pass |
| Requests: composer Offers To Attach A Time | pass |
| Requests: decline Is Offered And Completes | pass |
| Requests: reschedule Opens A Time Picker | pass |
| Save For Later comes Back Off Again | pass |
| Spontaneous: send Is Reachable And The Form Carries Everything | pass |
| Stake: row Is Shown On A Staked Plan | pass |
| The Suggest Button Says What It Does | pass |
| Threads: reply Control Is Offered | pass |
| Threads: reply Is Shown Under Its Parent | pass |
| Typing: indicator Appears When Someone Is Typing | pass |
| Typing: indicator Is Absent By Default | pass |

### Smoke — the app runs at all

`WalkthroughUITests` — 12 tests, all passed

| Test | Result |
|---|---|
| Activities Tab Shows Gamification | pass |
| All Four Tabs Exist | pass |
| App Launches And Reaches Main U I | pass |
| Calendar Tab Renders | pass |
| Compose Sheet Opens | pass |
| Creator Sees No Response Buttons On Their Own Request | pass |
| Creator Sees Waiting State And Can Cancel | pass |
| Large Text Does Not Break The Feed | pass |
| Opening A Request Shows Its Detail | pass |
| Profile Shows Account Deletion | pass |
| Requests Feed Renders Seeded Requests | pass |
| Saving Is Not Available To The Creator | pass |
### Security rules — the emulator suite

`CloudFunctions/test/rules.test.js` — 181 tests, all passed. The six covering report resolution
had never run before: the emulator needs a JVM, and OpenJDK was installed but keg-only, so it was
never on `PATH`.

| Test | Proves |
|---|---|
| an admin can record a decision | the queue can actually be worked |
| **an admin cannot alter the report itself** | **a complaint is not editable by the people it is about** |
| an admin cannot sign somebody else's name to it | `resolvedBy` is the actor, not a claim |
| only the two real outcomes are accepted | no arbitrary status strings |
| an ordinary user cannot resolve a report | the tab is a convenience gate; the rules are enforcement |
| a resolved report still cannot be deleted | matches what the privacy policy promises |

## Four fixture bugs this run found

Every one was in the test or the fixture, not the app — but each would have made the log lie:

1. **The outcomes fixture had nine settled plans and the figure needs ten**, so the panel correctly
   said "not enough yet" and my assertion failed. The app was right.
2. **The attendance button says "Yes, it did", not "It happened"** — the test was looking for copy
   that does not exist.
3. **A plan code is revoked by "Cancel this plan code", not "Revoke".**
4. **`switches.firstMatch` is the master push toggle**, which asks iOS for a permission the
   simulator never grants — so it correctly stays off. Asserting it flips would have been
   asserting the app ignores the OS. The test now drives a per-kind switch.

## Deployed and verified live

| Thing | State |
|---|---|
| Firestore ruleset | `8a899225-ba02-479b-9f54-440325ef3f24` (roll back to `d191f323`) |
| seekmiddleground.com | `/`, `/changelog`, `/timeline`, `/privacy`, `/terms`, `/support` — all 200 |
| Privacy policy | report-resolution wording live on **both** hosts, effective 4 August 2026 |

## What a simulator cannot prove

Stated so this log is not read as claiming more than it does:

- **Push has never been delivered end to end.** The weekly-nudge deep link fixed this week is the
  one change here a simulator cannot exercise. It needs a real device.
- **Sign in with Apple and push registration have never run on hardware.**
- **App Check enforcement is off.**
- **The two-device settlement path** — one person confirms, the other collects on their next visit
  — is covered by an idempotency unit test and by reasoning, not by two devices. `PairingE2ETests`
  and `Scripts/two-device-e2e.sh` exist for this and need two simulators and a real backend.
- Everything above runs against **mock repositories**. The Firestore implementations are exercised
  by the rules suite and by `RealBackendUITests`, not by these 77.

These are tracked in `docs/APP_REVIEW_NOTES.md` and are the substance of a 1.0.1 device pass.
