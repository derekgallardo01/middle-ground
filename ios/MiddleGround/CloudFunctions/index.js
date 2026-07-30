/**
 * Cloud Functions for Middle Ground.
 *
 * MIXED GENERATIONS, ON PURPOSE. Everything here is 2nd-gen except `onUserDeleted`, which
 * cannot be: there is no 2nd-gen auth-delete trigger. The 2nd-gen identity hooks are
 * `beforeUserCreated` and `beforeUserSignedIn`, and neither fires on deletion. Since that
 * function is the durable backstop for the account-deletion cascade (App Store Guideline
 * 5.1.1(v)), it stays on 1st-gen via the `firebase-functions/v1` subpath, which is a stable
 * long-standing export rather than a compatibility shim.
 *
 * The 2nd-gen handler shape differs from 1st-gen in ways the compiler cannot catch:
 *   v1  (snap, context)   -> snap.data(),          context.params.x
 *   v2  (event)           -> event.data.data(),    event.params.x
 *   v1  (change, context) -> change.before.data(), change.after.data()
 *   v2  (event)           -> event.data.before.data(), event.data.after.data()
 * `event.data` is undefined on delete events, so every handler guards it.
 */

const admin = require('firebase-admin');
const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } =
  require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
// 1st-gen, for the auth trigger only. See the note above.
const functionsV1 = require('firebase-functions/v1');

const { getUserName, notifyUsers } = require('./push');
const { purgeUserData } = require('./purge');
const { sendAlert, when } = require('./alerts');

admin.initializeApp();
const db = () => admin.firestore();

const RESEND_API_KEY = defineSecret('RESEND_API_KEY');

/** Every 2nd-gen function that sends mail needs the secret bound, or the key is absent at runtime. */
const alerting = { secrets: [RESEND_API_KEY] };

// ---------------------------------------------------------------- push

/** Notifies the recipients when a request is created. */
exports.notifyNewRequest = onDocumentCreated('requests/{requestId}', async (event) => {
  const request = event.data?.data();
  if (!request?.recipientIDs?.length) return null;

  const senderName = await getUserName(request.creatorID);

  return notifyUsers(request.recipientIDs, {
    notification: {
      title: `New request from ${senderName}`,
      body: request.title,
    },
    data: {
      request_id: event.params.requestId,
      type: 'new_request',
    },
  });
});

/** Notifies everyone except the responder when a request gains a response. */
exports.notifyRequestResponse = onDocumentUpdated('requests/{requestId}', async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!before || !after) return null;

  const beforeCount = (before.negotiationChain || []).length;
  const afterCount = (after.negotiationChain || []).length;
  if (afterCount <= beforeCount) return null;

  const latestMessage = after.negotiationChain[afterCount - 1];
  const responderName = await getUserName(latestMessage.senderID);

  const notifyUserIds = (after.allParticipantIDs || []).filter(
    (id) => id !== latestMessage.senderID
  );

  return notifyUsers(notifyUserIds, {
    notification: {
      title: `${responderName} responded`,
      body: latestMessage.text || latestMessage.responseType,
    },
    data: {
      request_id: event.params.requestId,
      type: 'request_response',
    },
  });
});

// ------------------------------------------------------ operator alerts
//
// Watching Firestore documents rather than auth events, deliberately: the auth triggers are
// 1st-gen only, and the app writes users/{uid} on sign-up and deletes it on account deletion,
// so these carry the same signal while staying 2nd-gen.

exports.alertOnSignup = onDocumentCreated('users/{uid}', alerting, async (event) => {
  const user = event.data?.data();
  if (!user) return null;

  await sendAlert(`New signup: ${user.name || 'unnamed'}`, [
    `Name: ${user.name || '(none)'}`,
    `UID:  ${event.params.uid}`,
    `At:   ${when(new Date())}`,
    '',
    'They have not paired with anyone yet — the app is empty for them until they do.',
  ]);
  return null;
});

exports.alertOnPairing = onDocumentUpdated('relationships/{id}', alerting, async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!before || !after) return null;

  // Only the 1 -> 2 transition is a pairing. Any other participant change (someone leaving,
  // a code rotation) is not, and alerting on those would make this noisy and untrustworthy.
  const had = (before.participantIDs || []).length;
  const has = (after.participantIDs || []).length;
  if (!(had === 1 && has === 2)) return null;

  const names = await Promise.all((after.participantIDs || []).map(getUserName));

  await sendAlert(`Paired: ${names.join(' + ')}`, [
    `Group:  ${event.params.id} (${after.type || 'unknown type'})`,
    `Members: ${names.join(', ')}`,
    `UIDs:    ${(after.participantIDs || []).join(', ')}`,
    '',
    'Both can now send each other requests. This is the activation moment.',
  ]);
  return null;
});

/** Abuse reports are the one alert that should interrupt you. */
exports.alertOnReport = onDocumentCreated('reports/{id}', alerting, async (event) => {
  const report = event.data?.data();
  if (!report) return null;

  const [reporter, reported] = await Promise.all([
    getUserName(report.reporterID),
    getUserName(report.reportedUserID),
  ]);

  await sendAlert(`⚠️ Content reported — ${report.reason}`, [
    `Reason:   ${report.reason}`,
    `Reported: ${reported} (${report.reportedUserID})`,
    `By:       ${reporter} (${report.reporterID})`,
    `Request:  ${report.requestID}`,
    `Note:     ${report.note || '(none)'}`,
    `At:       ${when(report.at)}`,
    '',
    'The published policy commits to reviewing reports within 24 hours.',
    'Open the Admin tab > Reports to see the content.',
  ]);
  return null;
});

exports.alertOnAccountDeleted = onDocumentDeleted('users/{uid}', alerting, async (event) => {
  await sendAlert('Account deleted', [
    `UID: ${event.params.uid}`,
    `At:  ${when(new Date())}`,
    '',
    'Their data is purged by AccountDataPurger on the client and by onUserDeleted here.',
  ]);
  return null;
});

// -------------------------------------------------------- daily digest

/**
 * A once-a-day summary, so the numbers are visible without opening the app.
 *
 * Request and response volume is deliberately reported here rather than emailed per event:
 * it is the one event class that scales with usage, and per-event mail would train you to
 * ignore the inbox that also carries abuse reports.
 */
exports.dailyDigest = onSchedule(
  { schedule: '0 9 * * *', timeZone: 'America/New_York', secrets: [RESEND_API_KEY] },
  async () => {
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000);

    const countEvents = async (type) => {
      try {
        const snap = await db()
          .collection('events')
          .where('type', '==', type)
          .where('at', '>', since)
          .count()
          .get();
        return snap.data().count;
      } catch (error) {
        console.error(`digest: could not count ${type}:`, error);
        return '?';
      }
    };

    const totalUsers = async () => {
      try {
        return (await db().collection('users').count().get()).data().count;
      } catch {
        return '?';
      }
    };

    const [signups, onboarded, groups, redeemed, created, responded, left, reported, users] =
      await Promise.all([
        countEvents('signed_up'),
        countEvents('onboarding_completed'),
        countEvents('relationship_created'),
        countEvents('invite_redeemed'),
        countEvents('request_created'),
        countEvents('request_responded'),
        countEvents('relationship_left'),
        countEvents('content_reported'),
        totalUsers(),
      ]);

    await sendAlert('Daily digest', [
      'Last 24 hours',
      '',
      `  signed up            ${signups}`,
      `  finished onboarding  ${onboarded}`,
      `  created a group      ${groups}`,
      `  redeemed an invite   ${redeemed}   <- pairing`,
      `  requests created     ${created}`,
      `  requests answered    ${responded}`,
      `  left a group         ${left}`,
      `  content reported     ${reported}`,
      '',
      `Total users: ${users}`,
    ]);
  }
);

// ------------------------------------------------------------- 1st gen
//
// This one CANNOT be 2nd-gen — see the file header. Leave it on v1.

exports.onUserDeleted = functionsV1.auth.user().onDelete(async (user) => {
  await purgeUserData(user.uid);
});
