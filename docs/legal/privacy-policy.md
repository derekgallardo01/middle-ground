# Privacy Policy

**Effective date:** 6 August 2026

**Applies to:** the Middle Ground iOS app

Middle Ground helps a small group of people make shared decisions together. This policy
describes exactly what the app collects, why, where it goes, and how to delete it. It describes what the software
actually does — every item below corresponds to real behaviour in the app.

## The short version

- We collect the minimum needed to show your requests to the people you paired with.
- **Location is shared only when you tap to share it**, only on a plan you already agreed to, and
  only around the time it happens. It is deleted when the plan is over. Nothing runs in the
  background and you are never tracked.
- **Your calendar is never uploaded.** If you allow calendar access, the check for whether a
  suggested time clashes happens on your phone, and no event ever leaves it.
- **We record how the app is used** — that you created or answered a request, and when — so we
  can understand and improve the product. We do **not** sell your data, run advertising, or use
  third-party trackers or ad SDKs.
- Your requests are visible to you, the people you paired with, **and to authorised Middle
  Ground staff** who may access accounts for support, safety and debugging. Every such access is
  recorded in a tamper-evident log.
- We collect **crash diagnostics** so we can fix crashes. They contain no request content.
- You can **report** abusive content and **leave a group** at any time, from inside the app.
- You can delete your account, and everything tied to it, from inside the app.

## What we collect, and why

| Data | Where it is stored | Why |
|---|---|---|
| **Display name** | `users/{your-id}` in Firebase Firestore | So the people you plan with see a name instead of an ID |
| **Account identifier** | Attached to every document you create | Determines what you are allowed to read and write |
| **Email address** | Firebase Authentication | Only if you sign in with a method that provides one. With Sign in with Apple, you may choose Apple's private relay address and we never see your real one |
| **Requests you create** — title, optional note, optional proposed time, and the responses exchanged | `requests/{id}` in Firebase Firestore | This is the product: it is the content you and the people you plan with are deciding on |
| **Group membership** — who you are paired with, and your invite code | `relationships/{id}` and `invites/{code}` | Connects a group so its members can send each other requests |
| **Notification token** | `user_tokens/{your-id}` | Lets us send a push notification when someone sends or answers a request. Only if you grant notification permission |
| **Messages you send on a plan** — what you write, and which message it replies to | `requests/{id}/messages` | So the people on a plan can talk about it. Readable by them, **and by authorised Middle Ground staff** — the same access, and the same audit log, as the plans themselves. Without it a reported message could not be looked at, and we could not act on abuse |
| **That you are typing** — a flag with no content, lasting about eight seconds | `requests/{id}/presence` | So the others on a plan can see a reply is coming. It contains no text, expires by itself, and is deleted by the server |
| **That you opened a plan** — the time you last had it open | `requests/{id}/reads` | So people can tell their message was seen. Recorded **per plan, not per message** — there is no record of which individual messages you read |
| **Days you mark yourself unavailable** — a start and an end, and nothing else | `relationships/{id}/availability/{your-id}` | So the people in your group can see when you are not free. **Only what you deliberately block out.** It carries no title, no place and no link to any calendar entry — your calendar is never read for this, and never uploaded |
| **Notification preferences** — which kinds of alert you want | `notification_settings/{your-id}` | So we only send the kinds you left switched on. Readable only by you |
| **A location you choose to share** — one coordinate, the time you shared it, and the time it expires | `requests/{id}/locations/{your-id}` | Lets the other people on an agreed plan see you are on your way. Written only when you tap **Share my location**, and only while that plan is live. Deleted automatically when it expires |
| **Progress data** — XP, streak, achievements | On your device, and mirrored to `gamification/{your-id}` | Powers the Activities tab, and means your progress survives changing phone |
| **Usage events** — that you signed up, paired, created a request, shared an invite, or responded, with a timestamp | `events` | Lets us understand how the product is actually used and where people get stuck. Records the *action*, not the words you wrote. When you join a group using somebody's code, the record also notes **whose code it was**, so we can tell how many invitations actually reach someone — that is the only place an event mentions another person |
| **A plan you asked us to look at** — which plan, its title, and what you wrote about it | `disputes/{id}` | When two people remember a plan differently, either of you can ask us to review it. Readable only by staff. **Nothing about the plan changes when you do** — a plan you disagree about already counts for nobody. Kept apart from reports below, because a disagreement is not an accusation |
| **Reports you file** — which request you reported, who you reported, the reason, and your optional note | `reports/{id}` | So we can act on harassment and abuse. Readable only by staff. Once a report has been reviewed, the record also carries **what was decided, who decided it and when** — so that a report cannot quietly go unread. Staff can add that decision and nothing else: the report itself cannot be edited by anyone, including us, because it is a record of somebody's conduct and an editable complaint is not evidence |
| **Crash diagnostics** — stack trace, device model, OS version, and the app version at the time of a crash | Firebase Crashlytics | So we can find and fix crashes. Contains no request content and no message text |
| **What became of a plan** — that a plan was agreed, happened, was called off, or did not happen, with the party size and the kind of plan | `plan_outcomes` | So we can tell how often plans people agree to actually happen. **These records contain no name, no account identifier, and no link to the plan or the people on it** — they cannot be traced back to you, which is why they are kept rather than deleted with your account |
| **That someone looked for a table** — that a booking link was opened, with the party size and the kind of plan | `booking_intents` | So we can tell how often people want to book somewhere. Recorded only when you tap the link, never when it is merely shown. **Contains no name, no account identifier and no link to the plan**, on the same basis as the row above |

We do **not** collect: contacts, photos, health data, advertising identifiers, or device
fingerprints. We do not collect location in the background, and we never read or upload your
calendar — both are explained in full below.

You can read the usage events recorded about you at any time — they are readable by your own
account and by nobody else's.

## Who can see your content

- **You and the people you paired with.** Requests are readable only by their participants, and
  this is enforced on the server, not just in the app.
- **Authorised Middle Ground staff.** A small number of accounts hold an administrator
  permission that allows access to account records and request content. It exists so we can
  provide support, investigate abuse or safety reports, and diagnose faults.
  - The permission is granted server-side and cannot be obtained by modifying the app.
  - **Every administrator access to an individual's data is written to an append-only audit
    log** that administrators cannot edit or delete.
  - We use it only for the reasons above — not for browsing, marketing, or curiosity.
- **No other app user.** Invite codes cannot be listed or enumerated — a code only works if
  someone tells it to you. Notification tokens are not readable by any app user, including you.
- **We do not sell, rent, or share your data with third parties for their own purposes.**

If you would like to know whether your account has been accessed by staff, email us and we will
tell you what the audit log shows.

## Service providers

Middle Ground uses **Google Firebase** (Google LLC) for authentication, database storage, and
push notification delivery. Firebase processes data on our behalf under Google's terms, and data
is stored on Google's infrastructure, which may be located in the United States. Google's privacy
information is at <https://firebase.google.com/support/privacy>.

Push notifications are delivered through **Apple Push Notification service**. If you sign in with
Apple, Apple handles that authentication; see <https://www.apple.com/legal/privacy/>.

Crash diagnostics are collected by **Firebase Crashlytics**, also part of Google Firebase. It
reports crashes only — stack traces and device/OS/app-version details. It does not see request
titles, notes, or messages.

These are the only third parties involved. Usage events are recorded in our own Firestore
database — there are no advertising, attribution, or third-party marketing-analytics SDKs in the
app, and no usage data is shared with anyone else.

## Reporting abuse, and leaving a group

If someone sends you something abusive, you can act on it from inside the app without contacting
us first:

- **Report it.** Open the request, tap the menu, and choose **Report this**. We review every
  report within 24 hours.
- **Leave the group.** Open **Profile → Your groups → Leave**. You immediately stop seeing each
  other's requests and they can no longer send you any. If the invite code was yours, it is
  revoked at the same time so nobody can use it to reach you again.

Reports are kept even if you later delete your account, because a report is a record about
somebody else's conduct and erasing it would remove the evidence of what you reported.

## Sign in with Apple

If you sign in with Apple, we receive an account identifier and — only if you choose to share it
— your name and an email address. Apple's Hide My Email option gives us a relay address instead
of your real one, and the app works normally either way. When you delete your account we also
revoke the Apple token issued to us, so the connection between your Apple ID and Middle Ground is
severed.

## Notifications

Notifications are optional. The app asks only when it is relevant, and declining does not limit
any other feature. If you allow them, a device token is stored so notifications can be routed to
your phone; you can turn them off at any time in Profile → Push Notifications, or in iOS
Settings. Turning them off removes the token from your account.

## Location

Location is **off unless you ask for it**, one time at a time. There is no background tracking,
no location history, and no continuous updates — the app asks iOS for **When In Use**
authorisation only, which means it cannot read your location while you are not using it.

The **Share my location** button appears only when all of these are true:

- the plan has been **accepted** by you, and
- it has a **time**, and
- that time is **near** — from an hour before it starts until four hours after.

Tapping it sends **one coordinate**, once. It is stored against that one plan and is readable
only by the people on it. Each point carries an expiry that the server sets and the app cannot
choose, and Firestore deletes it automatically when that expiry passes; the app also hides points
that have lapsed. Nothing is written to any other plan, and there is no record of where you have
been.

Declining location permission does not limit anything else in the app. Every other feature works
exactly the same.

## Calendar

If you allow calendar access, the app checks whether a suggested time clashes with something you
already have booked, and warns you before you agree to it.

**This happens entirely on your phone.** Your events are never uploaded, never stored on our
servers, and never shown to anyone you are planning with — they see only that you flagged a
clash, if you tell them. Access is **read-only**: the app does not create, change, or delete
anything in your calendar.

Declining calendar access does not limit anything else. You simply do not get the clash warning.

**Blocking out time is a separate thing, and it is the only part anyone else sees.** You can mark
days you are not free, and the people in your groups can see those. They are typed by you — the
app never reads your calendar to fill them in, and what your group sees is a start and an end with
no title, no place and no connection to anything in your calendar.

The app reads **every calendar your phone already has**, whether that is iCloud, Google, Exchange
or anything else you have added in iOS Settings. It does not connect to those services itself and
holds no account of yours.

## Deleting your account and data

Open **Profile → Delete Account**. After you confirm:

- Your authentication account is deleted and, for Sign in with Apple, the token we hold is
  revoked.
- The progress data stored on your device is removed with the app's data.
- Your profile, notification token, notification preferences, invite codes, group membership,
  progress data, usage events, **every message you sent on any plan**, and requests that involved
  only you are erased from our database.
  Requests shared with other people have your participation removed so they keep their own
  history.
- Any location you shared expires on its own schedule — hours after the plan it belonged to —
  and is deleted by the server whether or not you delete your account.

The only records **not** erased are the two anonymous tallies described in the table above — what
became of a plan, and that someone opened a booking link. Neither carries anything that identifies
you or the plan, so there is nothing in them to erase and no way to find "yours". They are counts,
not history.

The erasure happens while you are still signed in, as part of the deletion itself — not on a
delay and not in a queue. An automated server-side job runs the same cleanup afterwards to catch
anything the app could not reach (for example if your phone lost connectivity mid-way).

Deletion is permanent and cannot be undone. There is no waiting period and you do not need to
contact us to do it.

The things not erased are any **report you filed about someone else**, and any **plan you asked
us to look at** — both are records of something between two people, and erasing one side of a
disagreement would leave the other half of it standing alone.

## Retention

Your content is kept until you delete it or delete your account, and is erased when you do.
**Usage events are additionally deleted automatically 90 days after they are recorded**, whether
or not you delete your account. **A location you shared is deleted automatically when the plan it
belongs to is over** — hours, not days — whether or not you delete your account. We do not keep backups of deleted accounts for our own purposes.

## Children

Middle Ground is not directed at children under 13, and we do not knowingly collect their data.
If you believe a child has provided us data, contact us and we will remove it.

## Your rights

Depending on where you live, you may have the right to access, correct, export, or erase your
data, and to object to processing. The app's delete function satisfies erasure directly. For
anything else, contact us and we will respond within 30 days.

## Security

Access is enforced by server-side security rules, not just by the app: every read and write is
checked against who you are and which conversations you belong to. Data is encrypted in transit,
and at rest by our provider. No system is perfectly secure, but we do not store passwords
ourselves and we collect as little as we can.

## Changes

If this policy changes materially we will update the effective date above and note the change in
the app's release notes.

## Contact

**support@middleground.app**
