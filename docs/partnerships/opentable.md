# OpenTable — ideal partnership

Answer prepared for OpenTable's partnership enquiry, 2 August 2026.

The argument to lead with is **no-shows**, not features. Every app wants booking access and most
offer OpenTable nothing back. Middle Ground already measures whether a plan happened, which is the
problem restaurants lose the most money to. That is the asset — the booking integration is the ask.

Scale is stated honestly: early-stage, Miami-only. Overstating volume to a partnerships team gets
found out at the first reporting call.

---

## Where we sit

Middle Ground is where a small group decides *whether*, *when*, and *with whom* — the step that
happens before anyone opens a booking app. By the time a plan is agreed we already hold the party
size, the date and time, the neighbourhood, and the fact that every person has said yes.

Today a plan ends with a suggested place and a Maps pin (see `Venue.swift` — the curated half of
the restaurants idea, which needs no partnership). The natural next step is a table.

## What we want from OpenTable

1. **Availability lookup** — restaurants and open times near a location, queried by a *window*
   rather than a single slot. Our users agree on "Friday evening", so we can fill 6:15 and 9:30 as
   readily as 8:00.
2. **Inline booking** — create a reservation from inside an agreed plan, using the party size and
   time already held, without re-asking the user anything.
3. **Modify and cancel** — plans change, and the app is built around that. Changes should reach the
   restaurant immediately and automatically.
4. **Confirmation state** — booking status written back onto the plan so the group sees one source
   of truth.

## What OpenTable gets

- **Pre-committed demand.** Not browsers: groups who have already agreed on a night out, with party
  size settled.
- **Materially fewer no-shows.** Reliability is the core mechanic — the app asks afterwards whether
  a plan happened, tracks who follows through, warns people *before* they cancel late, and lets
  groups stake points on turning up.
- **Cancellations that arrive early**, because cancelling here is a deliberate, tracked act rather
  than silence.
- **Off-peak fill**, since we influence the time before it is fixed.

## Shape

A Miami pilot on affiliate or per-seated-cover terms. Start with availability plus deep-linked
booking; expand to in-app reservations once volume justifies it.

## Phasing

| Phase | Needs from OpenTable | Ships when |
|---|---|---|
| 1 | Availability read + deep link | Integration approved |
| 2 | Create / modify / cancel a reservation | Pilot terms signed |
| 3 | Reliability signal shared back on booked covers | Volume justifies it |

Phase 3 is the one worth protecting in negotiation — it is the part nobody else can offer, and it
should be priced rather than given away.
