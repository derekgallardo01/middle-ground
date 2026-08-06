/**
 * Tests for delivery: who gets a push, and what the badge says.
 *
 * These are the two things a preferences UI cannot prove on its own. A settings screen that
 * saves `newRequest: false` looks perfectly correct while the backend ignores the document
 * entirely — the switch moves, the notification still arrives, and nobody finds out until a
 * user says so. Same for the badge: it is a number on an icon that no screen displays, so the
 * only way it gets checked is here.
 *
 * `firebase-admin` is stubbed through require.cache rather than by injecting a database into
 * push.js. The module reads `getFirestore()` lazily inside `db()` precisely so it can be
 * swapped, and stubbing at the module boundary keeps the production code free of test seams.
 * `node --test` runs each file in its own process, so the stub cannot leak into rules.test.js.
 */
const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert');

const sent = [];
const store = { notification_settings: {}, user_tokens: {}, requests: {} };

function docSnapshot(id, data) {
  return { id, exists: data !== undefined, data: () => data };
}

/** Just enough Firestore for push.js: two document reads, one filtered query, one update. */
function fakeFirestore() {
  const query = (name, filters, cap) => ({
    where: (field, op, value) => query(name, [...filters, { field, op, value }], cap),
    // Real Firestore truncates server-side, so the fake has to as well — a `limit` that only
    // exists in production is a cap nothing can test.
    limit: (count) => query(name, filters, count),
    get: async () => {
      const matches = Object.entries(store[name] || {})
        .filter(([, data]) =>
          filters.every(({ field, op, value }) => {
            if (op === 'array-contains') return (data[field] || []).includes(value);
            if (op === 'in') return value.includes(data[field]);
            return data[field] === value;
          }),
        )
        .map(([id, data]) => docSnapshot(id, data));
      const docs = cap === undefined ? matches : matches.slice(0, cap);
      return { docs, empty: docs.length === 0, size: docs.length };
    },
  });

  return {
    collection: (name) => ({
      ...query(name, [], undefined),
      doc: (id) => ({
        get: async () => docSnapshot(id, (store[name] || {})[id]),
        update: async (changes) => Object.assign(store[name][id], changes),
      }),
    }),
  };
}

const firestorePath = require.resolve('firebase-admin/firestore');
const messagingPath = require.resolve('firebase-admin/messaging');

require.cache[firestorePath] = {
  id: firestorePath,
  filename: firestorePath,
  loaded: true,
  exports: { getFirestore: fakeFirestore, FieldValue: { arrayRemove: (...ids) => ids } },
};

require.cache[messagingPath] = {
  id: messagingPath,
  filename: messagingPath,
  loaded: true,
  exports: {
    getMessaging: () => ({
      sendEachForMulticast: async (message) => {
        sent.push(message);
        return { successCount: message.tokens.length, failureCount: 0, responses: [] };
      },
    }),
  },
};

const { notifyUsers, NotificationType } = require('../push');

const payload = { notification: { title: 'Dinner?', body: 'Friday' } };

beforeEach(() => {
  sent.length = 0;
  store.notification_settings = {};
  store.user_tokens = { alice: { tokens: ['token-a'] }, bob: { tokens: ['token-b'] } };
  store.requests = {};
});

describe('notification preferences', () => {
  test('a type switched off is not delivered', async () => {
    store.notification_settings.alice = { newRequest: false };

    await notifyUsers(['alice'], payload, NotificationType.newRequest);

    assert.equal(sent.length, 0);
  });

  test('switching one type off leaves the others alone', async () => {
    store.notification_settings.alice = { newRequest: false };

    await notifyUsers(['alice'], payload, NotificationType.response);

    assert.equal(sent.length, 1);
  });

  test('no settings document means everything is on', async () => {
    await notifyUsers(['alice'], payload, NotificationType.newRequest);

    assert.equal(sent.length, 1);
  });

  test('one person opting out does not silence the other', async () => {
    store.notification_settings.alice = { confirmPlan: false };

    await notifyUsers(['alice', 'bob'], payload, NotificationType.confirmPlan);

    assert.deepEqual(sent.map((message) => message.tokens).flat(), ['token-b']);
  });
});

describe('badge count', () => {
  const badgeAfterNotifying = async (userId) => {
    await notifyUsers([userId], payload, NotificationType.response);
    return sent[0].apns.payload.aps.badge;
  };

  test('counts a request waiting on you', async () => {
    store.requests.r1 = {
      status: 'pending',
      creatorID: 'bob',
      recipientIDs: ['alice'],
      allParticipantIDs: ['alice', 'bob'],
      negotiationChain: [],
    };

    assert.equal(await badgeAfterNotifying('alice'), 1);
  });

  // The bug this replaced: `countered` is not `pending`, and after a counter the turn belongs to
  // the creator, who is not in `recipientIDs`. Both filters excluded the same request, so the
  // badge stayed at zero for every negotiation actually in flight.
  test('counts a counter-offer waiting on the creator', async () => {
    store.requests.r1 = {
      status: 'countered',
      creatorID: 'alice',
      recipientIDs: ['bob'],
      allParticipantIDs: ['alice', 'bob'],
      negotiationChain: [{ senderID: 'bob', responseType: 'counter' }],
    };

    assert.equal(await badgeAfterNotifying('alice'), 1);
  });

  // This query runs on every push, once per recipient, and was unbounded — the most frequently
  // executed read in the system with no ceiling on it. The number it produces is a badge, and
  // "200" on an app icon says everything a larger number would.
  test('the badge query is capped rather than reading everything open', async () => {
    for (let i = 0; i < 260; i += 1) {
      store.requests[`r${i}`] = {
        status: 'pending',
        creatorID: 'bob',
        recipientIDs: ['alice'],
        allParticipantIDs: ['alice', 'bob'],
        negotiationChain: [],
      };
    }

    assert.equal(await badgeAfterNotifying('alice'), 200);
  });

  test('does not count a request waiting on the other person', async () => {
    store.requests.r1 = {
      status: 'countered',
      creatorID: 'alice',
      recipientIDs: ['bob'],
      allParticipantIDs: ['alice', 'bob'],
      negotiationChain: [{ senderID: 'bob', responseType: 'counter' }],
    };

    assert.equal(await badgeAfterNotifying('bob'), 0);
  });

  // A save is a bookmark, not an answer — it leaves the turn where it was. `isMyTurn()` in
  // firestore.rules carries the same exception; if this drifts, the client offers a button the
  // backend refuses.
  test('a save leaves the turn where it was', async () => {
    store.requests.r1 = {
      status: 'saved',
      creatorID: 'bob',
      recipientIDs: ['alice'],
      allParticipantIDs: ['alice', 'bob'],
      negotiationChain: [{ senderID: 'alice', responseType: 'save' }],
    };

    assert.equal(await badgeAfterNotifying('alice'), 1);
  });

  test('a settled request counts for nobody', async () => {
    store.requests.r1 = {
      status: 'accepted',
      creatorID: 'bob',
      recipientIDs: ['alice'],
      allParticipantIDs: ['alice', 'bob'],
      negotiationChain: [{ senderID: 'alice', responseType: 'accept' }],
    };

    assert.equal(await badgeAfterNotifying('alice'), 0);
  });
});
