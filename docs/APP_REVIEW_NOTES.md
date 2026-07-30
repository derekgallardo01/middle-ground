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

## Building the upload

```sh
cd ios/MiddleGround
MG_P12_PASSWORD=... ./Scripts/export-ipa.sh
```

That archives, exports a distribution-signed `.ipa`, asserts the entitlements are right, and
runs App Store Connect validation. It fails loudly if the payload comes out development-signed.

Verified output of the last run:

| Check | Value |
|---|---|
| Signing authority | `Apple Distribution: Derek Gallardo (9U3ZSABZG7)` |
| `aps-environment` | `production` |
| `get-task-allow` | `false` |
| `beta-reports-active` | `true` |
| Profile | `iOS Team Store Provisioning Profile` |

**Validation currently stops at one thing** — `Cannot determine the Apple ID from Bundle ID
'app.middleground.MiddleGround'`. That is the missing App Store Connect app record, not a
problem with the build. Create the record and the same command validates and uploads.

The distribution certificate is backed up at `~/Desktop/MiddleGround-Distribution.p12`. Move it
somewhere durable — if it is lost the certificate has to be revoked and reissued, and any build
signed with it stops being reproducible.

## Signing: what was wrong, and what fixed it

Two things blocked the first archive, and one blocked the export. Recorded because none of them
announce themselves clearly.

**The App ID had no capabilities at all.** Not Push, not Sign in with Apple — so no provisioning
profile could cover the entitlements, and the archive failed with "doesn't include the Push
Notifications capability". Both were attached via the App Store Connect API.

**There was no Apple Distribution certificate** in the account. One was created via the API
(`POST /v1/certificates` with a locally generated CSR).

**Importing the certificate and key separately into the login keychain produced an unusable
identity.** `security find-identity` listed it happily, but every signing attempt died with
`errSecInternalComponent` and a misleading "unable to build chain to self-signed root" warning.
Ruled out along the way, all of which checked out fine:

- the key and certificate matched (identical modulus)
- both WWDR intermediates were present and unexpired (G3 → 2030, G6 → 2036)
- `security verify-cert -p codeSign` passed for the certificate
- the session was Aqua, not SSH, so a GUI prompt could have been shown

The fix was to bundle key + leaf + intermediate into a **PKCS#12** and import that into a
dedicated keychain with `security set-key-partition-list`. `Scripts/export-ipa.sh` does this.

**Also worth knowing:** distribution signing happens at *export*, not at archive. Under
`CODE_SIGN_STYLE: Automatic` Xcode signs the archive with the development identity by design and
refuses a manually set `CODE_SIGN_IDENTITY`. An archive showing `aps-environment: development`
is therefore expected and is not what gets uploaded.

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
