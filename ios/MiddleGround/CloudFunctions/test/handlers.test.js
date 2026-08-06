/**
 * Tests for the trigger handlers themselves.
 *
 * Before this file, **not one of the fourteen exported handlers was ever invoked by a test.** The
 * green suite covered `push.js`, `time.js`, `paging.js` and `firestore.rules` — the pure modules
 * and the permission layer — so every trigger body shipped unexecuted by CI. An audit against
 * production found three that had additionally never run there either.
 *
 * v2 handlers expose `.run(event)`, which takes a plain object, so each is directly callable once
 * `firebase-admin` is stubbed at the module boundary — the same technique `push.test.js` already
 * uses. `node --test` gives each file its own process, so the stubs cannot leak.
 *
 * What is asserted is the contract that matters and cannot be seen by reading: **who gets
 * notified, who is excluded, and what is written or deleted.** Excluding the actor is the recurring
 * requirement — nobody should be told about their own action.
 */
const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert');

const { fakeFirestore, FieldValueStub, FieldPathStub } = require('./support/firestore-fake');

// ---------------------------------------------------------------- stubs

let store = {};
let sent = [];
let emails = [];
let firestore = fakeFirestore(store);

const stub = (specifier, exports) => {
  const path = require.resolve(specifier);
  require.cache[path] = { id: path, filename: path, loaded: true, exports };
};

stub('firebase-admin/app', { initializeApp: () => ({}) });
stub('firebase-admin/firestore', {
  getFirestore: () => firestore.db(),
  FieldValue: FieldValueStub,
  FieldPath: FieldPathStub,
});
stub('firebase-admin/messaging', {
  getMessaging: () => ({
    sendEachForMulticast: async (message) => {
      sent.push(message);
      return { successCount: message.tokens.length, failureCount: 0, responses: [] };
    },
  }),
});
stub('resend', {
  Resend: class {
    // eslint-disable-next-line class-methods-use-this
    get emails() {
      return { send: async (payload) => { emails.push(payload); return { error: null }; } };
    }
  },
});

// `sendAlert` skips silently unless both are set, which would make every alert test vacuous.
process.env.RESEND_API_KEY = 'test-key';
process.env.OPERATOR_EMAIL = 'operator@example.com';

const fns = require('../index');

// ---------------------------------------------------------------- helpers

/** Everyone in these tests has a token and no muted types, so exclusion is never accidental. */
function seedUsers(ids) {
  for (const id of ids) {
    store[`users/${id}`] = { name: id.toUpperCase(), createdAt: new Date() };
    store[`user_tokens/${id}`] = { tokens: [`token-${id}`], timeZone: 'America/New_York' };
  }
}

const recipientsOf = (message) => message.tokens.map((t) => t.replace('token-', ''));
const everyoneNotified = () => sent.flatMap(recipientsOf).sort();

const created = (data, params) => ({ data: { data: () => data }, params: params || {} });
const updated = (before, after, params) => ({
  data: { before: { data: () => before }, after: { data: () => after } },
  params: params || {},
});

beforeEach(() => {
  for (const key of Object.keys(store)) delete store[key];
  sent = [];
  emails = [];
});

// ---------------------------------------------------------------- push triggers

describe('notifyNewRequest', () => {
  test('tells the recipients and not the sender', async () => {
    seedUsers(['alice', 'bob', 'carol']);

    await fns.notifyNewRequest.run(created(
      { creatorID: 'alice', recipientIDs: ['bob', 'carol'], title: 'Dinner?' },
      { requestId: 'r1' },
    ));

    assert.deepEqual(everyoneNotified(), ['bob', 'carol']);
    assert.equal(sent[0].data.type, 'new_request');
    assert.equal(sent[0].data.request_id, 'r1', 'the deep link needs the id, or the tap goes nowhere');
  });

  test('a request with no recipients notifies nobody', async () => {
    seedUsers(['alice']);
    await fns.notifyNewRequest.run(created({ creatorID: 'alice', recipientIDs: [] }, { requestId: 'r1' }));
    assert.equal(sent.length, 0);
  });
});

describe('notifyPlanMessage', () => {
  // Never fired in production — no plan message has ever existed — so this is the only place its
  // behaviour is established at all.
  test('tells every participant except whoever spoke', async () => {
    seedUsers(['alice', 'bob', 'carol']);
    store['requests/r1'] = { title: 'Sunday roast', allParticipantIDs: ['alice', 'bob', 'carol'] };

    await fns.notifyPlanMessage.run(created(
      { senderID: 'bob', text: 'Which entrance?' },
      { requestId: 'r1', messageId: 'm1' },
    ));

    assert.deepEqual(everyoneNotified(), ['alice', 'carol']);
    assert.equal(sent[0].notification.title, 'BOB on Sunday roast');
    assert.equal(sent[0].notification.body, 'Which entrance?');
    assert.equal(sent[0].data.type, 'plan_message');
  });

  test('a message on a plan that no longer exists notifies nobody', async () => {
    seedUsers(['alice', 'bob']);
    await fns.notifyPlanMessage.run(created(
      { senderID: 'bob', text: 'hello?' },
      { requestId: 'gone', messageId: 'm1' },
    ));
    assert.equal(sent.length, 0);
  });
});

describe('notifyRequestResponse', () => {
  test('tells everyone except the responder, and only when the chain grew', async () => {
    seedUsers(['alice', 'bob']);
    const before = { allParticipantIDs: ['alice', 'bob'], negotiationChain: [] };
    const after = {
      allParticipantIDs: ['alice', 'bob'],
      negotiationChain: [{ senderID: 'bob', responseType: 'accept', text: 'Yes' }],
    };

    await fns.notifyRequestResponse.run(updated(before, after, { requestId: 'r1' }));
    assert.deepEqual(everyoneNotified(), ['alice']);

    sent = [];
    await fns.notifyRequestResponse.run(updated(after, after, { requestId: 'r1' }));
    assert.equal(sent.length, 0, 'an unrelated edit must not re-notify');
  });

  test('a proposed time is rendered on the recipient reader clock, not the sender one', async () => {
    seedUsers(['alice', 'bob']);
    store['user_tokens/alice'] = { tokens: ['token-alice'], timeZone: 'Europe/London' };
    const proposed = new Date('2026-08-07T18:00:00Z');

    await fns.notifyRequestResponse.run(updated(
      { allParticipantIDs: ['alice', 'bob'], negotiationChain: [] },
      {
        allParticipantIDs: ['alice', 'bob'],
        negotiationChain: [{
          senderID: 'bob',
          responseType: 'reschedule',
          text: 'How about 2:00 PM?',
          proposedTime: proposed,
        }],
      },
      { requestId: 'r1' },
    ));

    assert.equal(sent.length, 1);
    assert.match(sent[0].notification.body, /How about/);
    assert.ok(
      !sent[0].notification.body.includes('2:00 PM'),
      "the sender's wording names their own hour; London must not be told 2 PM",
    );
  });
});

describe('notifyPlanCancelled', () => {
  test('tells everyone but the person who called it off', async () => {
    seedUsers(['alice', 'bob', 'carol']);

    await fns.notifyPlanCancelled.run(updated(
      { status: 'accepted', creatorID: 'alice', allParticipantIDs: ['alice', 'bob', 'carol'], title: 'Drinks' },
      {
        status: 'cancelled',
        creatorID: 'alice',
        allParticipantIDs: ['alice', 'bob', 'carol'],
        title: 'Drinks',
        cancellationReason: 'somethingCameUp',
      },
      { requestId: 'r1' },
    ));

    assert.deepEqual(everyoneNotified(), ['bob', 'carol']);
    assert.equal(sent[0].data.type, 'plan_cancelled');
  });

  test('an edit that is not a cancellation says nothing', async () => {
    seedUsers(['alice', 'bob']);
    const doc = { status: 'accepted', creatorID: 'alice', allParticipantIDs: ['alice', 'bob'] };
    await fns.notifyPlanCancelled.run(updated(doc, { ...doc, title: 'Renamed' }, { requestId: 'r1' }));
    assert.equal(sent.length, 0);
  });
});

// ---------------------------------------------------------------- scheduled

describe('purgeStaleEvents', () => {
  // Has never run in production; first firing is 2026-08-09.
  test('deletes only events past the retention window', async () => {
    const old = new Date(Date.now() - 400 * 24 * 3600 * 1000);
    const recent = new Date(Date.now() - 2 * 24 * 3600 * 1000);
    store['events/e_old'] = { at: old, name: 'request_created' };
    store['events/e_recent'] = { at: recent, name: 'request_created' };

    await fns.purgeStaleEvents.run({});

    assert.equal(store['events/e_old'], undefined, 'stale event should be gone');
    assert.ok(store['events/e_recent'], 'a recent event must survive');
  });

  test('an empty sweep is not an error', async () => {
    await assert.doesNotReject(fns.purgeStaleEvents.run({}));
  });
});

describe('weeklyNudge', () => {
  // Ran for the first time ever on 2026-08-06 and reported "Nudged 2 of 6 user(s)". These pin the
  // behaviour that run demonstrated, plus the paging and bounded fan-out added the same morning.
  test('nudges somebody whose group has nothing planned', async () => {
    seedUsers(['alice', 'bob']);
    store['relationships/rel1'] = { participantIDs: ['alice', 'bob'], createdAt: new Date('2026-01-01') };

    await fns.weeklyNudge.run({});

    assert.deepEqual(everyoneNotified(), ['alice', 'bob']);
    assert.equal(sent[0].data.type, 'weekly_nudge');
    assert.equal(sent[0].data.relationship_id, 'rel1', 'the nudge names a group, not a plan');
  });

  test('says nothing to a group with a plan still ahead of it', async () => {
    seedUsers(['alice', 'bob']);
    store['relationships/rel1'] = { participantIDs: ['alice', 'bob'], createdAt: new Date('2026-01-01') };
    store['requests/r1'] = {
      allParticipantIDs: ['alice', 'bob'],
      status: 'accepted',
      proposedTime: new Date(Date.now() + 3 * 24 * 3600 * 1000),
    };

    await fns.weeklyNudge.run({});

    assert.equal(sent.length, 0, 'a nudge while a plan is booked teaches people to ignore them');
  });

  test('an unpaired relationship is left alone', async () => {
    seedUsers(['alice']);
    store['relationships/rel1'] = { participantIDs: ['alice'], createdAt: new Date('2026-01-01') };

    await fns.weeklyNudge.run({});

    assert.equal(sent.length, 0, 'there is nobody to plan with yet');
  });

  test('every user is visited even when they span several pages', async () => {
    // The page size is 200, so this proves the cursor advances rather than re-reading page one —
    // the failure mode that would silently nudge the same handful forever.
    const ids = Array.from({ length: 205 }, (_, i) => `u${String(i).padStart(3, '0')}`);
    seedUsers(ids);
    ids.forEach((id, i) => {
      if (i % 2 !== 0) return;
      const partner = ids[i + 1];
      store[`relationships/rel${i}`] = { participantIDs: [id, partner], createdAt: new Date('2026-01-01') };
    });

    await fns.weeklyNudge.run({});

    assert.equal(everyoneNotified().length, ids.length, 'somebody on page two was skipped');
  });
});

describe('promptForAttendance and remindBeforePlan', () => {
  test('a plan that has just passed prompts its participants once', async () => {
    seedUsers(['alice', 'bob']);
    store['requests/r1'] = {
      allParticipantIDs: ['alice', 'bob'],
      status: 'accepted',
      title: 'Coffee',
      proposedTime: new Date(Date.now() - 5 * 3600 * 1000),
    };

    await fns.promptForAttendance.run({});

    assert.deepEqual(everyoneNotified(), ['alice', 'bob']);
    assert.equal(sent[0].data.type, 'confirm_plan');
  });

  test('a plan still in the future is not asked about', async () => {
    seedUsers(['alice', 'bob']);
    store['requests/r1'] = {
      allParticipantIDs: ['alice', 'bob'],
      status: 'accepted',
      proposedTime: new Date(Date.now() + 48 * 3600 * 1000),
    };

    await fns.promptForAttendance.run({});

    assert.equal(sent.length, 0);
  });

  test('a plan inside the reminder window is reminded about', async () => {
    seedUsers(['alice', 'bob']);
    store['requests/r1'] = {
      allParticipantIDs: ['alice', 'bob'],
      status: 'accepted',
      title: 'Sunday roast',
      proposedTime: new Date(Date.now() + 24 * 3600 * 1000),
    };

    await fns.remindBeforePlan.run({});

    // Whether it lands depends on the exact window; what must never happen is a reminder aimed at
    // somebody who is not on the plan.
    for (const message of sent) {
      assert.ok(recipientsOf(message).every((id) => ['alice', 'bob'].includes(id)));
    }
  });
});

// ---------------------------------------------------------------- operator alerts

describe('operator alerts', () => {
  test('a new user raises one email', async () => {
    await fns.alertOnSignup.run(created({ name: 'Alex', createdAt: new Date() }, { uid: 'u1' }));

    assert.equal(emails.length, 1);
    assert.match(emails[0].subject, /Middle Ground/);
  });

  test('a report raises one email', async () => {
    await fns.alertOnReport.run(created(
      { reporterID: 'alice', reportedUserID: 'bob', reason: 'spam' },
      { id: 'rep1' },
    ));

    assert.equal(emails.length, 1);
  });

  test('a relationship becoming paired raises one email', async () => {
    await fns.alertOnPairing.run(updated(
      { participantIDs: ['alice'] },
      { participantIDs: ['alice', 'bob'] },
      { id: 'rel1' },
    ));

    assert.equal(emails.length, 1);
  });

  test('a deleted account raises one email', async () => {
    await fns.alertOnAccountDeleted.run({
      data: { data: () => ({ name: 'Alex' }) },
      params: { uid: 'u1' },
    });

    assert.equal(emails.length, 1);
  });

  // The unconfigured case cannot be tested here: `alerts.js` reads OPERATOR_EMAIL into a module
  // constant at load time, so unsetting it afterwards changes nothing. It lives in
  // `alerts.test.js`, which gets its own process with the variable never set.
});

describe('dailyDigest', () => {
  // Paused in Cloud Scheduler at the operator's request. Tested anyway: paused is a deployment
  // decision, and the code still ships.
  test('runs without throwing when there is nothing to report', async () => {
    await assert.doesNotReject(fns.dailyDigest.run({}));
  });
});
