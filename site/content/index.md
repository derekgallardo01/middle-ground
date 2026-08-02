<div class="hero">
<span class="eyebrow">Version 1.0 · in App Store review</span>
<h1>Plans die in <span class="tagline">the back-and-forth</span>.</h1>
<p>Middle Ground is an iOS app for the decisions two or more people have to make together — dinner, the weekend, who is actually free on Thursday. It turns an open-ended conversation into something with a shape, and an answer.</p>
<div class="actions">
<a class="btn btn-primary" href="/changelog">See what's shipping →</a>
<a class="btn btn-secondary" href="/timeline">Timeline</a>
</div>
</div>

---

## The problem

Nobody struggles to *have* the idea. They struggle to land it.

"Dinner Friday?" becomes eleven messages, two maybes and no reservation. The plan does not fail because anyone objected — it fails because nothing ever converted the conversation into a decision, and the thread scrolled away.

Group chat is built for talking. It is not built for deciding.

## What Middle Ground does

<div class="cards">
<div class="card">
<span class="ico">📨</span>
<h3>A request, not a message</h3>
<p>Someone proposes something specific. It has a time, a place and a state — so it can be accepted, countered or declined rather than ignored.</p>
</div>
<div class="card">
<span class="ico">🤝</span>
<h3>Countering that moves the plan</h3>
<p>"Sunday instead?" carries a new time. Accepting it actually reschedules the plan, rather than leaving everyone to work out what was agreed.</p>
</div>
<div class="card">
<span class="ico">✅</span>
<h3>Did it happen?</h3>
<p>Afterwards, the app asks. That single answer is what makes reliability measurable instead of a feeling people carry silently.</p>
</div>
<div class="card">
<span class="ico">📆</span>
<h3>It knows your calendar</h3>
<p>A proposed time is checked against what is already in your calendar, on device. Nothing about your events leaves the phone.</p>
</div>
<div class="card">
<span class="ico">🎯</span>
<h3>Something riding on it</h3>
<p>Both people can stake points on a plan actually happening. Never one at the other's expense — the record says whether it happened, not whose fault it was.</p>
</div>
<div class="card">
<span class="ico">📍</span>
<h3>Location, scoped to one plan</h3>
<p>Share where you are for the hours around a plan you both agreed to. One point per tap, not a trail, and it is deleted afterwards.</p>
</div>
</div>

## How it is built

The interesting decisions in this product are the ones about restraint.

**A reliability score exists, and couples are excluded from it.** A number your partner can quote back at you stops being feedback and becomes an argument. Groups — where a no-show costs someone else their evening or their booking — keep it. That split is enforced in code, not in a guideline.

**Location is something you hand over, not something the app knows.** Sharing is possible only while an accepted plan is inside its window, it sends a single point rather than starting a feed, and it is deleted when the window closes. The window is enforced on the server against the server's own clock, because a rule that lives only in the app is a rule a tampered app does not have.

**Every privacy boundary is a tested one.** The security rules that decide who can read what are covered by an automated suite that runs on every change — because those rules encode the entire privacy model, and they are the kind of thing that is easy to get subtly wrong and impossible to verify by reading.

## Where it is

In private beta on TestFlight, with version 1.0 submitted to the App Store. Development is active and continuous — the [changelog](/changelog) is the honest record of it, and the [timeline](/timeline) covers what is being built next.

<div class="actions">
<a class="btn btn-primary" href="/changelog">Read the changelog</a>
<a class="btn btn-secondary" href="mailto:support@middleground.app">Get in touch</a>
</div>
