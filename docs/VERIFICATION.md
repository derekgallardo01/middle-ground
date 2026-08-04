# Verification log

**Run:** 04 August 2026, 14:21 EDT
**Commit:** `95c9dc3` on `main` — Merge main: keep the promises already on screen
**Machine:** macOS 26.5 (arm64) · Xcode 26.6
**Simulator:** iPhone 17 Pro
**Java:** openjdk version "26.0.2" 2026-07-21

## Result: everything passed

| Suite | Count | Result | Evidence |
|---|---|---|---|
| Firestore security rules | 181 | **pass**, 0 fail | `CloudFunctions/test/rules.test.js` via emulator |
| Swift unit tests | 240 | **pass**, 0 fail | `xcodebuild test -scheme MiddleGround` |
| UI — action coverage | 18 | **pass**, 0 fail | `ActionCoverageUITests` |
| UI — feature coverage | 26 | **pass**, 0 fail | `FeatureCoverageUITests` |
| SwiftLint `--strict` | — | **clean**, 0 violations | repo root |
| Cloud Functions syntax | — | **ok** | `node --check index.js` |
| Recorded tour | 41 frames | **pass**, every frame distinct | `Scripts/full-tour.sh` |

**Total: 485 automated tests, 0 failures.**

## The gap this run was for

The report-resolution security rule shipped **untested**. The emulator needs a JVM, none was
installed, and the rule was deployed on the strength of compiling cleanly — which proves syntax and
nothing else. That is now closed: OpenJDK 26 was already present via Homebrew but keg-only, so it
was never on `PATH` and `java -version` failed. No install was needed, only the path.

All six of those tests pass. The one that matters most is the second:

| Test | What it proves |
|---|---|
| an admin can record a decision | the queue can actually be worked |
| **an admin cannot alter the report itself** | **a complaint is not editable by the people it is about** |
| an admin cannot sign somebody else's name to the decision | `resolvedBy` is the actor, not a claim |
| only the two real outcomes are accepted | no arbitrary status strings |
| an ordinary user cannot resolve a report | the tab is a convenience gate; the rules are the enforcement |
| a resolved report still cannot be deleted | matches what the privacy policy promises |

## Deployed and verified live

| Thing | State |
|---|---|
| Firestore ruleset | `8a899225-ba02-479b-9f54-440325ef3f24` (live; roll back to `d191f323`) |
| seekmiddleground.com | `/`, `/changelog`, `/timeline`, `/privacy`, `/terms`, `/support` — all 200 |
| Changelog | carries the 4 August release |
| Privacy policy | report-resolution wording live on **both** hosts, effective date 4 August 2026 |

## What is still not verified, and cannot be here

Unchanged from before — worth restating so the log is not read as saying more than it does:

- **Push notifications have never been delivered end to end.** The weekly-nudge deep link fixed in
  this batch is the one change here that a simulator cannot exercise. It needs a real device.
- **Sign in with Apple and push registration have never run on physical hardware.**
- **App Check enforcement is off.**
- The stake and attendance payouts are proven against the real `GamificationService` in unit tests,
  but the two-device case — one person confirming, the other collecting on their next visit — has
  only been reasoned about and covered by the idempotency test, not driven on two devices.

These are recorded in `docs/APP_REVIEW_NOTES.md` and are the substance of a 1.0.1 device pass.
