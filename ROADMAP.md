# Middle Ground — Roadmap

Captured from a product brainstorm on 2026-07-31. This document has two halves:

- **Specs** — the Categories & Groups cluster, worked up in enough detail that someone (or an
  agent) can pick one up and build it without making product decisions on the owner's behalf.
- **Backlog** — everything else, grouped and sized, deliberately *not* specced until promoted.

Anything not in the Specs section is an idea, not a commitment. Where a decision has already been
made it says so; where one is still open it says that too, rather than quietly picking.

---

## Built since this document was written

- **Dating and Chill categories**, with an `unknown` fallback so a category added later can never
  make a request silently vanish on an older build — the trap existed in both the Firestore and
  the SwiftData decode paths.
- **Group names and per-group invite codes.** The code shown was picked by
  `relationships.first { !$0.isPaired }` in five places across three view models, so with more
  than one unpaired group the screen could show a code that invited someone into the wrong group.
- **Request templates** — "what are we watching / eating tonight" as one tap.
- **Counter suggestions** — Negotiate opens the composer instead of sending an empty response, and
  a counter can carry a new time, so accepting one actually moves the plan.
- **"Did it happen?"** — attendance confirmation, and `RequestStatus.completed` is finally
  assigned. ⚠️ *Built but inert until `firestore.rules` is deployed; the rules tests have not
  been run, since the emulator needs a JDK and firebase-tools.*
- **Per-activity levels and goals.** XP now accrues per category as well as overall, and goals
  name the metric they measure — previously progress was a switch on hardcoded IDs ending in
  `default: 0`, so any goal added without editing that switch could never unlock.
- **Calendar clash checks** (Apple/EventKit), read-only and opt-in.
- **Location on a plan** — the `location` field had been on the model, the DTO and the rules
  since the beginning and rendered nowhere. It now has a "Where?" and opens in Maps.
- **Achievements and the activity feed are mirrored**, so a reinstall no longer restores the
  numbers with nothing behind them.
- **Saved requests are findable** — a filter on the feed. `savedForLater`, a Bool set to `true`
  in exactly zero places, is gone.
- **Cancelling records why instead of deleting the request.** ⚠️ *Rules branch undeployed.*
- **A reliability score**, computed from confirmations and cancellations rather than stored.
  Visible only to the person it describes — see the open question below.
- **Notifications people can control.** Five types, each switchable, stored in a collection of
  their own because `users/{uid}` is readable by any signed-in user. Absence means send, so nobody
  is migrated and nobody is silently muted. Two of the five did not exist before: a plan being
  cancelled (which the response trigger never saw, because cancelling does not touch the
  negotiation chain) and "did it happen?", which asks for the attendance every reliability idea is
  computed from.
- **A weekly nudge** naming the group that has gone longest without a plan — one push however many
  qualify, and silent when something is already booked.
- **Plan-scoped location sharing.** One point per tap, only while an accepted plan is inside its
  window, deleted afterwards. ⚠️ *Gated on the App Store Connect privacy questionnaire.*
- **A curated list of real places**, edited from the admin panel rather than compiled in, so a
  restaurant that closes is an edit instead of an App Store submission.
- **The push badge counted the wrong things.** `recipientIDs + status == 'pending'` missed every
  negotiation in flight: a counter-offer has status `countered`, and the turn after a counter
  usually belongs to the creator, who is in neither.

### ⚠️ Three rules branches are written, unverified and undeployed

`isConfirmingAttendance`, `isCancelling`, and the tightened `allow delete`. Until
`firestore.rules` is deployed, attendance confirmation and cancellation are both inert: the
backend refuses the writes, so the reliability score has nothing to count. The emulator needs a
JDK and firebase-tools, so the rules tests have not been run — the CI "Firestore rules" job is
the intended verification.

### Open question the scoring work needs answered

**Who can see someone's reliability score?** It is currently visible only to its owner. Inside a
couple this number is as usable as a weapon as it is as a signal, and "who can read it" is the
decision that settles which it becomes. Penalties and appeals were chosen deliberately; this is
the part of that choice still outstanding.

## Status of the product

v1.0 is in App Store review. The core loop — send a request, negotiate, land on a time — works and
is covered by tests. Requests, relationships, and analytics events live in Firestore behind
turn-based security rules. Gamification (XP, streak, growth score, achievements) is local to the
device with a Firestore mirror for restore.

---

# Specs

## S1 — Dating and Chill categories

**Goal.** Two new request categories, so plans that aren't errands or travel have a home:
*Dating* (planning a date, including with someone you're not yet paired with long-term) and
*Chill* (low-effort, low-commitment time together).

**Data model.** Add `case dating` and `case chill` to `RequestCategory`
(`Sources/MiddleGround/Core/Models/Request.swift:3`). Raw values are the enum case names, matching
the existing ones. Add arms to `displayName` and `iconName` in the same file — suggested SF Symbols
`heart.circle.fill` and `sofa.fill`.

**Files.** `Request.swift` only, for the enum. `RequestTypePicker.swift` and the admin overview
iterate `RequestCategory.allCases`, so both pick the new cases up with no change. Confirm the grid
in `RequestTypePicker` still lays out at eight items on the smallest supported width.

**Security rules.** None. Rules never inspect `category`.

**⚠️ The one real risk — old clients silently lose requests.**
`RequestDTO.toModel()` (`Sources/MiddleGround/Core/Repositories/Firestore/FirestoreDTOs.swift:39`)
does `guard let categoryEnum = RequestCategory(rawValue: category) else { return nil }`, and the
repository uses `compactMap`. So a request created in a new category does not fail loudly on an
older build — **it simply is not in the list**. One partner sends a Dating request, the other is a
version behind, and it never arrives. No error, nothing to report.

Pick one before shipping:

- **Decode fallback (recommended).** Add `case unknown` to `RequestCategory` and decode unrecognised
  raw values to it, rendering with a neutral icon and the stored string. Costs one release of lead
  time — the fallback must ship *before* anything writes the new categories — but it makes every
  future category addition safe forever.
- **Minimum version gate.** Refuse to create new-category requests until adoption is high enough.
  No code changes to decoding, but it needs a remote flag and it only defers the problem.

**Acceptance criteria.**
- Both categories appear in the compose picker and on request cards.
- A request created in each category round-trips through Firestore and renders correctly.
- With the fallback in place, a client that does not know a category still shows the request rather
  than dropping it — test by writing a request with a bogus `category` value via the seed script.
- Admin overview counts the new categories (it iterates `allCases`, so this should be automatic —
  verify rather than assume).

---

## S2 — Renaming groups

**Goal.** A group is currently labelled by its *type* ("Couple", "Friends"). With multiple groups,
two friend groups are indistinguishable. Let members give a group a name.

**Data model.** `Relationship` (`Sources/MiddleGround/Core/Models/Relationship.swift`) has
`participantIDs`, `type`, `createdAt`, `growthScore`, `inviteCode` — **no name**. Add
`var name: String?`. Add the same to `RelationshipDTO`
(`Sources/MiddleGround/Core/Repositories/Firestore/FirestoreDTOs.swift:119`) as an optional so
existing documents decode unchanged.

**Security rules — already permitted, no change needed.** The general update branch in
`firestore.rules` pins only `inviteCode`, `type` and `createdAt` and requires `participantIDs` to be
unchanged. A new `name` field falls outside that list, so any participant can already write it.
Worth a rules test to lock the intent in rather than relying on the absence of a constraint.

**Display.** `RelationshipService.displayLabels(for:currentUserID:)`
(`Sources/MiddleGround/Core/Services/RelationshipService.swift:149`) currently resolves the
partner's name and falls back to `type.displayName`. New precedence: group name → partner name →
type. This one function feeds both the Compose picker and Profile, so changing it covers both.

**UI.** Rename affordance in Profile's group list. Reuse `RequestLimits.clamp` for the length cap;
add a `groupName` limit (suggest 40) alongside the existing ones in `Request.swift`.

**Acceptance criteria.**
- Naming a group updates the label in Profile and in the Compose partner picker.
- An existing group with no name still shows the partner's name, then the type.
- The name is trimmed, length-capped, and an all-whitespace name is treated as no name.
- A rules test asserts a participant may set `name` and a non-participant may not.

---

## S3 — Multiple groups: close the gaps

**Goal.** Multiple groups mostly work already. `CreateRequestViewModel` loads every relationship and
exposes a recipient picker; the demo seed script creates two. What's missing is the surrounding UI
and one genuine bug.

**🐛 The invite-code bug — fix first.** Both Profile and Compose read the code to share from
`relationships.first { !$0.isPaired }?.inviteCode`
(`ProfileViewModel.swift:21`, `CreateRequestViewModel.swift:24`). With more than one group that
picks an arbitrary unpaired group, so **the screen can show the code for a different group than the
one the user thinks they're inviting to.** This is already reachable today. The seeding script works
around it by insisting every group it creates is paired — see the comment in
`Scripts/seed-demo-partner.mjs`. Fix: make the invite code an explicit per-group action rather than
a single ambient "your code".

**Also in scope.**
- Profile lists all groups, each with its own members, invite code and leave action — not one
  implicit group.
- Compose shows which group a request is going to, not just which person.
- Creating a second group from Profile (`type` picker already exists on the model).

**Acceptance criteria.**
- With two unpaired groups, each shows its own distinct invite code, and redeeming one joins that
  group.
- A request created for group B is not visible to members of group A (already enforced by rules via
  `allParticipantIDs` — verify).
- Leaving one group leaves the others intact.

---

## S4 — "What are we watching / eating tonight?"

**Goal.** The two most frequent low-stakes decisions, as one tap instead of a typed request.

**Approach.** Templates over the S1 categories — **not new infrastructure**. A template is a
title, a category, and optionally a proposed time; picking one opens the existing compose sheet
prefilled. Everything downstream (rules, negotiation, calendar, gamification) is unchanged because
it is an ordinary `Request`.

**Depends on** S1 (Chill category).

**Acceptance criteria.**
- Templates appear on the compose sheet and prefill title and category.
- A request created from a template is indistinguishable from a typed one in Firestore.
- Adding a template requires no model, DTO or rules change.

---

# Backlog

Sized as **S** (days), **M** (a week or two), **L** (a month+), **XL** (needs partnerships or
staffing before code).

## ⚠️ Prerequisite for everything below: "did it happen?" — M

**The app has no idea whether a plan actually took place, and nothing below works without that.**

Missed reservations, missed trips, a record of people missing, three cancellations in a row,
attendance-based scoring — every one of these is computed from whether an accepted plan was
honoured. The app never learns that. A request's life ends at `accepted`.

`RequestStatus.completed` already exists, and it is decoration: it has a display name, a badge
colour, and it counts as settled in `Request.isOpen` — but **nothing anywhere assigns it**. It is
read in four places and written in none. This is the same shape of defect as `.reschedule` before it
got a trigger: a fully modelled state with no way to enter it.

So the first thing to build in this cluster is the confirmation step from your notes —
*Cancel / Confirm / Reject* and *"confirmation of the action"*. After a plan's `proposedTime`
passes, both participants are asked whether it happened. That single signal is what produces:

- attendance and no-show records (missed reservations, missed trips)
- a defensible reliability score, rather than one derived from intentions
- the evidence an appeal is argued over

Design notes worth settling early: what happens when the two people disagree about whether it
happened; what a non-answer means (silence must not equal a no-show, or the score punishes people
for not opening the app); and how far after the fact confirmation stays open.

**Nothing else in this section should be specced before this is.** A penalty derived from a signal
the app does not collect is a penalty derived from nothing.

## Reliability & reputation — L

**Decided: penalties are in, with an appeals path.** Blocked on the prerequisite above.

Raw items: popularity score · missed reservations subtract · missed trips · record of people missing
· cancellation reasons (list) · cancel three times in a row → penalty · punishment · score ·
cancel / confirm / reject · confirmation of the action · appeal rejection via moderator/staff ·
rejection reasons (list) · rejection denials *(defined: disputing a decline — gated on a moderator queue)* ·
review other group members · "leadership of score for activities" *(defined: a leaderboard,
groups only)* · people rate the activities · closure *(defined: the confirmation step, built)* ·
motivation betting *(defined: points, built)* · stats or metrics
*(unclear whether user-facing or the existing admin panel, which already reports totals, funnel
and per-user stats)*.

Constraints that come with the decision:

- **A punitive score inside a couple is usable as a weapon as easily as a signal.** Needs an
  explicit answer to: what can the *other* partner see, and can a score be used to pressure someone?
  The safest split is the one already discussed — penalties apply to venue bookings and group/public
  plans where a no-show costs someone money; couples keep a positive-only score.
- **Appeals imply staffing.** A moderator queue is an operational commitment, not a feature.
  This is what gates **Rejection Denials** (defined below) — the screens are small, the standing
  obligation to answer them is not.
- **A leaderboard inherits the couples exclusion.** "Leadership of score" is a ranking within a
  group, and a ranking between two partners is the weaponisation problem with a rank attached.
- Every penalty needs a recorded reason, or the score is unexplainable — the same defect just fixed
  on Growth Score, at higher stakes.
- App Review guideline 1.2 (user-generated content) applies once users rate each other: reporting,
  blocking and a response window are required. Reporting already exists (`reports` collection).

## Identity & trust — one defined, one still open

In-person identity verification · gate guardian *(undefined)* · authorised representative
*(undefined)* · start at 0 *(defined: reputation earned from zero)*.

**Specced, deliberately not built.** Gate Guardian now has a definition (below). It is not started
because feature work is paused until 1.0 ships, and because its second stage is an operational
commitment rather than an engineering one.

**Identity verification** means handling government ID: a data-protection posture well beyond
anything this app does today, a new App Privacy disclosure, near-certain review scrutiny, and an
ongoing obligation to store and destroy identity documents correctly. That is a company decision,
not a sprint.

### Gate Guardian — ✅ defined, specced, not built

**A two-stage trust ladder, and a gate on meeting strangers.**

| Stage | How | What it proves |
|---|---|---|
| 1. Identity | A third-party provider (Stripe Identity, Persona or similar) | The person holds a real government ID |
| 2. In person | A staff member or agent meets them | A human has actually seen them |

**What it unlocks:** planning with someone outside your existing groups. Today that means the
single-plan invite — a code handed to someone you are not in a group with — and it would cover any
future discovery. This is the "gate" the name implies, and the only version where the cost of
verification clearly buys something: a badge alone changes nothing, and weighting the reliability
score by verification would penalise people for declining to hand over a passport.

**Documents never touch our storage.** The provider holds them; we store a pass/fail, a level and
an opaque provider reference. That is the difference between a feature and a liability — becoming
the custodian of identity documents brings retention, deletion and breach obligations that dwarf
anything this app does today.

Shape of the data: a `verification/{uid}` document holding `level` (`none` / `id` / `inPerson`),
the provider reference and timestamps. Others may see *that* someone is verified — that is the
whole point — but never the reference or anything from the document itself, which means the public
half and the private half cannot live in the same readable record. Same reasoning that put
notification settings in their own collection rather than on `users/{uid}`.

**Stage 2 is an operation, and it is tractable because the app is local to Miami.** A representative
meeting people works at one city's scale; it is the thing that breaks first if the app spreads. That
is a decision with a written trigger now rather than an unexamined assumption — see "Where this
runs" below.

It is still the second standing obligation on this roadmap, after the appeals queue for Rejection
Denials. Worth knowing that both exist before committing to either.

**Before it can start:** an App Privacy disclosure for identity data, a provider chosen and under
contract, a written retention and deletion policy, and a decision about what happens to someone
whose verification is revoked mid-plan.

### Authorized Representative — ✅ defined: the person who does stage 2

Not a user delegating authority — **someone authorised to verify on the company's behalf.** They
meet a person, confirm they are who the document said, and mark them verified.

This correction matters, because the earlier reading was the dangerous one. "Someone acting on
another's behalf" would have meant letting a third party accept or decline plans for a user, which
requires `firestore.rules` to permit writes to a request they are not a participant of — the widest
change available in this codebase. None of that applies. A representative never touches anyone's
plans.

What it actually needs is a role: a claim like the existing `admin` one, scoped to a single
action — raising a user's verification level to `inPerson`, and nothing else. Every such action is
audit-logged the same way admin reads of user data already are, because "a human vouched for this
person" is exactly the claim that needs to be traceable to *which* human.

⚠️ The role is the easy part. Deciding who gets it, what training they have, and what happens when
one of them is wrong or dishonest is the real work — and it is operational, not technical.

---

## Where this runs: Miami

The app operates in **one city**, and that assumption is already load-bearing in several places
that would otherwise look arbitrary:

- Every scheduled Cloud Function runs on `America/New_York` — the attendance prompt, the weekly
  nudge, the operator digest. Correct for Miami, and quietly wrong the day it is not.
- The curated venue list carries a `city` on every entry but filters by none, which is right for
  one city and misleading for two.
- **In-person verification is only viable at this scale.** A representative meeting people is a
  real operation, and it is tractable precisely because it is local.

Recorded so that "we will cross that road when we get there" is a decision with a written trigger
rather than an assumption nobody revisits. The trigger is the second city.

**What exists already, and may be enough:** App Review guideline 1.2 asks for a way to report
content, a way to block an abusive user, and a published response window. Reporting is built,
leaving a group severs contact entirely, and the policy commits to 24 hours. The gap is that
leaving is all-or-nothing — there is no way to block one person while staying in a group with
others, which only starts to matter once groups hold more than two people.

---

## What comes next: getting 1.0 approved

Feature work stops here. Everything built since the 1.0 submission — groups of three, late
cancellation, notifications, location sharing, venues, the speed and motion passes — is already
queued for the version after it.

The only thing blocking the next submission is the **App Privacy questionnaire in App Store
Connect**, which needs Coarse Location added: linked to the user, not used for tracking, purpose
App Functionality. The privacy manifest already declares it; the questionnaire is a separate
declaration and a mismatch is a rejection. Details in `docs/APP_REVIEW_NOTES.md`.

## Venues & partners — the free half is built, the rest is still commercial

Restaurants · OpenTable reservations · restaurant sponsors · gyms · linking restaurant locations ·
list of restaurants.

**✅ Built: the curated list.** Real named places are offered when someone fills in "Where?", and
they lead the generic kinds of place — "Lucia's" is a decision already made, "Restaurant" is the
same blank page with a category attached.

The list lives in a `venues` collection, edited from **Admin → Venues**, not compiled into the app.
That is what answers the standing objection. "A curated list goes stale" was right about a
*hardcoded* one: a restaurant closes and fixing it costs a code change, a build, a review and a
release. Curated in Firestore it costs an edit. Each venue carries a city, the categories it suits,
and a rank so the good ones can lead without being renamed.

✅ **One city is the operating assumption, not a limitation.** The app runs in Miami; every venue
stores its `city` and shows it, and nothing filters by location because nothing needs to. Filtering
is the first thing to build if a second city ever appears — see "Where this runs" below.

**Still blocked on commercial agreements:** OpenTable reservations, restaurant sponsors, gyms.
OpenTable's partner API is not open self-service. Sequence unchanged: confirm access first, then
spec. None of it blocks the list above, which was the half that never needed a partnership.

## Calendar integration — M

Google Calendar / Apple Calendar · show whether an accepted slot is already booked.

Apple Calendar via EventKit is the cheaper half and needs only a purpose string plus an App Privacy
update. Google Calendar needs OAuth and a verification review. High user value: the app already
knows `proposedTime`, so a conflict check is a small addition to
`Features/Calendar/CalendarViewModel.swift`.

## Location sharing — ✅ built, gated on App Privacy answers

**Settled and built.** "Only active steps" meant only while a plan is *active* — not step or
movement data, which would have been HealthKit and a much heavier posture.

What shipped:

- Sharing exists only while an **accepted, dated** plan is inside its window: an hour before its
  time until four hours after. Opening early is deliberate — "I'm five minutes away" is said on the
  way, not on arrival. An undated request never qualifies.
- One point per tap, not a feed. `requestLocation()` returns a single fix and stops, so there is no
  stream to leave running and nothing happens in the background.
- **When In Use** only. `Always` would need a background mode and a justification at review this
  feature does not have.
- Readable only by that plan's participants, and **deleted** afterwards — Firestore TTL on
  `expiresAt`, plus a client filter because TTL is promised within 24 hours rather than instantly.
- The window is enforced in `firestore.rules` against the **server** clock, not only in Swift. A
  rule that lives only in the client is a rule a tampered client does not have, and that is the
  entire threat model for a location feature.

⚠️ **Still gated on one manual step**: the App Privacy questionnaire in App Store Connect. The
manifest (`App/PrivacyInfo.xcprivacy`) and the questionnaire are separate declarations and a
mismatch is a rejection. Answer Coarse Location · linked · not tracking · App Functionality. Full
notes in `docs/APP_REVIEW_NOTES.md`.

## Activity categories — S, mostly covered by S1

Fishing · basketball · workout · events · dating · chill · activity levels · skill points · goals.

The first four are *content* within categories, not new categories. Skill points and levels overlap
the existing gamification system — extend `GamificationRules` rather than building a parallel one.

## "Schedule a date with someone" — size unknown, needs scoping

Listed beside Dating and Chill, and it does not necessarily belong with them.

If "someone" means a person you are already grouped with, it is covered by S1 and costs nothing.
If it means **someone you are not yet connected to**, it is a different product: discovery,
matching, messaging strangers, consent and safety controls, and App Review guideline 1.2 obligations
far beyond what pairing-by-invite-code requires today. Every relationship in the app currently
begins with a code shared privately between two people who already know each other; this would be
the first feature that breaks that assumption.

Worth answering before it is sized, because the two readings differ by an order of magnitude.

## Smaller, already-adjacent — S

- **Counter suggestions** — built. Negotiate opens the composer rather than sending a contentless
  response, and a counter can carry a new time, so accepting one actually moves the plan. Before
  that, a counter was transcript text only: accepting "Sunday instead?" left the request — and the
  Calendar entry — on the original date.
- **Improving the score / rebuilding relationships** — presentation on top of the existing growth
  score, now that `StatDetailView` explains how it is calculated.
- **Cancel the last minute** — needs a definition: a distinct late-cancel action, or a normal cancel
  the reliability score weights by proximity to the plan?

---

## Proposed readings — correct these rather than starting from a blank page

Terms from the brainstorm I could not spec without inventing what they mean. Each row is my best
reading, clearly a **proposal**, with what changes if it is wrong. Cross out and replace freely.

| Term | Proposed reading | If this is wrong |
|---|---|---|
| **Gate Guardian** | An approval gate: a nominated person who must approve a plan before it reaches you | If it means controlling *who may contact you*, it is a blocking/allowlist feature instead — a different screen and a different rules change |
| **Authorized Representative** | Delegated authority: someone who may accept or decline on another's behalf | Changes the account model. Actions would need "acting as" attribution, and `firestore.rules` would have to let a third party write to a request they are not a participant of — a significant widening |
| **Start at 0** | Reputation is earned from zero rather than granted as a default | If a score can go *below* zero, penalties need a floor and a story for what a negative score means socially |
| ~~**Closure**~~ ✅ **settled** | The terminal step that ends a plan and locks its outcome — the confirmation step, **already built** | — |
| ~~**Motivation Betting**~~ ✅ **settled: points** | Both people stake **points** on following through; the stake moves on a no-show. **Built** — see `Stake.swift` | Real money is explicitly out. It would pull in payments, App Review 3.1.1 and possibly gambling rules |
| ~~**Rejection Denials**~~ ✅ **settled** | Disputing someone's decline or no-show claim — the **entry point to appeals**. See the definition below | — |
| **Stats or metrics** | User-facing per-group stats | The admin panel already reports totals, the funnel and per-user stats. If that is what you meant, it exists — and now loads in about one round trip instead of twenty-four |
| ~~**"Leadership of score for activities"**~~ ✅ **settled** | A **leaderboard** ranking within a group. See the constraint below | — |
| ~~**"Only active steps"** (location)~~ ✅ **settled** | Share location **only while a plan is active** — foreground, on demand, a point rather than a feed | HealthKit step data is explicitly out |
| **"Schedule a date with someone"** | Someone already in one of your groups | If it means people you are *not* connected to, that is discovery and matching — it breaks the assumption that every relationship starts with a code shared privately between two people who already know each other |

Five of these are now settled and struck through. What remains open is **Gate Guardian**,
**Authorized Representative**, **Start at 0**, **Stats or metrics**, and **"Schedule a date with
someone"** — the first two are the ones that would change the account model, so they are the ones
worth answering next.

### Rejection Denials — settled definition

Disputing someone else's decline or no-show claim: you said it happened, they said it did not, and
this is where that disagreement goes. It is the entry point to appeals.

**The blocker is operational, not technical.** A dispute has to be resolved by somebody, and that
somebody is a moderator queue — a commitment to answer within a stated window, staffed by a real
person, for as long as the app exists. The code is a few screens; the queue is a standing
obligation. Nothing here should ship until there is an answer to "who reads these, and by when".

Note the smaller version that needs no queue: a disputed plan already resolves to *no* settlement
rather than a wrong one — `stakeSettlement` returns nil when the two answers disagree, so nobody
loses points to a claim nobody adjudicated. Disagreement is already safe. Appeals only add the
ability to *overturn*, which is exactly the part that needs a human.

### "Leadership of score for activities" — settled definition, blocked on group size

A leaderboard ranking within a group: who has shown up most, planned most, followed through most.

⚠️ **It follows the same rule as the reliability score: groups yes, couples no.** A leaderboard
between two partners is the identical weaponisation risk that kept reliability out of couples, only
with a rank attached — being second of two is not a statistic, it is an accusation.
`canSeeReliability(in:)` already encodes exactly this split (`relationship.type != .couple`), and
the leaderboard must reuse it rather than inventing a second, subtly different rule.

🚧 **It cannot be built yet, and the reason is not the leaderboard.** Every group in this app holds
at most two people. `isRedeemingInvite` in `firestore.rules` permits a join only when
`participantIDs.size() == 1`, so a second person can join and a third can never. "Multiple groups"
works — you can have many pairs — but a group of three does not exist.

So a leaderboard today would always be a ranking between exactly two people, which is precisely the
harm the couples exclusion exists to prevent, wearing a "Friends" label. Building it would deliver
the risk without the thing that makes a leaderboard worth having.

**The prerequisite is groups of three or more**, and it is a real piece of work rather than a
constant to change:
- `isRedeemingInvite` needs a seat ceiling rather than `size() == 1` — the plan-invite branch
  already does exactly this with `planInviteSeats`, so the shape is known.
- Requests fan out to `recipientIDs`; turn-taking (`awaitingResponseFrom`) currently means
  "everyone who did not send the last message", which is right for two and needs deciding for
  three — does one accept settle it, or all of them?
- `partnerID(excluding:)` and `displayLabels` assume exactly one other person, in several places.

Until that is decided, the leaderboard stays specced and unbuilt. That is the honest sequence: the
ranking is the easy half.

---

## Known dead code and gaps worth clearing

Found while working nearby; small, and each removes a source of confusion:

- **`savedForLater`** is on the model, the DTO and the rules, but has **no UI surface anywhere in
  `Features/`**. "Save for later" cannot be undone because there is nothing to undo it with. Either
  build the surface or remove the field.
- **`location`** is stored on `Request` and carried through the DTO and rules, and is **rendered
  nowhere**. Dead.
- **`CloudFunctions/node_modules`** — 4,140 directories inside the Swift package root, which
  `xcodebuild` walks on every build over the network mount. Moving `CloudFunctions/` out of
  `ios/MiddleGround/` would cut minutes off each archive.
- **Achievements and the activity feed are not mirrored.** Only `GamificationStats` is, so a
  reinstall restores XP, level and streak but starts achievements and history from empty.
