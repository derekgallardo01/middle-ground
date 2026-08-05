#!/usr/bin/env node
/**
 * Sends one real push to a registered device, through FCM, exactly as the Cloud Functions do.
 *
 * This is the half of "delivered end to end" that does not need a person holding a phone. It uses
 * the same `data` keys the functions send, so a successful tap proves the client's deep link too,
 * not merely that a banner can appear.
 *
 * It also answers the question nothing else can from here: whether APNs is actually wired up in
 * this Firebase project. If the auth key was never uploaded, FCM rejects the send with a specific
 * error rather than silently dropping it — which is the failure that looks exactly like "the
 * phone didn't buzz".
 *
 *   node Scripts/send-test-push.mjs [type] [--user <uid>]
 *
 * type is one of: reminder (default), new-request, message, confirm, cancelled, nudge
 */

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const PROJECT = process.env.MG_FIREBASE_PROJECT || 'middle-ground-8fd13';
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

const args = process.argv.slice(2);
const kind = args.find((a) => !a.startsWith('--')) ?? 'reminder';
const onlyUser = args.includes('--user') ? args[args.indexOf('--user') + 1] : null;

/// The same shapes CloudFunctions/index.js sends. `data.type` is snake_case and `request_id` is
/// what NotificationService.handleNotification switches on — get either wrong and the banner
/// appears but the tap goes nowhere, which is the bug this is meant to catch.
const PAYLOADS = {
  reminder: {
    title: 'Still on?',
    body: '"Sunday roast?" is tomorrow at 1:00 PM.',
    data: { request_id: 'req_6', type: 'plan_reminder' },
  },
  'new-request': {
    title: 'New request from Sam',
    body: 'Dinner on Thursday?',
    data: { request_id: 'req_0', type: 'new_request' },
  },
  message: {
    title: 'Sam on Sunday roast?',
    body: 'Which entrance?',
    data: { request_id: 'req_6', type: 'plan_message' },
  },
  confirm: {
    title: 'Did it happen?',
    body: 'Let us know how "Coffee on Monday" went.',
    data: { request_id: 'req_5', type: 'confirm_plan' },
  },
  cancelled: {
    title: 'Sam called off Drinks on Wednesday?',
    body: 'Something came up — at short notice.',
    data: { request_id: 'req_2', type: 'plan_cancelled' },
  },
  // The one whose deep link was broken until recently: it names a group, not a plan.
  nudge: {
    title: 'Plan something?',
    body: 'Nothing on the calendar for you and Sam in three weeks.',
    data: { relationship_id: 'rel_1', type: 'weekly_nudge' },
  },
};

const payload = PAYLOADS[kind];
if (!payload) {
  console.error(`Unknown type "${kind}". One of: ${Object.keys(PAYLOADS).join(', ')}`);
  process.exit(1);
}

async function accessToken() {
  const cfgPath = `${homedir()}/.config/configstore/firebase-tools.json`;
  const refreshToken = JSON.parse(readFileSync(cfgPath, 'utf8')).tokens?.refresh_token;
  if (!refreshToken) throw new Error('No Firebase CLI session found. Run `firebase login`.');
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error(`Token refresh failed: ${JSON.stringify(json)}`);
  return json.access_token;
}

const auth = await accessToken();

const query = await (
  await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:runQuery`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${auth}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        structuredQuery: { from: [{ collectionId: 'user_tokens' }], limit: 20 },
      }),
    }
  )
).json();

const devices = (Array.isArray(query) ? query : [])
  .filter((r) => r.document)
  .flatMap((r) => {
    const owner = r.document.name.split('/').pop();
    const list = r.document.fields?.tokens?.arrayValue?.values ?? [];
    return list.map((t) => ({ owner, token: t.stringValue }));
  })
  .filter((d) => d.token && (!onlyUser || d.owner === onlyUser));

if (devices.length === 0) {
  console.log('No registered device to send to.');
  console.log(
    'Install a real (non-mock) build on a phone, sign in, and allow notifications — the token is\n' +
    'written to user_tokens the moment it arrives. Then run this again.'
  );
  process.exit(0);
}

console.log(`sending "${kind}" to ${devices.length} device(s)\n`);

for (const device of devices) {
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${PROJECT}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${auth}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: {
        token: device.token,
        notification: { title: payload.title, body: payload.body },
        data: payload.data,
        apns: { payload: { aps: { sound: 'default', badge: 1 } } },
      },
    }),
  });
  const body = await res.json();

  if (res.ok) {
    console.log(`  ${device.owner}  sent  ${body.name}`);
  } else {
    const message = body.error?.message ?? JSON.stringify(body);
    console.log(`  ${device.owner}  FAILED  ${message}`);
    if (/APNS|apns|SenderId|Auth/i.test(message)) {
      console.log(
        '    ^ this is the APNs configuration, not the phone. Firebase console →\n' +
        '      Project settings → Cloud Messaging → APNs Authentication Key.'
      );
    }
    if (/not.*registered|Unregistered|invalid/i.test(message)) {
      console.log('    ^ stale token; the app prunes these itself on the next real send.');
    }
  }
}
