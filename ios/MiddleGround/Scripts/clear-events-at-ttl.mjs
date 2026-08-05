#!/usr/bin/env node
/**
 * Removes the TTL policy from `events.at`, so it can be applied to `events.expiresAt` instead.
 *
 * A collection group may carry only one TTL field, and the deploy refuses with HTTP 429 while the
 * old one is still configured:
 *
 *   The collection group 'events' can only have at most '1' field(s) marked with TTL but already
 *   has TTL configurations set on path 'at'.
 *
 * `firebase deploy --only firestore:indexes --force` would clear it, but --force also deletes
 * every index in the project that is absent from firestore.indexes.json — three of them here,
 * none of which anybody has looked at. This does the one thing.
 *
 * Why the TTL is moving at all: a TTL deletes a document once the timestamp it names is in the
 * past, with no offset. `at` is when the event happened, so it was already past on write and every
 * event was collected within about a day. Six users, twelve requests and five groups had produced
 * an entirely empty `events` collection.
 *
 * Safe to re-run: clearing an already-clear TTL is a no-op.
 *
 *   node Scripts/clear-events-at-ttl.mjs
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

const FIELD =
  `https://firestore.googleapis.com/v1/projects/${PROJECT}` +
  `/databases/(default)/collectionGroups/events/fields/at`;

const token = await accessToken();

const before = await (await fetch(FIELD, { headers: { Authorization: `Bearer ${token}` } })).json();
console.log('events.at ttlConfig before:', JSON.stringify(before.ttlConfig ?? null));

if (!before.ttlConfig) {
  console.log('Already clear — nothing to do.');
  process.exit(0);
}

// An empty body with the ttlConfig mask is what removes it. Naming the mask matters: without it
// the request is a full replace and would drop the field's index configuration too. The
// parameter is `updateMask`, spelled exactly so — `updateMask.fieldPaths` is rejected as an
// unknown query parameter, which reads like a payload problem rather than a URL one.
const res = await fetch(`${FIELD}?updateMask=ttlConfig`, {
  method: 'PATCH',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({}),
});
const body = await res.json();
if (!res.ok) throw new Error(`Clearing the TTL failed: ${JSON.stringify(body)}`);

console.log('requested removal —', body.name ?? 'operation started');
console.log('Firestore applies this asynchronously; re-run to confirm it reads null.');
