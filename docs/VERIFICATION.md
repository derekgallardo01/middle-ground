# Verification log — screenshots and video, personally checked

Every ✓ below means **I opened that image and read what was on it**. Where I could only read a
frame at contact-sheet scale, it says so, because "it passed" and "I looked at it" are different
claims and only one of them is worth anything.

**Run:** 04 August 2026, 16:24 EDT · **Commit:** `65bdb8f`
**Simulator:** iPhone 17 Pro · macOS 26.5 · Xcode 26.6

## Where the evidence is

```
~/Desktop/MiddleGround-Evidence/
  tour.mp4                 6m14s, the whole app end to end
  tour-contact-sheet.png   all 51 tour frames on one page
  tour-frames/             51 stills
  feature-proof/           26 stills, one per action or admin section
```

## Video — `tour.mp4`

Checked by sampling frames at 3s, 60s, 140s, 220s, 300s, 330s, 350s and 368s, **not** by file
size. That distinction matters: a tour was once reported as good on file size alone when its first
six minutes were the iPhone home screen.

| At | ✓ What is on screen |
|---|---|
| 0–3s | Home screen while the app launches. Three seconds, not six minutes |
| 60s | A declined plan, five tabs including Admin |
| 140s | The feed, response buttons reading **Accept / Suggest / Decline** |
| 220s | "Why are you cancelling?" with all six reasons |
| 300s | Profile, all six notification switches |
| 330s | "Date night this Friday? — Cancelled · Something came up" |
| 350s | The operator panel overview |
| 368s | **Follow-through 70%** |

51 frames extracted, every one distinct.

## Actions — driven, and the result photographed

Read at full size. `feature-proof/`

| Action | ✓ What the image shows | File |
|---|---|---|
| Asked whether a plan happened | "Did this happen? Your answer is yours alone — the other person is asked separately", **Yes, it did** / **No, it didn't** | `action-01-asked-if-it-happened.png` |
| Confirming it happened | The question is gone, replaced by "Waiting for Sam to confirm" | `action-01-confirmed.png` |
| Saying it did not happen | Same — correctly waits for the other person either way | `action-02-did-not-happen.png` |
| Points offered on a plan | "Put points on it? You both stake the same. Turn up and you each get it back as a bonus." 10 / 25 / 50 — **copy that is now true** | `action-03-stake-offered.png` |
| Points placed | "25 points on it — waiting for Sam to agree" | `action-03-stake-placed.png` |
| Cancelling asks why | Six reasons, and "The plan stays in your history rather than disappearing" | `action-04-cancel-asks-why.png` |
| Cancelled with a reason | Status **Cancelled**, and "Something came up" on the record | `action-04-cancelled.png` |
| Plan invite created | Code `EVPC8T`, "The next person to use this code joins the plan. It then stops working." | `action-05-plan-invite-created.png` |
| Plan invite revoked | Back to "Create a code for this plan" | `action-05-plan-invite-revoked.png` |
| Notification switches | All six kinds, each with its explanation | `action-06-notification-settings.png` |
| A switch actually switches | "New requests" off, the rest on | `action-06-notification-changed.png` |
| Reporting inside a group | **"Who is this about?" — Priya / Sam**, then "What's wrong?", Send disabled until chosen | `action-07-report-asks-who.png` |
| The feed can be filtered | All / Your turn / Saved | `action-08-feed-filters.png` |

## The operator role — every section

| Section | ✓ What the image shows | File |
|---|---|---|
| The gate | Admin tab present with the claim, **absent without it** — both launches side by side | `admin-00-tab-present.png` |
| Overview | Users 2, Groups 1, Paired 1, Requests 3, Activation 100%, plus by-status and by-category | `admin-01-overview.png` |
| Users | Alex (`user_1`), Sam (`user_2`) | `admin-02-users.png` |
| Requests | Three plans with status, category, message count, id | `admin-03-requests.png` |
| Reports, waiting | The report with its note, subject, reporter and plan, offering **Actioned** / **Dismiss** | `admin-04-reports-waiting.png` |
| **Reports, closed** | Buttons gone, replaced by **"Actioned — user_1 · Aug 4, 2026 at 3:48 PM"** | `admin-05-report-closed.png` |
| A report decided earlier | "Dismissed — root · Aug 3" | `admin-09-report-already-decided.png` |
| Events | Empty state: "No events recorded yet." | `admin-06-events.png` |
| Venues | Three curated places with their cities and plan kinds | `admin-07-venues.png` |
| Audit | "Every admin view of user data is recorded here. Entries cannot be edited or deleted." | `admin-08-audit.png` |
| **Outcomes** | **Follow-through 70%** across 10 plans, 10% called off at short notice | `admin-10-outcomes.png` |
| Outcomes, broken down | By party size and by kind of plan | `admin-11-outcomes-breakdown.png` |
| Outcomes, the caveat | "Collection began 2 August 2026… it cannot be reconstructed" | `admin-12-outcomes-caveat.png` |

**I checked the arithmetic rather than trusting the label:** happened 7 + called off early 1 +
called off late 1 + nobody turned up 1 = 10 settled, matching "across 10 plans". 7/10 = 70%.
1/10 = 10% late. Agreed (2) and disputed (1) are correctly outside the denominator.

## Features — read at contact-sheet scale

`tour-contact-sheet.png`, 51 frames. At that size I can confirm the screen, the flow and the
headline text, **not** every word of body copy.

| ✓ | Seen in the frames |
|---|---|
| ✓ | Feed, calendar, activities, profile |
| ✓ | Accept, and the "+25 XP · Request accepted!" celebration |
| ✓ | Decline, and the declined state |
| ✓ | Suggest, and the reschedule date picker |
| ✓ | Group plan with three people, chat, a reply, the typing indicator and "Seen by" |
| ✓ | Points on a plan |
| ✓ | Cancelling, both ways |
| ✓ | Calendar with a plan, "I'm not free this day", and "Sam isn't free" |
| ✓ | Creating a request, every category |
| ✓ | Spontaneous mode with title, description, expiry, recipients and Send Now |
| ✓ | Activities: level, streak, achievements, and the follow-through card |
| ✓ | Every admin section |

## Automated totals behind the pictures

| Suite | Tests | Result |
|---|---|---|
| Firestore security rules (emulator) | 181 | all passed |
| Swift unit | 240 | all passed |
| UI, on the simulator | 77 | all passed |
| SwiftLint `--strict` | — | 0 violations |

## Two things looking at the pictures found

Neither would have shown up in a pass/fail total, which is the argument for looking.

1. **The report picker offered "Sam" and "Someone".** `MockUserRepository` knew Alex and Sam but
   not Priya, who is on the three-person plan — so her name fell back to "Someone". On a
   safety-critical screen, choosing between a name and "Someone" is no choice at all. The fixture
   now knows her, and the frame above reads **Priya / Sam**. Worth keeping in mind for production:
   if a participant's user document ever fails to load, that picker degrades the same way.
2. **Every breakdown row reads "—".** The by-party-size and by-kind tables suppress a percentage
   until that *slice* has ten settled plans, so at today's volume they all show a dash next to a
   count. It is the same honesty rule used everywhere else and it is not wrong, but a reader
   cannot tell "0%" from "not enough yet". Worth deciding deliberately rather than leaving.

## What no simulator can show

- **Push has never been delivered end to end.** The weekly-nudge deep link is the one fix this
  week that cannot be exercised here at all.
- Sign in with Apple and push registration have never run on hardware; App Check is off.
- The two-device settlement path — one person confirms, the other collects on their next visit —
  is covered by an idempotency unit test and by reasoning, not by two devices.
- Everything photographed above runs against **mock repositories**. The Firestore implementations
  are exercised by the rules suite, not by these frames.
