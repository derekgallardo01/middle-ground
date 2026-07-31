#!/usr/bin/env node
/**
 * Pairs a REAL account with a demo partner and seeds a believable history, so the app can be
 * shown to someone rather than described to them.
 *
 * An empty Middle Ground is not a demo: no requests, no calendar entries, no streak, and a
 * disabled compose button. This fills in the state a real pair would have after a couple of
 * weeks together, chosen to exercise every screen worth showing:
 *
 *   - one request waiting on YOU        -> the response row, with Accept as the primary action
 *   - one mid-negotiation waiting on YOU -> the counter → accept loop
 *   - one you sent, waiting on THEM      -> the waiting state
 *   - two settled, one with a future date -> the feed's history and the Calendar tab
 *
 * Gamification is deliberately NOT seeded. Progress lives in UserDefaults on the device and
 * `restoreFromMirrorIfNeeded` is never called, so a Firestore write would not show up — and
 * letting XP accrue as you respond during the demo shows the reward loop working, which is a
 * better thing to show than a number that was always there.
 *
 * Writes with an owner token, which bypasses security rules — that is required, since no client
 * may create another user's account or forge their messages.
 *
 *   node Scripts/seed-demo-partner.mjs <your-email> [partner-name]
 *   node Scripts/seed-demo-partner.mjs --clean <your-email>
 */

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const PROJECT = 'middle-ground-8fd13';
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
// The Firebase CLI's own well-known public value, not a secret of this project.
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

/** Demo partners are recognisable by this domain so --clean can find them again. */
const DEMO_DOMAIN = 'demo.middleground.app';
const DEMO_PASSWORD = 'MGdemo!2026';

/**
 * Fixed IDs, so re-running overwrites rather than accumulating, and so --clean can remove
 * them by name even if the partner account is already gone.
 */
const DEMO_IDS = [
  'demo-waiting-on-you',
  'demo-negotiating',
  'demo-waiting-on-them',
  'demo-accepted-upcoming',
  'demo-accepted-past',
];

const FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

async function accessToken() {
  const cfgPath = `${homedir()}/.config/configstore/firebase-tools.json`;
  let refreshToken;
  try {
    refreshToken = JSON.parse(readFileSync(cfgPath, 'utf8')).tokens?.refresh_token;
  } catch {
    throw new Error('Could not read the Firebase CLI session. Run `firebase login` first.');
  }
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

// ------------------------------------------------------------- helpers

const str = (v) => ({ stringValue: v });
const num = (v) => ({ integerValue: String(v) });
const bool = (v) => ({ booleanValue: v });
const ts = (d) => ({ timestampValue: d.toISOString() });
const arr = (v) => ({ arrayValue: { values: v.map(str) } });
const nul = { nullValue: null };

const hoursAgo = (h) => new Date(Date.now() - h * 3_600_000);

/**
 * The next `weekday` (0 = Sunday) at `hour`, local time — always in the future.
 *
 * Titles below name a day ("Dinner Friday?"), and the card renders `proposedTime` beside
 * that title. A fixed offset would drift out of agreement with the words within a day of
 * writing this, and a demo where the text and the date chip disagree looks broken.
 */
function nextWeekday(weekday, hour, weeksOut = 0) {
  const d = new Date();
  d.setHours(hour, 0, 0, 0);
  const delta = (weekday - d.getDay() + 7) % 7 || 7;
  d.setDate(d.getDate() + delta + weeksOut * 7);
  return d;
}

const FRI = 5, SAT = 6;

const message = (senderID, responseType, text, at) => ({
  mapValue: {
    fields: {
      id: str(`m-${senderID.slice(0, 6)}-${responseType}-${at.getTime()}`),
      senderID: str(senderID),
      responseType: str(responseType),
      text: text ? str(text) : nul,
      timestamp: ts(at),
    },
  },
});

function api(token) {
  const H = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  return {
    set: (path, fields) =>
      fetch(`${FIRESTORE}/${path}`, { method: 'PATCH', headers: H, body: JSON.stringify({ fields }) })
        .then((r) => r.status),
    get: (path) => fetch(`${FIRESTORE}/${path}`, { headers: H }).then(async (r) =>
      r.status === 200 ? r.json() : null),
    del: (path) => fetch(`${FIRESTORE}/${path}`, { method: 'DELETE', headers: H }).then((r) => r.status),
    list: async (collection) => {
      const out = [];
      let pageToken;
      do {
        const q = new URLSearchParams({ pageSize: '300' });
        if (pageToken) q.set('pageToken', pageToken);
        const j = await fetch(`${FIRESTORE}/${collection}?${q}`, { headers: H }).then((r) => r.json());
        (j.documents || []).forEach((d) => out.push({ id: d.name.split('/').pop(), f: d.fields || {} }));
        pageToken = j.nextPageToken;
      } while (pageToken);
      return out;
    },
    identity: (path, body) =>
      fetch(`https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/${path}`,
        { method: 'POST', headers: H, body: JSON.stringify(body) }).then((r) => r.json()),
  };
}

const members = (f) => (f?.participantIDs?.arrayValue?.values || []).map((v) => v.stringValue);
const participants = (f) => (f?.allParticipantIDs?.arrayValue?.values || []).map((v) => v.stringValue);

// ---------------------------------------------------------------- main

const token = await accessToken();
const db = api(token);
const args = process.argv.slice(2);
const clean = args.includes('--clean');
const email = args.find((a) => a.includes('@') && !a.endsWith(DEMO_DOMAIN));
if (!email) {
  console.error('Usage: node Scripts/seed-demo-partner.mjs <your-email> [partner-name]');
  console.error('       node Scripts/seed-demo-partner.mjs --clean <your-email>');
  process.exit(1);
}
const partnerName = args.find((a) => !a.includes('@') && !a.startsWith('--')) || 'Sam';

const { users = [] } = await db.identity('accounts:lookup', { email: [email] });
const me = users[0];
if (!me) throw new Error(`No account for ${email}. Sign in on the device at least once first.`);
console.log(`you: ${email} (${me.localId})`);

const partnerEmail = `partner-${me.localId.slice(0, 8).toLowerCase()}@${DEMO_DOMAIN}`;

// ------------------------------------------------------------- cleanup

if (clean) {
  const { users: found = [] } = await db.identity('accounts:lookup', { email: [partnerEmail] });
  const partner = found[0];

  let removed = 0;
  // By ID first, so a half-cleaned run (partner deleted, requests left behind) still tidies up.
  for (const id of DEMO_IDS) {
    if ((await db.del(`requests/${id}`)) === 200) removed++;
  }
  for (const r of await db.list('requests')) {
    const p = participants(r.f);
    if (partner && p.includes(partner.localId)) { await db.del(`requests/${r.id}`); removed++; }
  }
  for (const r of await db.list('relationships')) {
    const m = members(r.f);
    if (partner && m.includes(partner.localId)) {
      // Leave your own group intact and unpaired, rather than deleting it.
      await db.set(`relationships/${r.id}`, {
        ...r.f,
        participantIDs: arr(m.filter((id) => id !== partner.localId)),
      });
      removed++;
    }
  }
  if (partner) {
    await db.del(`users/${partner.localId}`);
    await db.del(`gamification/${partner.localId}`);
    await db.identity('accounts:delete', { localId: partner.localId });
  }
  console.log(`cleaned ${removed} document(s) and the demo partner.`);
  process.exit(0);
}

// -------------------------------------------------------------- create

let partnerID;
try {
  ({ localId: partnerID } = await db.identity('accounts', {
    email: partnerEmail, password: DEMO_PASSWORD, displayName: partnerName,
  }));
} catch { /* fall through to lookup */ }
if (!partnerID) {
  const { users: found = [] } = await db.identity('accounts:lookup', { email: [partnerEmail] });
  partnerID = found[0]?.localId;
}
if (!partnerID) throw new Error('Could not create or find the demo partner account.');
// `createdAt` is NOT optional in UserDTO — omit it and the whole document fails to decode,
// which shows up as the partner having no name anywhere in the app.
await db.set(`users/${partnerID}`, {
  name: str(partnerName),
  avatarURL: nul,
  createdAt: ts(hoursAgo(24 * 14)),
});
console.log(`partner: ${partnerName} (${partnerID})`);

// Pair into your EXISTING group if you have an unpaired one, so the code you already have
// keeps working; otherwise make one.
const mine = (await db.list('relationships')).filter((r) => members(r.f).includes(me.localId));
let group = mine.find((r) => members(r.f).length === 1) || mine[0];
if (group) {
  await db.set(`relationships/${group.id}`, {
    ...group.f,
    participantIDs: arr([me.localId, partnerID]),
  });
  console.log(`paired into your existing group ${group.id}`);
} else {
  const id = crypto.randomUUID();
  await db.set(`relationships/${id}`, {
    participantIDs: arr([me.localId, partnerID]),
    type: str('couple'),
    createdAt: ts(hoursAgo(24 * 14)),
    growthScore: num(0),
    inviteCode: str('DEMO01'),
  });
  group = { id };
  console.log(`created a paired group ${id}`);
}

// --------------------------------------------------------------- seed

const request = ({ creator, recipient, category, title, details, status, proposed, chain = [], created, updated }) => ({
  creatorID: str(creator),
  recipientIDs: arr([recipient]),
  allParticipantIDs: arr([creator, recipient]),
  category: str(category),
  title: str(title),
  details: details ? str(details) : nul,
  proposedTime: proposed ? ts(proposed) : nul,
  location: nul,
  status: str(status),
  negotiationChain: { arrayValue: { values: chain } },
  savedForLater: bool(false),
  createdAt: ts(created),
  updatedAt: ts(updated),
});

const seeds = [
  // Waiting on YOU — the response row, with Accept prominent.
  ['demo-waiting-on-you', request({
    creator: partnerID, recipient: me.localId, category: 'relationship',
    title: 'Dinner at the ramen place Friday?',
    details: 'They finally take bookings. 7pm?',
    status: 'pending', proposed: nextWeekday(FRI, 19),
    created: hoursAgo(3), updated: hoursAgo(3),
  })],

  // Mid-negotiation, waiting on YOU — the loop that used to be impossible to close.
  // The counter proposes Sunday, so accepting it in front of someone actually reads as
  // "we landed on a middle ground" rather than as a button that just changes a badge.
  ['demo-negotiating', request({
    creator: me.localId, recipient: partnerID, category: 'friends',
    title: 'Movie night Saturday?',
    details: 'The new one everyone keeps talking about.',
    status: 'countered', proposed: nextWeekday(SAT, 20),
    chain: [
      message(partnerID, 'counter', 'Saturday is tight — could we do Sunday afternoon?', hoursAgo(20)),
    ],
    created: hoursAgo(26), updated: hoursAgo(20),
  })],

  // Waiting on THEM — the creator's waiting state.
  ['demo-waiting-on-them', request({
    creator: me.localId, recipient: partnerID, category: 'daily',
    title: 'Swap dishes for laundry this week?',
    status: 'pending',
    created: hoursAgo(6), updated: hoursAgo(6),
  })],

  // Settled, with a future date — shows up in Calendar.
  ['demo-accepted-upcoming', request({
    creator: partnerID, recipient: me.localId, category: 'travel',
    title: 'Weekend by the coast',
    details: 'Two nights, leave Friday after work.',
    status: 'accepted', proposed: nextWeekday(FRI, 17, 1),
    chain: [message(me.localId, 'accept', 'Yes — booking it tonight.', hoursAgo(48))],
    created: hoursAgo(72), updated: hoursAgo(48),
  })],

  // Settled history, so the feed does not look like it started today.
  ['demo-accepted-past', request({
    creator: me.localId, recipient: partnerID, category: 'daily',
    title: 'Split the grocery run',
    status: 'accepted',
    chain: [message(partnerID, 'accept', 'Deal.', hoursAgo(24 * 5))],
    created: hoursAgo(24 * 6), updated: hoursAgo(24 * 5),
  })],
];

for (const [id, fields] of seeds) {
  const status = await db.set(`requests/${id}`, fields);
  console.log(`  ${status === 200 ? 'ok  ' : 'FAIL'} ${fields.title.stringValue}`);
}

/** Read the dates back out of the seeds, so this summary cannot drift from what was written. */
const dated = seeds
  .map(([, f]) => [f.title.stringValue, f.proposedTime.timestampValue])
  .filter(([, t]) => t)
  .sort((a, b) => a[1].localeCompare(b[1]))
  .map(([title, t]) => `${new Date(t).toDateString()} — ${title}`);

console.log(`
Done. Relaunch the app (or pull to refresh) and you should see:

  Requests   one waiting on you, with Accept / Negotiate / Decline
             one mid-negotiation you can accept to close the loop
             one waiting on ${partnerName}
             two already settled

  Calendar   ${dated.join('\n             ')}

  Activities still zero, on purpose. Respond during the demo and the XP, the
             streak and the first achievement land while they are watching.

Remove it all with:
  node Scripts/seed-demo-partner.mjs --clean ${email}
`);
