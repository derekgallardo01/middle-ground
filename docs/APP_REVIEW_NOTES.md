# App Review notes

Paste the **Review notes** section below into App Store Connect → App Review Information.
Everything else here is context for us, not for Apple.

---

## Before every submission

1. **Seed fresh demo groups and collect the codes.**
   ```sh
   cd ios/MiddleGround
   node Scripts/seed-review-data.mjs --count 3
   ```
   It prints three invite codes. Paste them into the notes below.

   **Do not reuse codes from a previous submission.** `isRedeemingInvite` in `firestore.rules`
   requires `participantIDs.size() == 1`, so a code stops working the instant one reviewer
   redeems it. Three codes covers a resubmission and a second reviewer.

2. **Check the legal pages resolve** (they are linked from inside the app):
   ```sh
   for p in privacy terms support; do
     curl -sS -o /dev/null -w "%{http_code} $p\n" "https://middle-ground-8fd13.web.app/$p"
   done
   ```

3. **Bump the build number** — App Store Connect rejects a duplicate:
   ```sh
   xcodebuild ... MG_BUILD_NUMBER=$(date -u +%Y%m%d%H%M) archive
   ```

4. **Clean up after the review concludes:**
   ```sh
   node Scripts/seed-review-data.mjs --clean
   ```

---

## Review notes

> **Middle Ground needs two people — please use one of the codes below.**
>
> The app is a shared decision-making tool for two people (couples, housemates, family). Until
> your account is paired with someone, there is intentionally nothing to show: no requests, no
> calendar entries, and the compose button stays disabled because there is no one to send to.
>
> **To see the full app in about a minute:**
>
> 1. Tap **Sign in with Apple** and complete sign-in as yourself.
> 2. Go to the **Profile** tab.
> 3. Under **Connect**, enter one of these invite codes and tap **Join with a code**:
>
>    - `CODE1`
>    - `CODE2`
>    - `CODE3`
>
>    (Each code works once. If one is rejected, please try the next.)
>
> 4. You are now paired with a demo account that already has a short request history. The
>    **Requests** tab shows two pending requests you can accept, decline, counter or reschedule,
>    plus one already answered. The **Calendar** tab shows anything with a proposed time, and
>    **Activities** shows the XP and streak earned by responding.
> 5. Tap **+** on Requests to send one back to the demo partner.
>
> **Account deletion** (Guideline 5.1.1(v)): Profile → **Delete Account**. It deletes the account
> and its data immediately; there is no waiting period and no need to contact us.
>
> **User-generated content** (Guideline 1.2):
> - **Report:** open any request → the **⋯** menu → **Report this**.
> - **Block / leave:** Profile → **Your groups** → **Leave**. This removes you from the group,
>   stops the other person from sending you anything, and revokes the invite code if it was
>   yours.
> - Reports are reviewed within 24 hours. Contact: **support@middleground.app**
>
> **Push notifications** are optional and requested during onboarding with an explanation. The
> app deliberately does not declare the `remote-notification` background mode — all pushes are
> alert-style.
>
> **There is an Admin tab in the binary.** It is gated on a server-issued Firebase custom claim,
> not a client flag, and every query behind it is independently refused by our Firestore security
> rules for accounts without that claim. A reviewer's account will not have it, and forcing the
> screen open in a modified build returns permission errors and no data. Operator access to
> account data is disclosed in our Privacy Policy and written to an append-only audit log.
>
> **Privacy Policy:** https://middle-ground-8fd13.web.app/privacy
> **Terms:** https://middle-ground-8fd13.web.app/terms
> **Support:** https://middle-ground-8fd13.web.app/support

---

## Answers that must match the privacy manifest

App Store Connect's data-collection questionnaire has to agree with `App/PrivacyInfo.xcprivacy`
and with the published policy. Declare **all** of the following as collected and **linked** to
the user, none used for tracking:

| Category | Type | Purpose |
|---|---|---|
| Contact Info | Name | App Functionality |
| Contact Info | Email Address | App Functionality |
| Identifiers | User ID | App Functionality |
| Identifiers | Device ID | App Functionality |
| Usage Data | Product Interaction | Analytics, App Functionality |
| Diagnostics | Crash Data | App Functionality |
| User Content | Other User Content | App Functionality |

Answer **No** to "Do you or your third-party partners use data for tracking?"

## Blocker: no Apple Distribution certificate

`security find-identity -v -p codesigning` lists exactly one identity —
**Apple Development: Derek Gallardo** — and no Apple Distribution certificate. Consequences:

- `xcodebuild ... archive` **succeeds**, but automatic signing falls back to the development
  "iOS Team Provisioning Profile". The resulting archive carries `get-task-allow: true` and
  `aps-environment: development`, so it cannot be uploaded to App Store Connect, and push would
  not work even if it could.
- Fixing it needs the Apple Developer account: Xcode → Settings → Accounts → Manage
  Certificates → **+** → Apple Distribution. (Or generate a CSR in Keychain Access and request
  the certificate in the developer portal.)

Everything else on the build side is verified working: the Release configuration compiles, the
archive is produced, `PrivacyInfo.xcprivacy` is embedded, `ITSAppUsesNonExemptEncryption` is
present, and `CFBundleVersion` picks up `MG_BUILD_NUMBER` (`202607301940` on the last run).

The bundle ID's capabilities were missing entirely and have been enabled via the App Store
Connect API — `PUSH_NOTIFICATIONS` and `APPLE_ID_AUTH` are now attached to
`app.middleground.MiddleGround`, which is what unblocked the archive.

## Known gaps at time of writing

- **Sign in with Apple and push have never run on physical hardware.** Simulators return
  `AuthorizationError 1000` for Sign in with Apple, so the only sign-in method Release ships is
  unproven. Install the build from TestFlight on any iPhone before submitting.
- **App Check enforcement is off** in the Firebase console. The provider is wired
  (`MGAppCheckProviderFactory`), but App Attest cannot be exercised on a simulator and enabling
  enforcement unverified would lock every client out of Firestore.
- **Cloud Functions are not deployed** — the project is still on the Spark plan. Account
  deletion does not depend on them: `AccountDataPurger` performs the erasure from the client
  before the auth account is removed. Push notifications *do* depend on them and will not be
  delivered until Blaze is enabled and `firebase deploy --only functions` has run.
- **No TTL on the `events` collection.** Firestore TTL policies require Blaze — the
  `fieldOverride` deploys with HTTP 403 and fails the whole firestore deploy. Usage events are
  currently deleted only when the account is deleted. The privacy policy is worded to match; if
  you enable the TTL later, restore the 90-day retention sentence in
  `docs/legal/privacy-policy.md` at the same time and re-run `build.py`.

## What is already live

| Thing | State |
|---|---|
| Legal pages | Deployed. `/privacy`, `/terms`, `/support` all 200 with real content; unknown paths 404 |
| Firestore rules | Deployed, 64/64 emulator tests passing |
| Firestore indexes | Deployed — including `events (userID, at DESC)` and `requests (recipientIDs, status)` |
| Cloud Functions | **Not** deployed (Spark plan) |
