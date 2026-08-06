#!/usr/bin/env node
/**
 * Which features have actually reached the backend, and which have only ever been mocked.
 *
 * An audit found five collections with zero documents ever written — plan chat, location sharing,
 * shared availability, typing presence, read receipts — while UI tests for four of them passed
 * happily under `-MGMockMode`, which never touches Firestore or the rules. A green test suite and
 * an unused feature look identical from inside the repo. They do not look identical from here.
 *
 * This is the verdict for `RealBackendFeatureTests`: the screenshot proves the button was
 * tappable, this proves the write landed.
 *
 * Read-only.
 *
 *   node Scripts/verify-live-features.mjs
 */

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const PROJECT = process.env.MG_FIREBASE_PROJECT || 'middle-ground-8fd13';
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

/** collection id, whether it is nested under a parent, and what it means when empty. */
const FEATURES = [
  ['messages', true, 'plan chat', 'no message has ever been sent — notifyPlanMessage cannot fire'],
  ['locations', true, 'location sharing', 'never shared; the only feature making a privacy claim'],
  ['availability', true, 'shared availability', 'no day has ever been blocked out'],
  ['presence', true, 'typing indicator', 'nobody has ever been seen typing'],
  ['reads', true, 'read receipts', 'no plan has ever been marked read'],
  ['requests', false, 'plans', ''],
  ['relationships', false, 'pairing', ''],
  ['events', false, 'analytics', ''],
  ['user_tokens', false, 'push registration', ''],
];

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

async function count(collectionId, allDescendants) {
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:runQuery`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        structuredQuery: { from: [{ collectionId, allDescendants }], limit: 100 },
      }),
    }
  );
  const json = await res.json();
  if (json.error) return { error: json.error.message };
  return { n: (Array.isArray(json) ? json : []).filter((r) => r.document).length };
}

console.log('feature                     evidence');
console.log('─'.repeat(64));

let unproven = 0;
for (const [id, nested, label, whenEmpty] of FEATURES) {
  const result = await count(id, nested);
  if (result.error) {
    console.log(`✗ ${label.padEnd(24)} query failed: ${result.error.slice(0, 40)}`);
    continue;
  }
  const mark = result.n > 0 ? '✓' : '✗';
  const detail = result.n > 0
    ? `${result.n} document(s) in ${id}`
    : `NONE — ${whenEmpty || 'never written'}`;
  console.log(`${mark} ${label.padEnd(24)} ${detail}`);
  if (result.n === 0) unproven += 1;
}

// The function that cannot fire until plan chat is used at least once, and the clearest single
// signal that the app→Firestore→Cloud Function path works end to end for a subcollection.
const end = new Date().toISOString();
const start = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString();
const filter = encodeURIComponent(
  'metric.type="cloudfunctions.googleapis.com/function/execution_count" '
  + 'AND resource.label."function_name"="notifyPlanMessage"'
);
const metrics = await (
  await fetch(
    `https://monitoring.googleapis.com/v3/projects/${PROJECT}/timeSeries?filter=${filter}`
    + `&interval.startTime=${start}&interval.endTime=${end}`
    + `&aggregation.alignmentPeriod=2592000s&aggregation.perSeriesAligner=ALIGN_SUM`,
    { headers: { Authorization: `Bearer ${token}` } }
  )
).json();

const runs = (metrics.timeSeries ?? []).reduce(
  (total, ts) => total + (ts.points ?? []).reduce((a, p) => a + Number(p.value.int64Value ?? 0), 0),
  0
);
console.log('─'.repeat(64));
console.log(`${runs > 0 ? '✓' : '✗'} notifyPlanMessage        ${runs} execution(s) in 30 days`);

console.log('');
if (unproven === 0) {
  console.log('Every feature above has reached the real backend at least once.');
} else {
  console.log(
    `${unproven} feature(s) still have no production evidence. A passing UI test does not count:\n`
    + 'the mock-mode suite never reaches Firestore or the security rules.'
  );
}
