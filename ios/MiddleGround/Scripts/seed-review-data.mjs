#!/usr/bin/env node
/**
 * Seeds demo accounts, groups and content so App Review can actually use the app.
 *
 * The product does nothing until two people are paired: with no partner, Home is empty,
 * Calendar is empty, Activities is zeroed, and the compose button is disabled because
 * `CreateRequestViewModel.canSubmit` needs a recipient. A reviewer who signs in with their own
 * Apple ID therefore sees an empty shell and no way forward — a Guideline 2.1 rejection with
 * nothing to actually look at.
 *
 * This creates several one-person groups, each already populated with a realistic request
 * history from the demo partner, and prints their invite codes. Put the codes in the App Review
 * notes; the reviewer signs in with Apple as themselves, enters a code, and lands in a working
 * conversation.
 *
 * Why MORE THAN ONE code: `isRedeemingInvite` in firestore.rules admits a joiner only while
 * `participantIDs.size() < seats`, and a group seeded here has no `seats` field, so the rule's
 * `get('seats', 2)` default applies and it holds exactly two people. A code is therefore
 * single-use: the moment the first reviewer redeems it the group is full and every later
 * redemption is denied — which would silently break a rejection/resubmit cycle, or two
 * reviewers on the same build.
 *
 * That rule used to be `size() == 1`, which capped *every* group in the app at two. Groups now
 * carry a seat count; these deliberately do not, because single-use is the property the review
 * notes depend on.
 *
 * Reuses the Firebase CLI's OAuth session, like grant-admin.mjs, so no service-account key is
 * needed. Requires `firebase login`.
 *
 *   node Scripts/seed-review-data.mjs            # create 3 groups (default)
 *   node Scripts/seed-review-data.mjs --count 5
 *   node Scripts/seed-review-data.mjs --list     # print codes for existing demo groups
 *   node Scripts/seed-review-data.mjs --clean    # delete every demo account and its data
 */

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const PROJECT = 'middle-ground-8fd13';
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
// The Firebase CLI's own well-known public value, not a secret of this project.
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

/** Demo accounts are recognisable by this domain, so --clean can find them again. */
const DEMO_DOMAIN = 'review.middleground.app';
const DEMO_PASSWORD = 'MGreview!2026';

const FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

// Ambiguous characters (0/O, 1/I/L) are excluded, matching Relationship.inviteCodeAlphabet.
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

// ---------------------------------------------------------------- auth

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

const identity = (token) => async (path, body) => {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/${path}`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }
  );
  const json = await res.json();
  if (json.error) throw new Error(`${path}: ${json.error.message}`);
  return json;
};

// ------------------------------------------------------- firestore REST
//
// The REST API is used with an owner OAuth token, which bypasses security rules — that is the
// point. A client could not create these documents: it cannot write a relationship it is not
// in, and cannot forge another user's requests.

/** Encodes a JS value as a Firestore `Value`. */
function toValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(toValue) } };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  switch (typeof value) {
    case 'string':
      return { stringValue: value };
    case 'boolean':
      return { booleanValue: value };
    case 'number':
      return Number.isInteger(value)
        ? { integerValue: String(value) }
        : { doubleValue: value };
    case 'object':
      return { mapValue: { fields: toFields(value) } };
    default:
      throw new Error(`Cannot encode ${typeof value}`);
  }
}

const toFields = (obj) =>
  Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, toValue(v)]));

/** Decodes a Firestore `Value` back to JS. Only the shapes this script writes. */
function fromValue(value) {
  if (!value) return undefined;
  if ('stringValue' in value) return value.stringValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('timestampValue' in value) return new Date(value.timestampValue);
  if ('nullValue' in value) return null;
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(fromValue);
  if ('mapValue' in value) return fromFields(value.mapValue.fields || {});
  return undefined;
}

const fromFields = (fields) =>
  Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, fromValue(v)]));

function firestore(token) {
  const request = async (method, path, body) => {
    const res = await fetch(`${FIRESTORE}${path}`, {
      method,
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.status === 404 && method === 'GET') return null;
    const json = res.status === 200 ? await res.json() : await res.json().catch(() => ({}));
    if (json.error) throw new Error(`${path}: ${json.error.message}`);
    return json;
  };

  return {
    set: (collection, id, data) =>
      request('PATCH', `/${collection}/${encodeURIComponent(id)}`, { fields: toFields(data) }),
    get: (collection, id) => request('GET', `/${collection}/${encodeURIComponent(id)}`),
    delete: (collection, id) => request('DELETE', `/${collection}/${encodeURIComponent(id)}`),
    list: async (collection) => {
      const docs = [];
      let pageToken;
      do {
        const query = new URLSearchParams({ pageSize: '300' });
        if (pageToken) query.set('pageToken', pageToken);
        const page = await request('GET', `/${collection}?${query}`);
        (page?.documents || []).forEach((doc) =>
          docs.push({ id: doc.name.split('/').pop(), data: fromFields(doc.fields || {}) })
        );
        pageToken = page?.nextPageToken;
      } while (pageToken);
      return docs;
    },
  };
}

// ------------------------------------------------------------- seeding

const randomCode = () =>
  Array.from({ length: 6 }, () => CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)]).join('');

const uuid = () => crypto.randomUUID();

/** A realistic, entirely tame conversation for a reviewer to land in. */
function demoRequests(ownerID, ownerName) {
  const now = Date.now();
  const hoursAgo = (h) => new Date(now - h * 3_600_000);

  const base = (overrides) => ({
    creatorID: ownerID,
    recipientIDs: [],
    allParticipantIDs: [ownerID],
    savedForLater: false,
    negotiationChain: [],
    ...overrides,
  });

  // Categories, statuses and response types must match the raw values in Request.swift —
  // RequestCategory is relationship/friends/family/daily/travel/spontaneous, and a document
  // with an unknown value is dropped by `compactMap` in the DTO and never appears.
  return [
    base({
      id: uuid(),
      category: 'relationship',
      title: 'Dinner on Friday?',
      details: 'That pasta place we liked. I can book for 7.',
      status: 'pending',
      proposedTime: hoursAgo(-48),
      createdAt: hoursAgo(6),
      updatedAt: hoursAgo(6),
    }),
    base({
      id: uuid(),
      category: 'daily',
      title: 'Swap dishes for laundry this week?',
      status: 'pending',
      createdAt: hoursAgo(20),
      updatedAt: hoursAgo(20),
    }),
    base({
      id: uuid(),
      category: 'travel',
      title: 'Weekend trip in October',
      details: 'Thinking two nights somewhere near the coast.',
      status: 'accepted',
      createdAt: hoursAgo(72),
      updatedAt: hoursAgo(70),
      negotiationChain: [
        {
          id: uuid(),
          senderID: ownerID,
          responseType: 'accept',
          text: `Sounds good to me — ${ownerName} is in.`,
          timestamp: hoursAgo(70),
        },
      ],
    }),
  ];
}

async function seedOne(call, db, index) {
  const label = `demo${index}`;
  const email = `${label}@${DEMO_DOMAIN}`;
  const name = ['Alex', 'Sam', 'Jordan', 'Riley', 'Casey', 'Quinn'][index % 6];

  // Create the demo partner. If it already exists, reuse it.
  //
  // The admin create endpoint is `projects/{id}/accounts`. `accounts:signUp` exists only on
  // the unauthenticated client API and 404s here with an HTML error page, which surfaces as
  // "Unexpected token '<'" rather than anything informative.
  let localId;
  try {
    ({ localId } = await call('accounts', {
      email,
      password: DEMO_PASSWORD,
      displayName: name,
    }));
  } catch (error) {
    if (!/EMAIL_EXISTS/.test(error.message)) throw error;
    const { users = [] } = await call('accounts:lookup', { email: [email] });
    localId = users[0]?.localId;
    if (!localId) throw new Error(`${email} exists but could not be looked up`);
  }

  const code = randomCode();
  const relationshipID = uuid();
  const createdAt = new Date();

  await db.set('users', localId, { name, avatarURL: null });

  // One participant only — exactly the state isRedeemingInvite requires.
  await db.set('relationships', relationshipID, {
    participantIDs: [localId],
    type: 'couple',
    createdAt,
    growthScore: 40,
    inviteCode: code,
  });

  await db.set('invites', code, {
    relationshipID,
    ownerID: localId,
    createdAt,
  });

  for (const request of demoRequests(localId, name)) {
    const { id, ...data } = request;
    await db.set('requests', id, data);
  }

  return { email, name, localId, code, relationshipID };
}

// ---------------------------------------------------------------- main

async function main() {
  const args = process.argv.slice(2);
  const token = await accessToken();
  const call = identity(token);
  const db = firestore(token);

  if (args.includes('--list')) {
    const invites = await db.list('invites');
    const users = await db.list('users');
    const demoIDs = new Set();
    const { userInfo = [] } = await call('accounts:query', { returnUserInfo: true });
    userInfo
      .filter((u) => (u.email || '').endsWith(`@${DEMO_DOMAIN}`))
      .forEach((u) => demoIDs.add(u.localId));

    const demoInvites = invites.filter((i) => demoIDs.has(i.data.ownerID));
    if (!demoInvites.length) {
      console.log('No demo groups exist. Run without --list to create some.');
      return;
    }
    console.log('Demo invite codes:');
    for (const invite of demoInvites) {
      const owner = users.find((u) => u.id === invite.data.ownerID);
      console.log(`  ${invite.id}   partner: ${owner?.data.name || '(unknown)'}`);
    }
    return;
  }

  if (args.includes('--clean')) {
    const { userInfo = [] } = await call('accounts:query', { returnUserInfo: true });
    const demo = userInfo.filter((u) => (u.email || '').endsWith(`@${DEMO_DOMAIN}`));
    if (!demo.length) {
      console.log('No demo accounts to remove.');
      return;
    }
    const demoIDs = new Set(demo.map((u) => u.localId));

    for (const collection of ['relationships', 'requests', 'invites']) {
      for (const doc of await db.list(collection)) {
        const owners = [
          ...(doc.data.participantIDs || []),
          ...(doc.data.allParticipantIDs || []),
          doc.data.ownerID,
        ].filter(Boolean);
        if (owners.some((id) => demoIDs.has(id))) await db.delete(collection, doc.id);
      }
    }
    for (const id of demoIDs) {
      await db.delete('users', id).catch(() => {});
      await db.delete('gamification', id).catch(() => {});
      await call('accounts:delete', { localId: id }).catch(() => {});
    }
    console.log(`Removed ${demo.length} demo account(s) and their data.`);
    return;
  }

  const countIndex = args.indexOf('--count');
  const count = countIndex >= 0 ? Number(args[countIndex + 1]) : 3;
  if (!Number.isInteger(count) || count < 1 || count > 20) {
    console.error('--count must be between 1 and 20');
    process.exit(1);
  }

  const seeded = [];
  for (let i = 0; i < count; i += 1) {
    seeded.push(await seedOne(call, db, i));
  }

  console.log(`\nSeeded ${seeded.length} demo group(s).\n`);
  console.log('Put these in the App Review notes — each works exactly once:\n');
  seeded.forEach(({ code, name }) => console.log(`  ${code}    you pair with "${name}"`));
  console.log('\nEach group already has three requests, one of them answered.');
  console.log('Remove them all afterwards with: node Scripts/seed-review-data.mjs --clean');
}

main().catch((error) => {
  console.error(`Failed: ${error.message}`);
  process.exit(1);
});
