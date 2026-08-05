#!/usr/bin/env node
/**
 * Reports how old the oldest `events` document actually is.
 *
 * Exists because `firestore.indexes.json` sets a TTL policy on `events.at` and its comment claims
 * "Firestore deletes each document 90 days after its `at` value". That is not what a TTL policy
 * does: Firestore deletes a document once the timestamp in the TTL field is *in the past*, with no
 * offset. `at` is the moment the event was written, so every event is eligible for deletion the
 * instant it exists, and Firestore collects it within about 24 hours.
 *
 * The two other TTLs in the same file — `locations.expiresAt` and `presence.expiresAt` — point at a
 * future timestamp, which is the correct shape.
 *
 * If that reading is right, `events` never holds more than a day or so of history: the admin funnel
 * has been reporting a day rather than all time, and the privacy policy's 90-day sentence is
 * generous rather than accurate. Reading is the only way to know, because both explanations look
 * identical from the code.
 *
 * Read-only. Lists the oldest and newest event and the span between them.
 *
 *   node Scripts/check-events-ttl.mjs
 */

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const PROJECT = process.env.MG_FIREBASE_PROJECT || 'middle-ground-8fd13';
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

async function accessToken() {
  const cfgPath = `${homedir()}/.config/configstore/firebase-tools.json`;
  let refreshToken;
  try {
    refreshToken = JSON.parse(readFileSync(cfgPath, 'utf8')).tokens?.refresh_token;
  } catch {
    throw new Error('Could not read the Firebase CLI session. Run `firebase login` first.');
  }
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

async function oneEvent(token, direction) {
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:runQuery`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: 'events' }],
          orderBy: [{ field: { fieldPath: 'at' }, direction }],
          limit: 1,
        },
      }),
    }
  );
  const rows = await res.json();
  if (!Array.isArray(rows)) throw new Error(`Query failed: ${JSON.stringify(rows)}`);
  const doc = rows.find((r) => r.document)?.document;
  if (!doc) return null;
  return { at: doc.fields?.at?.timestampValue, type: doc.fields?.type?.stringValue };
}

async function count(token, collection) {
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:runAggregationQuery`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        structuredAggregationQuery: {
          structuredQuery: { from: [{ collectionId: collection }] },
          aggregations: [{ count: {}, alias: 'n' }],
        },
      }),
    }
  );
  const rows = await res.json();
  if (!Array.isArray(rows)) return `error: ${JSON.stringify(rows).slice(0, 120)}`;
  return rows[0]?.result?.aggregateFields?.n?.integerValue ?? '0';
}

async function ttlState(token, field) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${PROJECT}` +
    `/databases/(default)/collectionGroups/events/fields/${field}`;
  const r = await (await fetch(url, { headers: { Authorization: `Bearer ${token}` } })).json();
  return r.ttlConfig?.state ?? 'none';
}

const token = await accessToken();

console.log('events TTL policy:');
for (const f of ['at', 'expiresAt']) {
  console.log(`  events.${f.padEnd(10)} ${await ttlState(token, f)}`);
}
console.log('');

const oldest = await oneEvent(token, 'ASCENDING');
const newest = await oneEvent(token, 'DESCENDING');

// An empty `events` collection has two explanations that look identical: the TTL is eating
// everything, or nobody has used the app. Counting collections that carry no TTL tells them apart.
console.log('collection sizes (no TTL on any of these except events):');
for (const c of ['users', 'requests', 'relationships', 'plan_outcomes', 'events']) {
  console.log(`  ${c.padEnd(16)} ${await count(token, c)}`);
}
console.log('');

if (!oldest) {
  console.log('The events collection is empty.');
  console.log(
    'If the collections above are populated, that is the answer: events are being written and\n' +
    'then deleted, because the TTL field holds a timestamp that is already past.'
  );
  process.exit(0);
}

const days = (Date.now() - Date.parse(oldest.at)) / 86_400_000;
console.log(`oldest event   ${oldest.at}  (${days.toFixed(1)} days old)  type=${oldest.type}`);
console.log(`newest event   ${newest?.at}  type=${newest?.type}`);
console.log('');
console.log(
  days < 5
    ? 'CONFIRMED: nothing older than a few days survives. The TTL is firing immediately, because\n' +
      '`at` is already in the past when the document is written. Events are not kept for 90 days.'
    : `Not confirmed: history reaches back ${days.toFixed(0)} days, so the TTL is not deleting on write.`
);
