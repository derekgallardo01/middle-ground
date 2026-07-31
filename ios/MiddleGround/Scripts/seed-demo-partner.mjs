#!/usr/bin/env node
/**
 * Pairs a REAL account with demo partners and seeds a believable history, so the app can be
 * shown to someone rather than described to them.
 *
 * An empty Middle Ground is not a demo: no requests, an empty calendar, and a compose button
 * that stays disabled until somebody joins you. This fills in the state a real pair would have
 * after a few weeks, chosen to cover every screen worth showing:
 *
 *   - four open requests waiting on YOU, including a three-turn negotiation
 *   - three waiting on THEM, so the waiting state is on screen too
 *   - eight settled, spanning accepted / declined / completed
 *   - every request category, and seven of the eight statuses
 *   - five dated events across the next two weeks, so Calendar has real density
 *   - a second, paired group, so the partner picker in Compose has something to pick
 *
 * Two things are deliberately NOT seeded, because neither would be visible:
 *
 *   - `savedForLater` has no UI surface anywhere in Features/, so a saved request renders
 *     identically to an unsaved one.
 *   - Gamification lives in UserDefaults on the device. `restoreFromMirrorIfNeeded` has no
 *     call sites, so a Firestore write is never read back. Letting XP land as you respond
 *     during the demo shows the reward loop working, which is the better thing to show.
 *
 * Writes with an owner token, which bypasses security rules — that is required, since no
 * client may create another user's account or forge their messages.
 *
 *   node Scripts/seed-demo-partner.mjs <your-email>
 *   node Scripts/seed-demo-partner.mjs --clean <your-email>
 */

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const PROJECT = 'middle-ground-8fd13';
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
// The Firebase CLI's own well-known public value, not a secret of this project.
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

/** Demo accounts are recognisable by this domain so --clean can find them again. */
const DEMO_DOMAIN = 'demo.middleground.app';
const DEMO_PASSWORD = 'MGdemo!2026';

/**
 * Invite codes for groups this script creates, which is how --clean tells them apart from a
 * group you already had. Without that distinction cleanup unpaired everything instead of
 * deleting what it made, leaving a phantom group behind — and since Profile and Compose read
 * the invite code from `relationships.first { !isPaired }`, that phantom can end up showing
 * its code in place of your real one.
 */
const DEMO_CODES = { couple: 'DEMO01', friends: 'DEMO02' };

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

/** A past date at a fixed hour, so seeded history reads as evenings and lunches. */
function daysAgo(days, hour) {
  const d = new Date();
  d.setHours(hour, 0, 0, 0);
  d.setDate(d.getDate() - days);
  return d;
}

function daysAhead(days, hour) {
  const d = new Date();
  d.setHours(hour, 0, 0, 0);
  d.setDate(d.getDate() + days);
  return d;
}

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

/** The mirror of `nextWeekday`, for history that names a day it already happened on. */
function previousWeekday(weekday, hour) {
  const d = new Date();
  d.setHours(hour, 0, 0, 0);
  const delta = (d.getDay() - weekday + 7) % 7 || 7;
  d.setDate(d.getDate() - delta);
  return d;
}

const SUN = 0, TUE = 2, THU = 4, FRI = 5, SAT = 6;

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
  console.error('Usage: node Scripts/seed-demo-partner.mjs <your-email>');
  console.error('       node Scripts/seed-demo-partner.mjs --clean <your-email>');
  process.exit(1);
}

const { users = [] } = await db.identity('accounts:lookup', { email: [email] });
const me = users[0];
if (!me) throw new Error(`No account for ${email}. Sign in on the device at least once first.`);
const ME = me.localId;
console.log(`you: ${email} (${ME})`);

const short = ME.slice(0, 8).toLowerCase();
/** `partner` is the couple; `friend` demos a second group and the Compose partner picker. */
const CAST = [
  { key: 'partner', name: 'Sam', email: `partner-${short}@${DEMO_DOMAIN}` },
  { key: 'friend', name: 'Jordan', email: `friend-${short}@${DEMO_DOMAIN}` },
];

// ------------------------------------------------------------- cleanup

if (clean) {
  const found = [];
  for (const c of CAST) {
    const { users: u = [] } = await db.identity('accounts:lookup', { email: [c.email] });
    if (u[0]) found.push(u[0].localId);
  }

  let removed = 0;
  // By prefix first, so a half-cleaned run (accounts gone, requests left behind) still tidies up.
  for (const r of await db.list('requests')) {
    if (r.id.startsWith('demo-') || participants(r.f).some((p) => found.includes(p))) {
      await db.del(`requests/${r.id}`);
      removed++;
    }
  }
  const demoCodes = Object.values(DEMO_CODES);
  for (const r of await db.list('relationships')) {
    const m = members(r.f);
    const isDemoGroup = demoCodes.includes(r.f.inviteCode?.stringValue);
    if (!isDemoGroup && !m.some((p) => found.includes(p))) continue;
    const kept = m.filter((id) => !found.includes(id));
    if (isDemoGroup || !kept.includes(ME)) {
      // This script created it, so remove it outright.
      await db.del(`relationships/${r.id}`);
    } else {
      // A group you already had: leave it intact and unpaired, with its own invite code.
      await db.set(`relationships/${r.id}`, { ...r.f, participantIDs: arr(kept) });
    }
    removed++;
  }
  for (const id of found) {
    await db.del(`users/${id}`);
    await db.del(`gamification/${id}`);
    await db.identity('accounts:delete', { localId: id });
  }
  console.log(`cleaned ${removed} document(s) and ${found.length} demo account(s).`);
  process.exit(0);
}

// -------------------------------------------------------------- people

const cast = {};
for (const c of CAST) {
  let id;
  ({ localId: id } = await db.identity('accounts', {
    email: c.email, password: DEMO_PASSWORD, displayName: c.name,
  }));
  if (!id) {
    const { users: found = [] } = await db.identity('accounts:lookup', { email: [c.email] });
    id = found[0]?.localId;
  }
  if (!id) throw new Error(`Could not create or find the demo account for ${c.name}.`);
  // `createdAt` is NOT optional in UserDTO — omit it and the whole document fails to decode,
  // which shows up as the person having no name anywhere in the app.
  await db.set(`users/${id}`, {
    name: str(c.name),
    avatarURL: nul,
    createdAt: ts(daysAgo(40, 12)),
  });
  cast[c.key] = id;
  console.log(`${c.key}: ${c.name} (${id})`);
}
const SAM = cast.partner;
const JORDAN = cast.friend;

// -------------------------------------------------------------- groups

const mine = (await db.list('relationships')).filter((r) => members(r.f).includes(ME));

/**
 * Pair into an EXISTING unpaired group where possible, so the invite code you already have
 * keeps working.
 *
 * Every group seeded here must end up paired. Both Profile and Compose source the invite code
 * from `relationships.first { !isPaired }`, so leaving a second group half-empty would quietly
 * replace the code on screen with the wrong one.
 */
async function ensureGroup(withID, type, code) {
  const existing = mine.find((r) => members(r.f).includes(withID))
    || mine.find((r) => members(r.f).length === 1 && !r.claimed);
  if (existing) {
    existing.claimed = true;
    await db.set(`relationships/${existing.id}`, {
      ...existing.f,
      // ME stays first: ProfileViewModel treats participantIDs[0] as the group's owner.
      participantIDs: arr([ME, withID]),
    });
    console.log(`group ${type}: reused ${existing.id}`);
    return existing.id;
  }
  const id = crypto.randomUUID();
  await db.set(`relationships/${id}`, {
    participantIDs: arr([ME, withID]),
    type: str(type),
    createdAt: ts(daysAgo(40, 12)),
    growthScore: num(0),
    inviteCode: str(code),
  });
  console.log(`group ${type}: created ${id}`);
  return id;
}

await ensureGroup(SAM, 'couple', DEMO_CODES.couple);
await ensureGroup(JORDAN, 'friends', DEMO_CODES.friends);

// --------------------------------------------------------------- seed

const request = ({ from, to, category, title, details, status, proposed, chain = [], updated }) => {
  // A day before the last activity, or an hour before the first reply — whichever is older.
  // Deriving it from `updated` alone dated the long exchanges *after* their own opening
  // message, so the detail view showed replies that predated the request they answered.
  const earliestReply = chain.length
    ? new Date(chain[0].mapValue.fields.timestamp.timestampValue).getTime() - 3_600_000
    : Infinity;
  const createdAt = new Date(Math.min(hoursAgo(updated + 24).getTime(), earliestReply));

  return {
    creatorID: str(from),
    recipientIDs: arr([to]),
    allParticipantIDs: arr([from, to]),
    category: str(category),
    title: str(title),
    details: details ? str(details) : nul,
    proposedTime: proposed ? ts(proposed) : nul,
    // `location` is never read anywhere in Features/, so filling it in would be invisible.
    location: nul,
    status: str(status),
    negotiationChain: { arrayValue: { values: chain } },
    savedForLater: bool(false),
    createdAt: ts(createdAt),
    updatedAt: ts(hoursAgo(updated)),
  };
};

// The feed is a flat list sorted by `updatedAt` descending, so these are ordered deliberately:
// everything needing an answer sits at the top, then what you are waiting on, then history.
const seeds = [
  // ------------------------------------------------ open, waiting on YOU
  ['demo-waiting-on-you', request({
    from: SAM, to: ME, category: 'relationship', updated: 2,
    title: 'Dinner at the ramen place Friday?',
    details: 'They finally take bookings. 7pm?',
    status: 'pending', proposed: nextWeekday(FRI, 19),
  })],

  // The three-turn exchange. This is the one to open in front of someone: before this week's
  // fix the conversation froze after the first reply and could never be closed.
  ['demo-negotiation-deep', request({
    from: ME, to: SAM, category: 'family', updated: 5,
    title: 'Visit your parents this month?',
    details: 'We keep saying we will and then not doing it.',
    status: 'countered', proposed: nextWeekday(SUN, 11, 1),
    chain: [
      message(SAM, 'negotiate', 'Could we make it a day trip rather than the whole weekend?', hoursAgo(30)),
      message(ME, 'counter', 'Day trip works. Saturday or Sunday?', hoursAgo(12)),
      message(SAM, 'counter', 'Sunday — then we are not rushing back for work.', hoursAgo(5)),
    ],
  })],

  ['demo-negotiating', request({
    from: ME, to: SAM, category: 'friends', updated: 9,
    title: 'Movie night Saturday?',
    details: 'The new one everyone keeps talking about.',
    status: 'countered', proposed: nextWeekday(SAT, 20),
    chain: [
      message(SAM, 'counter', 'Saturday is tight — could we do Sunday afternoon?', hoursAgo(9)),
    ],
  })],

  ['demo-rescheduled', request({
    from: ME, to: SAM, category: 'daily', updated: 14,
    title: 'Gym together Tuesday mornings?',
    status: 'rescheduled', proposed: nextWeekday(TUE, 7),
    chain: [
      message(SAM, 'reschedule', 'Wednesdays would be easier for me — Tuesdays I start early.', hoursAgo(14)),
    ],
  })],

  // ----------------------------------------------- open, waiting on THEM
  ['demo-waiting-on-them', request({
    from: ME, to: SAM, category: 'daily', updated: 20,
    title: 'Swap dishes for laundry this week?',
    status: 'pending',
  })],

  ['demo-awaiting-partner', request({
    from: SAM, to: ME, category: 'spontaneous', updated: 26,
    title: 'Walk before it gets dark?',
    status: 'negotiated',
    chain: [
      message(ME, 'negotiate', 'Give me twenty minutes to finish this and I am in.', hoursAgo(26)),
    ],
  })],

  ['demo-friend-pending', request({
    from: ME, to: JORDAN, category: 'friends', updated: 30,
    title: 'Concert tickets go on sale Thursday — in?',
    details: 'Presale is 10am, I can grab four.',
    status: 'pending', proposed: nextWeekday(THU, 10, 1),
  })],

  // ------------------------------------------------------------ settled
  ['demo-accepted-upcoming', request({
    from: SAM, to: ME, category: 'travel', updated: 48,
    title: 'Weekend by the coast',
    details: 'Two nights, leave Friday after work.',
    status: 'accepted', proposed: nextWeekday(FRI, 17, 1),
    chain: [message(ME, 'accept', 'Yes — booking it tonight.', hoursAgo(48))],
  })],

  // A negotiation that already resolved, so the history shows the loop closing and not just
  // a wall of one-tap yeses.
  ['demo-resolved', request({
    from: ME, to: SAM, category: 'relationship', updated: 60,
    title: 'Try the new Thai place?',
    status: 'accepted', proposed: nextWeekday(THU, 19),
    chain: [
      message(SAM, 'reschedule', 'Thursday instead of Tuesday? Tuesday is manic.', hoursAgo(80)),
      message(ME, 'accept', 'Thursday is perfect.', hoursAgo(60)),
    ],
  })],

  ['demo-declined', request({
    from: SAM, to: ME, category: 'travel', updated: 72,
    title: 'Camping next weekend?',
    status: 'declined',
    chain: [message(ME, 'decline', 'Not this one — I am wiped. Rain check?', hoursAgo(72))],
  })],

  ['demo-friend-accepted', request({
    from: JORDAN, to: ME, category: 'friends', updated: 90,
    title: 'Board game night at ours',
    details: 'Bring something to share.',
    status: 'accepted', proposed: daysAhead(5, 19),
    chain: [message(ME, 'accept', 'In. I will bring the good snacks.', hoursAgo(90))],
  })],

  ['demo-accepted-past', request({
    from: ME, to: SAM, category: 'daily', updated: 120,
    title: 'Split the grocery run',
    status: 'accepted',
    chain: [message(SAM, 'accept', 'Deal.', hoursAgo(120))],
  })],

  ['demo-completed', request({
    from: SAM, to: ME, category: 'family', updated: 150,
    title: 'Sunday lunch at your mum’s',
    status: 'completed', proposed: previousWeekday(SUN, 13),
    chain: [message(ME, 'accept', 'Wouldn’t miss it.', hoursAgo(200))],
  })],

  ['demo-spontaneous-past', request({
    from: ME, to: SAM, category: 'spontaneous', updated: 170,
    title: 'Ice cream, right now',
    status: 'accepted',
    chain: [message(SAM, 'accept', 'Already got my shoes on.', hoursAgo(170))],
  })],

  ['demo-habit', request({
    from: SAM, to: ME, category: 'relationship', updated: 200,
    title: 'Phones away at dinner this week?',
    status: 'accepted',
    chain: [message(ME, 'accept', 'Worth a try.', hoursAgo(200))],
  })],
];

for (const [id, fields] of seeds) {
  const status = await db.set(`requests/${id}`, fields);
  if (status !== 200) console.log(`  FAIL ${id} (${status})`);
}
console.log(`seeded ${seeds.length} requests`);

// Read the dates back out of the seeds, so this summary cannot drift from what was written.
const upcoming = seeds
  .map(([, f]) => [f.title.stringValue, f.proposedTime.timestampValue])
  .filter(([, t]) => t && new Date(t) >= new Date())
  .sort((a, b) => a[1].localeCompare(b[1]))
  .map(([title, t]) => `${new Date(t).toDateString()} — ${title}`);

const open = seeds.filter(([, f]) => !['accepted', 'declined', 'completed'].includes(f.status.stringValue));

console.log(`
Done. Relaunch the app (or pull to refresh).

  Requests   ${open.length} open, ${seeds.length - open.length} settled, newest first
             Every category, and every status that has a screen

  Calendar   ${upcoming.join('\n             ')}

  Compose    two groups now, so the partner picker has Sam and Jordan in it

  Activities still zero, on purpose. Respond during the demo and the XP, the
             streak and the first achievement land while they are watching.

Lead with "Visit your parents this month?" — three turns deep, waiting on you.

Remove it all with:
  node Scripts/seed-demo-partner.mjs --clean ${email}
`);
