# Privacy Policy

**Effective date:** 30 July 2026

**Applies to:** the Middle Ground iOS app

Middle Ground helps two people make shared decisions together. This policy describes exactly
what the app collects, why, where it goes, and how to delete it. It describes what the software
actually does — every item below corresponds to real behaviour in the app.

## The short version

- We collect the minimum needed to show your requests to the person you paired with.
- **We do not track you.** No advertising, no analytics SDKs, no third-party trackers, no data
  sold or shared for marketing.
- Your requests are visible only to you and the person you paired with.
- You can delete your account, and everything tied to it, from inside the app.

## What we collect, and why

| Data | Where it is stored | Why |
|---|---|---|
| **Display name** | `users/{your-id}` in Firebase Firestore | So the person you pair with sees a name instead of an ID |
| **Account identifier** | Attached to every document you create | Determines what you are allowed to read and write |
| **Email address** | Firebase Authentication | Only if you sign in with a method that provides one. With Sign in with Apple, you may choose Apple's private relay address and we never see your real one |
| **Requests you create** — title, optional note, optional proposed time, and the responses exchanged | `requests/{id}` in Firebase Firestore | This is the product: it is the content you and your partner are deciding on |
| **Group membership** — who you are paired with, and your invite code | `relationships/{id}` and `invites/{code}` | Connects two people so they can send each other requests |
| **Notification token** | `user_tokens/{your-id}` | Lets us send a push notification when your partner sends or answers a request. Only if you grant notification permission |
| **Progress data** — XP, streak, achievements, activity history | **On your device only** (`UserDefaults`) | Powers the Activities tab. This never leaves your phone and is not sent to any server |

We do **not** collect: contacts, photos, location, calendars, health data, advertising
identifiers, or device fingerprints.

## Who can see your content

- **You and the person you paired with.** Requests are readable only by their participants, and
  this is enforced on the server, not just in the app.
- **Nobody else.** Invite codes cannot be listed or enumerated — a code only works if someone
  tells it to you. Notification tokens are not readable by any app user, including you.
- **We do not sell, rent, or share your data with third parties for their own purposes.**

## Service providers

Middle Ground uses **Google Firebase** (Google LLC) for authentication, database storage, and
push notification delivery. Firebase processes data on our behalf under Google's terms, and data
is stored on Google's infrastructure, which may be located in the United States. Google's privacy
information is at <https://firebase.google.com/support/privacy>.

Push notifications are delivered through **Apple Push Notification service**. If you sign in with
Apple, Apple handles that authentication; see <https://www.apple.com/legal/privacy/>.

These are the only third parties involved. There are no analytics, attribution, or advertising
SDKs in the app.

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

## Deleting your account and data

Open **Profile → Delete Account**. After you confirm:

- Your authentication account is deleted and, for Sign in with Apple, the token we hold is
  revoked.
- The progress data stored on your device is removed with the app's data.
- Your profile, notification token, invite codes, group membership, and requests that involved
  only you are erased from our database. Requests shared with your partner have your
  participation removed so they keep their own history.

Deletion is permanent and cannot be undone. There is no waiting period and you do not need to
contact us to do it.

> **Current status:** the server-side erasure step described above runs as an automated cleanup
> job. If that job is not yet enabled on our backend at the time you delete, your account and
> on-device data are removed immediately and the shared records are erased as soon as it runs.
> We will remove this note once the job is permanently enabled.

## Retention

Your content is kept until you delete it or delete your account. We do not keep backups of
deleted accounts for our own purposes.

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
