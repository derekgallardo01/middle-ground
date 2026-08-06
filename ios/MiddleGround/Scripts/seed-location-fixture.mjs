#!/usr/bin/env node
/**
 * Creates one plan sitting inside its location-sharing window, so the feature can be tested.
 *
 * Location sharing is deliberately narrow: it needs an **accepted** plan timed within an hour
 * before and four hours after now (`Request.isWithinLocationWindow`). A pairing run does not
 * produce one, so `RealBackendFeatureTests.testLive3` had nothing to act on and skipped.
 *
 * Re-dating an existing plan is not enough, and finding that out cost three runs:
 * `CachedRequestRepository.merge` only overwrites a local row when the remote copy is strictly
 * newer, so an app that has already cached the plan keeps serving its own copy. Writing a **new**
 * document sidesteps that entirely — there is nothing cached to lose to.
 *
 * The title is distinctive so the test can find it without colliding with the leftovers of
 * previous runs, which is the other thing that broke: "E2E dinner test" matches several documents
 * and XCUITest refuses to guess between them.
 *
 * Safe to run repeatedly: the document ID is fixed, so this replaces rather than accumulates.
 *
 *   node Scripts/seed-location-fixture.mjs [participantA] [participantB]
 */

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const PROJECT = process.env.MG_FIREBASE_PROJECT || 'middle-ground-8fd13';
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

/** Fixed, so a re-run replaces the fixture rather than leaving another one behind. */
const DOC_ID = 'e2e-location-window';
export const FIXTURE_TITLE = 'E2E location window';

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

/**
 * Finds the two E2E test accounts rather than hardcoding UIDs, which change whenever the test
 * accounts are recreated.
 */
async function participants() {
  const fromArgs = process.argv.slice(2).filter((a) => !a.startsWith('--'));
  if (fromArgs.length === 2) return fromArgs;

  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:runQuery`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ structuredQuery: { from: [{ collectionId: 'requests' }], limit: 40 } }),
    }
  );
  const rows = (await res.json()).filter?.((r) => r.document) ?? [];
  // Borrow the participants of an existing E2E plan: whoever the harness last paired is exactly
  // who the next test run will be signed in as.
  const seed = rows.find((r) => r.document.fields?.title?.stringValue === 'E2E dinner test');
  const ids = (seed?.document.fields?.allParticipantIDs?.arrayValue?.values ?? [])
    .map((v) => v.stringValue);
  if (ids.length < 2) {
    throw new Error('Could not find a paired E2E plan to borrow participants from. '
      + 'Run Scripts/two-device-e2e.sh first, or pass two UIDs as arguments.');
  }
  return ids.slice(0, 2);
}

const [creator, recipient] = await participants();
const now = new Date().toISOString();

const document = {
  fields: {
    title: { stringValue: FIXTURE_TITLE },
    status: { stringValue: 'accepted' },
    category: { stringValue: 'relationship' },
    creatorID: { stringValue: creator },
    recipientIDs: { arrayValue: { values: [{ stringValue: recipient }] } },
    allParticipantIDs: {
      arrayValue: { values: [{ stringValue: creator }, { stringValue: recipient }] },
    },
    // Now, so the window is open in both directions with hours to spare either side.
    proposedTime: { timestampValue: now },
    createdAt: { timestampValue: now },
    updatedAt: { timestampValue: now },
    savedForLater: { booleanValue: false },
    negotiationChain: { arrayValue: { values: [] } },
  },
};

const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}`
  + `/databases/(default)/documents/requests/${DOC_ID}`;
const res = await fetch(url, {
  method: 'PATCH',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify(document),
});
const json = await res.json();

if (json.error) {
  console.error(`Failed to seed the fixture: ${json.error.message}`);
  process.exit(1);
}

console.log(`Seeded "${FIXTURE_TITLE}" (${DOC_ID})`);
console.log(`  participants: ${creator}, ${recipient}`);
console.log(`  proposedTime: ${now}`);
console.log('  window open until roughly four hours from now');
