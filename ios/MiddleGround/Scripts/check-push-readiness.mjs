#!/usr/bin/env node
/**
 * Reports whether push could work at all, before anybody goes looking for a banner.
 *
 * Push has never been delivered end to end, and "it didn't arrive" has several very different
 * causes that look identical from a phone: no device ever registered a token, the token is stale,
 * APNs was never wired up in Firebase, the send was skipped by a notification preference, or it
 * was sent and the phone dropped it. This narrows that down from the server side, where most of
 * those are visible.
 *
 * Read-only.
 *
 *   node Scripts/check-push-readiness.mjs
 */

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const PROJECT = process.env.MG_FIREBASE_PROJECT || 'middle-ground-8fd13';
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

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

const token = await accessToken();
const firestore = (path, body) =>
  fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents${path}`,
    {
      method: body ? 'POST' : 'GET',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    }
  ).then((r) => r.json());

// 1. Has any device ever registered? Without this nothing else matters — `notifyUser` returns
//    early on an empty token list and logs nothing, so a missing token is indistinguishable from
//    a delivered-and-ignored push.
const tokens = await firestore(':runQuery', {
  structuredQuery: { from: [{ collectionId: 'user_tokens' }], limit: 20 },
});
const docs = (Array.isArray(tokens) ? tokens : []).filter((r) => r.document);

console.log(`registered devices: ${docs.length}`);
for (const d of docs) {
  const owner = d.document.name.split('/').pop();
  const list = d.document.fields?.tokens?.arrayValue?.values ?? [];
  const updated = d.document.fields?.updatedAt?.timestampValue ?? 'unknown';
  console.log(`  ${owner}  ${list.length} token(s)  updated ${updated}`);
  for (const t of list) {
    // Enough to tell two devices apart and to spot a truncated or placeholder value; never the
    // whole thing, because a registration token is a capability to push to somebody's phone.
    const value = t.stringValue ?? '';
    console.log(`    …${value.slice(-12)}  (${value.length} chars)`);
  }
}

// 2. Notification preferences, since a muted kind is silently skipped and looks like a failure.
const settings = await firestore(':runQuery', {
  structuredQuery: { from: [{ collectionId: 'notification_settings' }], limit: 20 },
});
const settingDocs = (Array.isArray(settings) ? settings : []).filter((r) => r.document);
console.log(`\nnotification_settings documents: ${settingDocs.length}`);
for (const d of settingDocs) {
  const owner = d.document.name.split('/').pop();
  const off = Object.entries(d.document.fields ?? {})
    .filter(([, v]) => v.booleanValue === false)
    .map(([k]) => k);
  console.log(`  ${owner}  muted: ${off.length ? off.join(', ') : 'nothing'}`);
}

console.log('');
if (docs.length === 0) {
  console.log(
    'No device has ever registered a token. That is the first thing to fix, and it is upstream of\n' +
    'everything else: `notifyUser` returns early on an empty token list without logging, so every\n' +
    'push in this project has been a no-op that left no trace.'
  );
} else {
  console.log('At least one device is registered, so a send can be attempted against it.');
}
