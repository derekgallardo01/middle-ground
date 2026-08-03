# OpenTable — what we submitted

A record of the application as sent, kept because the next conversation will be held against it.
If they come back with questions, or if we reapply at a different tier in a year, the thing we
will want is not a summary — it is the exact claim we made about volume and use case.

## Submission facts

| | |
|---|---|
| Submitted | Yes — 2 August 2026, by Derek Gallardo |
| Market stated | Miami |
| Stage stated | Early-stage iOS app, pre-launch on the App Store at time of writing |
| Exact wording, tier and volume claimed | **Not recorded.** Submitted directly; the form's contents were not captured |

> The figure claimed about volume is the one a later conversation is most likely to be held
> against, and it is not recoverable from this repo. If it can still be found — in a sent
> confirmation email, or the form's own record — it is worth pasting here. If not, treat the facts
> below as the only verifiable ground and do not reconstruct the number from memory.

## Answer given

The prepared answer is in [opentable.md](opentable.md). The submitted text was not captured, so
treat that file as *what we intended to say* rather than a transcript of what went in the box.

## What was true on the day

Recorded so a future claim can be checked against the same facts rather than re-estimated:

- App Store state: 1.0 submitted 2 August 2026, `WAITING_FOR_REVIEW`, build `202608021918`.
- Venue handling: curated list in Firestore, no booking integration of any kind.
- Follow-through data: `plan_outcomes` began recording on 2 August 2026. **Anything before that
  date does not exist and cannot be reconstructed** — worth stating plainly if they ever ask for
  history, rather than estimating backwards.

## Status page

<https://status-api.opentable.com> — a StatusDashboard-hosted page. No RSS/Atom feed and no public
JSON API (`/api/v1/*`, `/api/v2/*` all 404); the only subscription route is the form at
`/subscribe`, which POSTs `email` plus one repeated `service` field per service to
`subscribe/email`.

**Requested 2 August 2026** for `derekgallardo01@gmail.com`, on the two services that bear on us:

| ID | Service | Why |
|---|---|---|
| 5720 | Consumer API | Directory, Availability Search and Booking — what a `ReservationProvider` implementation would call |
| 5721 | Network Access API | Partner-facing Inventory and Onboarding APIs — relevant once there is an agreement |

Not subscribed to 5722 (Restaurant Partner API — POS, Sync, CRM): it serves restaurants running
OpenTable's till systems, which is not us.

> ⚠️ **Not active yet.** The server replied "we have just sent you an email to confirm your
> subscription". It only takes effect when the validation link in that email is clicked, which
> cannot be done from here. If the application used a different address, resubscribe with that one
> instead — alerts should arrive where the rest of the correspondence does.

## Why the follow-through data matters here

The argument in [opentable.md](opentable.md) rests on no-shows. That claim is only worth making if
it can be evidenced, and the evidence is `plan_outcomes` — which is why it was built before any
answer was needed rather than after they asked. See `PlanOutcome` for why the rows are anonymous
and therefore survive.

By the time this conversation resumes, the useful number is the ratio: of plans recorded `agreed`,
how many reached `attended`, and how the `cancelled_late` share compares to `cancelled_early`.
