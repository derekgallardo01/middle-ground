# Middle Ground — Roadmap

Captured from a product brainstorm on 2026-07-31. This document has two halves:

- **Specs** — the Categories & Groups cluster, worked up in enough detail that someone (or an
  agent) can pick one up and build it without making product decisions on the owner's behalf.
- **Backlog** — everything else, grouped and sized, deliberately *not* specced until promoted.

Anything not in the Specs section is an idea, not a commitment. Where a decision has already been
made it says so; where one is still open it says that too, rather than quietly picking.

---

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

## Reliability & reputation — L

**Decided: penalties are in, with an appeals path.**

Raw items: popularity score · missed reservations subtract · missed trips · record of people missing
· cancellation reasons (list) · cancel three times in a row → penalty · punishment · closure ·
appeal rejection via moderator/staff · rejection reasons · review other group members · leaderboard
of activity scores · people rate the activities · motivation betting *(undefined — needs a
definition before it can be specced)*.

Constraints that come with the decision:

- **A punitive score inside a couple is usable as a weapon as easily as a signal.** Needs an
  explicit answer to: what can the *other* partner see, and can a score be used to pressure someone?
  The safest split is the one already discussed — penalties apply to venue bookings and group/public
  plans where a no-show costs someone money; couples keep a positive-only score.
- **Appeals imply staffing.** A moderator queue is an operational commitment, not a feature.
- Every penalty needs a recorded reason, or the score is unexplainable — the same defect just fixed
  on Growth Score, at higher stakes.
- App Review guideline 1.2 (user-generated content) applies once users rate each other: reporting,
  blocking and a response window are required. Reporting already exists (`reports` collection).

## Identity & trust — L

In-person identity verification · gate guardian *(undefined)* · authorised representative
*(undefined)* · start at 0.

Identity verification means handling government ID, which brings data-protection obligations well
beyond anything the app does today, plus an App Privacy disclosure and near-certain review
scrutiny. Do not start casually. The two undefined terms need a definition first.

## Venues & partners — XL

Restaurants · OpenTable reservations · restaurant sponsors · gyms · linking restaurant locations ·
list of restaurants.

Blocked on commercial agreements, not engineering. OpenTable's partner API is not open
self-service. Sequence: confirm access first, then spec.

## Calendar integration — M

Google Calendar / Apple Calendar · show whether an accepted slot is already booked.

Apple Calendar via EventKit is the cheaper half and needs only a purpose string plus an App Privacy
update. Google Calendar needs OAuth and a verification review. High user value: the app already
knows `proposedTime`, so a conflict check is a small addition to
`Features/Calendar/CalendarViewModel.swift`.

## Location sharing — M, gated on privacy work

Location sharing · only active plans are shared, never inactive · starts on the day of the plan.

The scoping instinct is good — time-boxed, plan-scoped sharing is far easier to justify than
continuous tracking. Still requires `NSLocationWhenInUseUsageDescription`, App Privacy answers, and
a clear in-app explanation. Treat the "only active, only on the day" constraint as a hard
requirement, not a setting.

## Activity categories — S, mostly covered by S1

Fishing · basketball · workout · events · dating · chill · activity levels · skill points · goals.

The first four are *content* within categories, not new categories. Skill points and levels overlap
the existing gamification system — extend `GamificationRules` rather than building a parallel one.

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
