# Timeline

Where Middle Ground has got to, and what is being built next. The [changelog](/changelog) is the
build-by-build record; this is the shape of it.

## So far

<ul class="timeline">
<li class="done"><span class="when">18 July 2026</span><span class="what">First TestFlight build</span><p>The core loop working end to end: propose a plan, negotiate it, land on a time.</p></li>
<li class="done"><span class="when">26 July 2026</span><span class="what">Private beta opens</span><p>Real people using it with real plans, which is where the assumptions started meeting reality.</p></li>
<li class="done"><span class="when">30 July 2026</span><span class="what">Groups, categories and templates</span><p>More than one group per person, each with its own invite code. Plans gained categories and one-tap templates for the decisions people make constantly.</p></li>
<li class="done"><span class="when">31 July 2026</span><span class="what">Version 1.0 submitted to the App Store</span><p>Alongside the feature that everything about reliability depends on: the app asking, afterwards, whether a plan actually happened.</p></li>
<li class="done"><span class="when">1 August 2026</span><span class="what">Commitment, and the boundaries around it</span><p>Points staked on a plan happening. Single-plan invites. A reliability score with couples deliberately excluded. Notifications people control, and location scoped to one plan and deleted afterwards.</p></li>
<li class="now"><span class="when">Now</span><span class="what">In App Store review</span><p>Version 1.0 is with Apple. Development continues on TestFlight in the meantime.</p></li>
</ul>

## What's next

<ul class="timeline">
<li class="now"><span class="when">In progress</span><span class="what">Groups of more than two</span><p>Every group today holds two people. Three or more changes what a plan means — whether one acceptance settles it, and what happens when one person is out and the others are still going. That question is being worked through before the code, not after it.</p></li>
<li><span class="when">Next</span><span class="what">Standing on reliability</span><p>A leaderboard within a group, following the same rule the reliability score already does: groups yes, couples no. It waits on groups of three, because a ranking between exactly two people is not a ranking.</p></li>
<li><span class="when">Next</span><span class="what">Late cancellations</span><p>Calling something off an hour before is not the same as calling it off on Tuesday, and the app should be able to tell the difference without turning into a punishment.</p></li>
<li><span class="when">Exploring</span><span class="what">Places worth going</span><p>The venue list is live and curated. Reservations and venue partnerships are the half that needs agreements rather than engineering.</p></li>
<li><span class="when">Exploring</span><span class="what">Disputes, and who settles them</span><p>Two people can disagree about whether a plan happened. Today that safely resolves to nothing rather than to a wrong answer. Going further means someone reviewing appeals — a standing commitment, not a feature.</p></li>
</ul>

---

## How it gets built

Four days of the history above produced sixty-eight commits, and nearly every one carries a written
explanation of the reasoning and what was rejected. Security rules are covered by an automated suite
that runs on every change, because the rules encode the entire privacy model and are easy to get
subtly wrong while looking correct.

The pattern worth naming: several of the features above shipped *smaller* than first specced.
A reliability score that couples cannot see. Location that expires. A leaderboard held back rather
than shipped between two people. Restraint is most of the product decision-making here.
