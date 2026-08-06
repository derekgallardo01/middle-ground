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
 * Resolves the two E2E accounts **by name**, not by position.
 *
 * Borrowing `allParticipantIDs[0]` and calling it "A" is a coin flip, and it landed wrong: the
 * pending plan was addressed to Tester B while the test signs in as Tester A, so it was correctly
 * not A's turn and no Accept button was ever offered. The app was right and the fixture was wrong,
 * which is exactly the sort of thing that gets read as a product bug.
 *
 * `signInAsTestUser` writes these display names, so they are the stable handle. UIDs are not —
 * they change whenever the test accounts are recreated.
 */
async function testers() {
  const fromArgs = process.argv.slice(2).filter((a) => !a.startsWith('--'));
  if (fromArgs.length === 2) return { a: fromArgs[0], b: fromArgs[1] };

  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:runQuery`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ structuredQuery: { from: [{ collectionId: 'users' }], limit: 50 } }),
    }
  );
  const rows = (await res.json()).filter?.((r) => r.document) ?? [];
  const byName = (want) => rows.find(
    (r) => (r.document.fields?.name?.stringValue ?? '').trim().toLowerCase() === want
  )?.document.name.split('/').pop();

  const a = byName('tester a');
  const b = byName('tester b');
  if (!a || !b) {
    throw new Error('Could not find users named "Tester A" and "Tester B". '
      + 'Run Scripts/two-device-e2e.sh first, or pass their two UIDs as arguments.');
  }
  return { a, b };
}

const { a: testerA, b: testerB } = await testers();
// The location fixture is A's own plan; either participant may share on it.
const creator = testerA;
const recipient = testerB;
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

/**
 * A second fixture: a plan still waiting on an answer.
 *
 * `plan_outcomes` is written on the transition *into* accepted, and the collection is empty
 * despite the app having been used — so the question is whether that write reaches the server at
 * all. Answering it needs a plan somebody can actually accept, and the pairing run's plans have
 * all been answered already.
 *
 * Addressed the other way round from the location fixture: the recipient is whoever the test signs
 * in as, because only the person whose turn it is may respond.
 */
const PENDING_DOC_ID = 'e2e-accept-me';
export const PENDING_TITLE = 'E2E accept me';

const pending = {
  fields: {
    title: { stringValue: PENDING_TITLE },
    status: { stringValue: 'pending' },
    category: { stringValue: 'relationship' },
    // Sent by B and awaiting A, because the test signs in as A and only the person whose turn
    // it is may respond.
    creatorID: { stringValue: testerB },
    recipientIDs: { arrayValue: { values: [{ stringValue: testerA }] } },
    allParticipantIDs: {
      arrayValue: { values: [{ stringValue: testerB }, { stringValue: testerA }] },
    },
    proposedTime: { timestampValue: new Date(Date.now() + 36 * 3600 * 1000).toISOString() },
    createdAt: { timestampValue: now },
    updatedAt: { timestampValue: now },
    savedForLater: { booleanValue: false },
    negotiationChain: { arrayValue: { values: [] } },
  },
};

async function put(id, body) {
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT}`
    + `/databases/(default)/documents/requests/${id}`,
    {
      method: 'PATCH',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }
  );
  const json = await res.json();
  if (json.error) {
    console.error(`Failed to seed ${id}: ${json.error.message}`);
    process.exit(1);
  }
  return json;
}

await put(DOC_ID, document);
await put(PENDING_DOC_ID, pending);

console.log(`Seeded "${FIXTURE_TITLE}" (${DOC_ID})`);
console.log(`  Tester A: ${testerA}   Tester B: ${testerB}`);
console.log(`  proposedTime: ${now} — location window open for about four hours`);
console.log(`Seeded "${PENDING_TITLE}" (${PENDING_DOC_ID}), sent by B, awaiting Tester A`);
