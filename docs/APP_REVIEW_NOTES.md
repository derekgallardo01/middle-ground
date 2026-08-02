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
>    - `6XRXSC`
>    - `TSF64V`
>    - `5F2YDB`
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

## Submission checklist — live state

| Item | State |
|---|---|
| Build 1.0.0 (202607302101) | Uploaded, VALID, attached to version 1.0 |
| Description, keywords, support URL | Set |
| Privacy Policy URL | Set |
| Primary / secondary category | Lifestyle / Productivity |
| Screenshots (5 × 1320×2868) | Uploaded, COMPLETE |
| Age rating, price schedule | Set |
| Review notes + contact | Set — includes the three verified invite codes below |
| App Privacy questionnaire | Completed (web UI — not verifiable via API) |
| Blaze billing | Enabled |
| Cloud Functions | Deployed — notifyNewRequest, notifyRequestResponse, onUserDeleted |
| `events` TTL | 90-day policy live |
| **Device test on real hardware** | **NOT DONE — the last unverified path** |

App Privacy is not exposed by the App Store Connect API (`appPrivacyDetails`, `appDataUsages`
and four related paths all return 404), so it can only be completed and confirmed in the web UI.

**It must say data IS collected.** `App/PrivacyInfo.xcprivacy` declares seven data types, and
Apple cross-checks the privacy manifest in the binary against the nutrition label. Answering
"Data Not Collected" would contradict both the manifest and the published policy, and is caught
at review.

## The 1.0.1 submission — do these together

Decided deliberately: **1.0 ships as it is**, then everything since follows as 1.0.1. A first
submission attracts the most scrutiny, and 1.0's binary is the smaller surface — adding location, a
new permission prompt and a data-collection declaration to it would widen that surface at the worst
moment. 1.0 also keeps its place in the queue, which changing the build would forfeit.

What 1.0 does **not** have, and 1.0.1 will: groups of more than two · calling off an agreed plan ·
notification preferences · location sharing · curated venues · the badge-count fix · the empty-state
flash fixes · the rebuilt plan screen · the speed and motion passes.

When 1.0 is approved, in one pass:

1. **Bump the version.** `MARKETING_VERSION` in `App/project.yml:25` is the literal `"1.0.0"` and has
   never changed. Deliberately not bumped in advance: if 1.0 is rejected and needs a replacement
   build, that build must still say 1.0.0.
2. **App Privacy → add Coarse Location.** Linked, not tracking, App Functionality. Precise Location
   stays off. See the section above — this is the web form only; the API has no endpoint for it.
3. **Refresh the review-note invite codes.** They are single-use, and the three in the notes below
   were consumed by the 1.0 review. Re-run the seed script and paste the new ones.
4. **Mention the new permission prompts** in the review notes. A reviewer will now see a location
   prompt and a calendar prompt that 1.0 never showed, and unexplained prompts invite questions.
5. **Archive from a committed tree**, upload, attach, submit.

⚠️ Before any of that: install the latest TestFlight build on a real device and put a three-person
plan through it, including a decline. Groups of three and late cancellation both changed what
declining does — which is core to the two-person flow already live in 1.0 — and no human has used
either on hardware.

## Answers that must match the privacy manifest

App Store Connect's data-collection questionnaire has to agree with `App/PrivacyInfo.xcprivacy`
and with the published policy. Declare **all** of the following as collected and **linked** to
the user, none used for tracking:

| Category | Type | Purpose |
|---|---|---|
| **Location** | **Coarse Location** | **App Functionality** — ⚠️ new, see below |
| Contact Info | Name | App Functionality |
| Contact Info | Email Address | App Functionality |
| Identifiers | User ID | App Functionality |
| Identifiers | Device ID | App Functionality |
| Usage Data | Product Interaction | Analytics, App Functionality |
| Diagnostics | Crash Data | App Functionality |
| User Content | Other User Content | App Functionality |

Answer **No** to "Do you or your third-party partners use data for tracking?"

### ⏳ Timing: answer this WITH the next submission, not before it

Verified rather than assumed: location landed in commit `2d59e2e` on 1 August 17:59, and version
1.0 is attached to build `202607311812`, built 31 July 18:12. **The binary awaiting review contains
no location code and no location entry in its manifest.**

So adding Coarse Location to App Privacy *now* would tell the App Store listing that the app
collects location while the app people can actually download does not. Over-declaring is not the
dangerous direction — under-declaring is — but it makes the listing untrue and hands a reviewer a
mismatch to query.

Do it in the same pass as submitting a build from `202608012232` onward, which is the first build
whose manifest declares it.

Note also: **this cannot be automated.** The App Store Connect API has no data-usage endpoints —
`/v1/apps/{id}/appDataUsages`, `/v1/appDataUsages`, `/v1/appDataUsageCategories` and the publish
state all return 404. App Privacy is the web form only.

### ⚠️ Location is new and must be answered before the next submission

Plan-scoped location sharing is in the build. The App Privacy answers in App Store Connect are
**not** updated automatically by the manifest — `App/PrivacyInfo.xcprivacy` and the questionnaire
are two separate declarations, and a mismatch is a rejection.

Answer it as: **Coarse Location**, **linked** to the user, **not** used for tracking, purpose
**App Functionality**. Precise Location is *not* collected — `desiredAccuracy` is
`kCLLocationAccuracyHundredMeters`.

What the reviewer should be told, and what is true:

- Sharing is a tap. Nothing is collected in the background and there is no tracking; the app uses
  `requestLocation()`, which returns one fix and stops.
- Authorisation is **When In Use** only. There is no `Always` request and no background location
  mode in the entitlements.
- A shared point is readable only by the participants of that one plan, and only while the plan is
  inside its window — an hour before its time until four hours after. This is enforced in
  `firestore.rules` against the server clock, not just in the app.
- Points are deleted, not archived: Firestore TTL on `expiresAt`, plus a client filter because TTL
  deletion is promised within 24 hours rather than instantly.

The calendar permission added earlier is read-only and stays on the device, so it collects nothing
and needs no questionnaire row — but `NSCalendarsFullAccessUsageDescription` is new since 1.0 and
a reviewer will see the prompt.

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

**Status: validated and uploaded.** `VERIFY SUCCEEDED with no errors`, then `UPLOAD SUCCEEDED`
— build `202607302101` of version 1.0.0, delivery UUID `de249814-36c3-4149-906f-4ce28b1f2bfd`.

The App Store Connect record is **"Middle Ground: Decide Together"** (app id `6796479061`).
The name "Middle Ground" was already reserved by another account; nothing in the build changed
as a result — the bundle ID is still `app.middleground.MiddleGround` and `CFBundleDisplayName`
is still `Middle Ground`, so the home-screen name is unaffected.

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
- **Push has never been delivered end to end.** Blaze is enabled and all three functions are
  deployed, and the APNs key is uploaded — but no push has actually arrived on a device, because
  no build has run on one.

## What is already live

| Thing | State |
|---|---|
| App Store Connect record | Created — "Middle Ground: Decide Together", app id `6796479061` |
| Build 1.0.0 (202607302101) | Validated and uploaded |
| Legal pages | Deployed. `/privacy`, `/terms`, `/support` all 200 with real content; unknown paths 404 |
| Firestore rules | Deployed, 64/64 emulator tests passing |
| Firestore indexes | Deployed — including `events (userID, at DESC)` and `requests (recipientIDs, status)` |
| Cloud Functions | Deployed — notifyNewRequest, notifyRequestResponse, onUserDeleted (v1, us-central1) |
| Blaze billing | Enabled |
| `events` TTL | 90-day policy live |
