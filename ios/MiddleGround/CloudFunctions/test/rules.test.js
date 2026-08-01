/**
 * Security-rules tests for firestore.rules.
 *
 * Run against the emulator:
 *   cd ios/MiddleGround
 *   npx firebase-tools emulators:exec --only firestore "cd CloudFunctions && npm test"
 *
 * These exist because the rules encode the app's entire privacy model: requests are
 * readable only by their participants, and invite codes must be redeemable-but-not-
 * enumerable. Both are easy to get subtly wrong and impossible to verify by reading.
 */

const { test, before, after, beforeEach, describe } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs,
} = require('firebase/firestore');

const ALICE = 'alice';
const BOB = 'bob';
const MALLORY = 'mallory';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'middle-ground-rules-test',
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

const asAlice = () => testEnv.authenticatedContext(ALICE).firestore();
const asBob = () => testEnv.authenticatedContext(BOB).firestore();
const asMallory = () => testEnv.authenticatedContext(MALLORY).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

/** Writes fixtures bypassing rules. */
const seed = (fn) => testEnv.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

const request = (overrides = {}) => ({
  creatorID: ALICE,
  recipientIDs: [BOB],
  allParticipantIDs: [ALICE, BOB],
  category: 'relationship',
  title: 'Dinner?',
  status: 'pending',
  negotiationChain: [],
  createdAt: new Date(),
  updatedAt: new Date(),
  ...overrides,
});

const relationship = (overrides = {}) => ({
  participantIDs: [ALICE],
  type: 'couple',
  createdAt: new Date(),
  growthScore: 0,
  inviteCode: 'MG24KT',
  ...overrides,
});

describe('requests', () => {
  beforeEach(() => seed((db) => setDoc(doc(db, 'requests/r1'), request())));

  test('a participant can read', async () => {
    await assertSucceeds(getDoc(doc(asBob(), 'requests/r1')));
  });

  test('a non-participant cannot read', async () => {
    await assertFails(getDoc(doc(asMallory(), 'requests/r1')));
  });

  test('an anonymous client cannot read', async () => {
    await assertFails(getDoc(doc(asAnon(), 'requests/r1')));
  });

  test('the creator can create a request they are part of', async () => {
    await assertSucceeds(setDoc(doc(asAlice(), 'requests/r2'), request()));
  });

  test('a request cannot be created on someone else behalf', async () => {
    await assertFails(
      setDoc(doc(asMallory(), 'requests/r3'), request({ creatorID: ALICE })),
    );
  });

  test('a participant can respond', async () => {
    await assertSucceeds(
      updateDoc(doc(asBob(), 'requests/r1'), { status: 'accepted', updatedAt: new Date() }),
    );
  });

  test('a non-participant cannot respond', async () => {
    await assertFails(updateDoc(doc(asMallory(), 'requests/r1'), { status: 'accepted' }));
  });

  test('a participant cannot rewrite authorship', async () => {
    await assertFails(updateDoc(doc(asBob(), 'requests/r1'), { creatorID: BOB }));
  });

  test('a participant cannot add themselves to another set of people', async () => {
    await assertFails(
      updateDoc(doc(asBob(), 'requests/r1'), { allParticipantIDs: [ALICE, BOB, MALLORY] }),
    );
  });

  test('only the creator can delete', async () => {
    await assertFails(deleteDoc(doc(asBob(), 'requests/r1')));
    await assertSucceeds(deleteDoc(doc(asAlice(), 'requests/r1')));
  });

  // The rule used to allow the creator to delete anything they created, settled or not, even
  // though its own comment claimed otherwise. Once attendance is recorded on a request, that is
  // a way to erase your own no-shows.
  test('the creator cannot delete a settled request', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r_done'), request({ status: 'accepted' })));
    await assertFails(deleteDoc(doc(asAlice(), 'requests/r_done')));
  });

  // Cancelling something the other person countered is legitimate, and the client offers it —
  // a stricter rule would refuse a button the app shows.
  test('the creator can still cancel a request mid-negotiation', async () => {
    await seed((db) =>
      setDoc(doc(db, 'requests/r_mid'), request({
        status: 'countered',
        negotiationChain: [{ id: 'm1', senderID: BOB, responseType: 'counter', timestamp: new Date() }],
      })),
    );
    await assertSucceeds(deleteDoc(doc(asAlice(), 'requests/r_mid')));
  });
});

// Cancelling keeps the record instead of deleting it, so "cancelled three times in a row" can
// ever mean anything.
describe('cancelling a request', () => {
  beforeEach(() => seed((db) => setDoc(doc(db, 'requests/r1'), request())));

  test('the creator can cancel with a reason', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'requests/r1'), {
        status: 'cancelled',
        cancellationReason: 'unwell',
        updatedAt: new Date(),
      }),
    );
  });

  test('a recipient cannot cancel someone else request', async () => {
    await assertFails(
      updateDoc(doc(asBob(), 'requests/r1'), { status: 'cancelled' }),
    );
  });

  test('cancelling cannot rewrite the plan', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'requests/r1'), {
        status: 'cancelled',
        title: 'Something else',
      }),
    );
  });

  test('an already settled request cannot be cancelled', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r_done'), request({ status: 'accepted' })));
    await assertFails(
      updateDoc(doc(asAlice(), 'requests/r_done'), { status: 'cancelled' }),
    );
  });

  // Cancelled is settled, so the record must not be removable afterwards either.
  test('a cancelled request cannot then be deleted', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r_x'), request({ status: 'cancelled' })));
    await assertFails(deleteDoc(doc(asAlice(), 'requests/r_x')));
  });
});

// Recording whether an accepted plan actually happened — the only write permitted on a settled
// request, and the signal every reliability idea is computed from.
describe('confirming attendance', () => {
  const past = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const future = new Date(Date.now() + 24 * 60 * 60 * 1000);

  const accepted = (overrides = {}) =>
    request({ status: 'accepted', proposedTime: past, confirmations: {}, ...overrides });

  beforeEach(() => seed((db) => setDoc(doc(db, 'requests/r_past'), accepted())));

  test('a participant can record their own answer', async () => {
    await assertSucceeds(
      updateDoc(doc(asBob(), 'requests/r_past'), { confirmations: { [BOB]: 'happened' } }),
    );
  });

  test('a participant cannot answer for the other person', async () => {
    await assertFails(
      updateDoc(doc(asBob(), 'requests/r_past'), { confirmations: { [ALICE]: 'didNotHappen' } }),
    );
  });

  test('a non-participant cannot answer at all', async () => {
    await assertFails(
      updateDoc(doc(asMallory(), 'requests/r_past'), { confirmations: { [MALLORY]: 'happened' } }),
    );
  });

  test('a plan that has not happened yet cannot be confirmed', async () => {
    await seed((db) =>
      setDoc(doc(db, 'requests/r_future'), accepted({ proposedTime: future })),
    );
    await assertFails(
      updateDoc(doc(asBob(), 'requests/r_future'), { confirmations: { [BOB]: 'happened' } }),
    );
  });

  test('confirming cannot be used to edit the plan itself', async () => {
    await assertFails(
      updateDoc(doc(asBob(), 'requests/r_past'), {
        confirmations: { [BOB]: 'happened' },
        title: 'Something else entirely',
      }),
    );
    await assertFails(
      updateDoc(doc(asBob(), 'requests/r_past'), {
        confirmations: { [BOB]: 'happened' },
        proposedTime: future,
      }),
    );
  });

  // A request with no time has no moment to ask about, so it never enters confirmation.
  test('an undated plan cannot be confirmed', async () => {
    await seed((db) =>
      setDoc(doc(db, 'requests/r_undated'), accepted({ proposedTime: null })),
    );
    await assertFails(
      updateDoc(doc(asBob(), 'requests/r_undated'), { confirmations: { [BOB]: 'happened' } }),
    );
  });

  // Settled requests are otherwise frozen, and must stay that way.
  test('confirming does not reopen the decision', async () => {
    await assertFails(
      updateDoc(doc(asBob(), 'requests/r_past'), { status: 'pending' }),
    );
  });
});

describe('turn taking on a request', () => {
  // Mirrors `Request.awaitingResponseFrom`. The rules used to require `uid() in recipientIDs`,
  // which froze every conversation after one reply: a counter handed the turn back to the
  // creator and the backend refused their answer.
  const msg = (sender, type) => ({
    id: `m-${sender}-${type}`, senderID: sender, responseType: type, text: null, timestamp: new Date(),
  });

  test('the creator may answer after the recipient counters', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r1'), request({
      status: 'countered', negotiationChain: [msg(BOB, 'counter')],
    })));
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'requests/r1'), { status: 'accepted', updatedAt: new Date() }),
    );
  });

  test('you cannot answer your own last message', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r1'), request({
      status: 'countered', negotiationChain: [msg(BOB, 'counter')],
    })));
    await assertFails(updateDoc(doc(asBob(), 'requests/r1'), { status: 'accepted' }));
  });

  test('the creator cannot answer before the recipient has', async () => {
    // No messages yet, so the turn is the recipient's — this is the rule that stops one
    // person closing a shared decision alone.
    await assertFails(updateDoc(doc(asAlice(), 'requests/r1'), { status: 'accepted' }));
  });

  test('a settled request cannot be reopened by anyone', async () => {
    for (const status of ['accepted', 'declined', 'completed']) {
      await seed((db) => setDoc(doc(db, 'requests/r1'), request({
        status, negotiationChain: [msg(BOB, 'accept')],
      })));
      await assertFails(updateDoc(doc(asAlice(), 'requests/r1'), { status: 'pending' }));
      await assertFails(updateDoc(doc(asBob(), 'requests/r1'), { status: 'pending' }));
    }
  });

  test('saving leaves the turn where it was', async () => {
    // A save is a bookmark, not an answer. Without the explicit carve-out the saver would be
    // locked out of ever accepting — the client would offer the button and this would refuse.
    await seed((db) => setDoc(doc(db, 'requests/r1'), request({
      status: 'saved', negotiationChain: [msg(BOB, 'save')],
    })));
    await assertSucceeds(
      updateDoc(doc(asBob(), 'requests/r1'), { status: 'accepted', updatedAt: new Date() }),
    );
  });

  test('an outsider never gets a turn', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r1'), request({
      status: 'countered', negotiationChain: [msg(BOB, 'counter')],
    })));
    await assertFails(updateDoc(doc(asMallory(), 'requests/r1'), { status: 'accepted' }));
  });
});

describe('relationships and invite redemption', () => {
  beforeEach(() => seed(async (db) => {
    await setDoc(doc(db, 'relationships/rel1'), relationship());
    await setDoc(doc(db, 'invites/MG24KT'), { relationshipID: 'rel1', ownerID: ALICE });
  }));

  test('a member can read', async () => {
    await assertSucceeds(getDoc(doc(asAlice(), 'relationships/rel1')));
  });

  test('a non-member cannot read', async () => {
    await assertFails(getDoc(doc(asBob(), 'relationships/rel1')));
  });

  test('a relationship is created containing only its owner', async () => {
    await assertSucceeds(
      setDoc(doc(asBob(), 'relationships/rel2'), relationship({ participantIDs: [BOB] })),
    );
    await assertFails(
      setDoc(doc(asBob(), 'relationships/rel3'), relationship({ participantIDs: [BOB, MALLORY] })),
    );
  });

  test('holding a valid code lets you add yourself', async () => {
    await assertSucceeds(
      updateDoc(doc(asBob(), 'relationships/rel1'), { participantIDs: [ALICE, BOB] }),
    );
  });

  test('you cannot add someone else while redeeming', async () => {
    await assertFails(
      updateDoc(doc(asBob(), 'relationships/rel1'), { participantIDs: [ALICE, MALLORY] }),
    );
  });

  test('you cannot join a relationship that is already paired', async () => {
    await seed((db) => setDoc(doc(db, 'relationships/rel1'), relationship({
      participantIDs: [ALICE, BOB],
    })));
    await assertFails(
      updateDoc(doc(asMallory(), 'relationships/rel1'), {
        participantIDs: [ALICE, BOB, MALLORY],
      }),
    );
  });

  test('redeeming cannot rewrite the invite code or type', async () => {
    await assertFails(
      updateDoc(doc(asBob(), 'relationships/rel1'), {
        participantIDs: [ALICE, BOB],
        inviteCode: 'HACKED',
      }),
    );
    await assertFails(
      updateDoc(doc(asBob(), 'relationships/rel1'), {
        participantIDs: [ALICE, BOB],
        type: 'coworkers',
      }),
    );
  });

  test('joining fails when no invite document exists for the code', async () => {
    await seed((db) => deleteDoc(doc(db, 'invites/MG24KT')));
    await assertFails(
      updateDoc(doc(asBob(), 'relationships/rel1'), { participantIDs: [ALICE, BOB] }),
    );
  });

  test('relationships cannot be deleted', async () => {
    await assertFails(deleteDoc(doc(asAlice(), 'relationships/rel1')));
  });
});

describe('leaving a group', () => {
  // The only escape from an abusive partner short of deleting your whole account, so the
  // rule has to permit exactly one shape: removing yourself and nothing else.
  beforeEach(() => seed(async (db) => {
    await setDoc(doc(db, 'relationships/rel1'), relationship({ participantIDs: [ALICE, BOB] }));
    await setDoc(doc(db, 'invites/MG24KT'), { relationshipID: 'rel1', ownerID: ALICE });
  }));

  test('a member can remove themselves', async () => {
    await assertSucceeds(
      updateDoc(doc(asBob(), 'relationships/rel1'), { participantIDs: [ALICE] }),
    );
  });

  test('the owner can also remove themselves', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'relationships/rel1'), { participantIDs: [BOB] }),
    );
  });

  test('a member cannot evict the other person', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'relationships/rel1'), { participantIDs: [ALICE] }),
    );
    await assertFails(
      updateDoc(doc(asBob(), 'relationships/rel1'), { participantIDs: [BOB] }),
    );
  });

  test('a non-member cannot remove anyone', async () => {
    await assertFails(
      updateDoc(doc(asMallory(), 'relationships/rel1'), { participantIDs: [ALICE] }),
    );
  });

  test('leaving cannot smuggle in a change to another field', async () => {
    await assertFails(
      updateDoc(doc(asBob(), 'relationships/rel1'), {
        participantIDs: [ALICE],
        type: 'coworkers',
      }),
    );
  });

  test('the owner can revoke their own invite code on the way out', async () => {
    await assertSucceeds(deleteDoc(doc(asAlice(), 'invites/MG24KT')));
  });

  test('a non-owner cannot revoke the invite code', async () => {
    await assertFails(deleteDoc(doc(asBob(), 'invites/MG24KT')));
  });
});

describe('rotating an invite code', () => {
  beforeEach(() => seed(async (db) => {
    await setDoc(doc(db, 'relationships/rel1'), relationship());
    await setDoc(doc(db, 'invites/MG24KT'), { relationshipID: 'rel1', ownerID: ALICE });
  }));

  test('the owner can change the code', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'relationships/rel1'), { inviteCode: 'NEWXYZ' }),
    );
  });

  test('a non-owner cannot change the code', async () => {
    await seed((db) => setDoc(doc(db, 'relationships/rel1'), relationship({
      participantIDs: [ALICE, BOB],
    })));
    await assertFails(
      updateDoc(doc(asBob(), 'relationships/rel1'), { inviteCode: 'NEWXYZ' }),
    );
  });

  test('rotating cannot change who is in the group', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'relationships/rel1'), {
        inviteCode: 'NEWXYZ',
        participantIDs: [ALICE, MALLORY],
      }),
    );
  });
});

describe('abuse reports', () => {
  const report = (overrides = {}) => ({
    reporterID: BOB,
    requestID: 'r1',
    reportedUserID: ALICE,
    reason: 'harassment',
    note: null,
    at: new Date(),
    ...overrides,
  });

  test('a user can file a report', async () => {
    await assertSucceeds(setDoc(doc(asBob(), 'reports/rep1'), report()));
  });

  test('a report cannot be filed in someone else name', async () => {
    await assertFails(
      setDoc(doc(asMallory(), 'reports/rep2'), report({ reporterID: BOB })),
    );
  });

  test('you cannot report yourself', async () => {
    await assertFails(
      setDoc(doc(asBob(), 'reports/rep3'), report({ reportedUserID: BOB })),
    );
  });

  test('a reporter cannot read reports back', async () => {
    // Deliberate: being able to list reports would expose who reported whom.
    await seed((db) => setDoc(doc(db, 'reports/rep1'), report()));
    await assertFails(getDoc(doc(asBob(), 'reports/rep1')));
  });

  test('reports cannot be edited or deleted', async () => {
    await seed((db) => setDoc(doc(db, 'reports/rep1'), report()));
    await assertFails(updateDoc(doc(asBob(), 'reports/rep1'), { reason: 'spam' }));
    await assertFails(deleteDoc(doc(asBob(), 'reports/rep1')));
  });
});

describe('events are self-readable and self-erasable', () => {
  // Account deletion has to be able to erase these from the client while Cloud Functions
  // are undeployed, which needs list access to discover the document IDs.
  beforeEach(() => seed(async (db) => {
    await setDoc(doc(db, 'events/e1'), { userID: BOB, type: 'app_opened', at: new Date() });
    await setDoc(doc(db, 'events/e2'), { userID: ALICE, type: 'app_opened', at: new Date() });
  }));

  test('a user can read their own event', async () => {
    await assertSucceeds(getDoc(doc(asBob(), 'events/e1')));
  });

  test('a user cannot read somebody else event', async () => {
    await assertFails(getDoc(doc(asBob(), 'events/e2')));
  });

  test('a user can delete their own event', async () => {
    await assertSucceeds(deleteDoc(doc(asBob(), 'events/e1')));
  });

  test('a user cannot delete somebody else event', async () => {
    await assertFails(deleteDoc(doc(asBob(), 'events/e2')));
  });

  test('events still cannot be rewritten', async () => {
    await assertFails(updateDoc(doc(asBob(), 'events/e1'), { type: 'signed_up' }));
  });
});

describe('invites', () => {
  beforeEach(() => seed((db) => setDoc(doc(db, 'invites/MG24KT'), {
    relationshipID: 'rel1',
    ownerID: ALICE,
  })));

  test('a code you were told can be fetched', async () => {
    await assertSucceeds(getDoc(doc(asBob(), 'invites/MG24KT')));
  });

  test('codes cannot be enumerated', async () => {
    // This is the property that makes the whole scheme safe.
    await assertFails(getDocs(collection(asBob(), 'invites')));
  });

  test('an anonymous client cannot read a code', async () => {
    await assertFails(getDoc(doc(asAnon(), 'invites/MG24KT')));
  });

  test('an invite cannot be created naming someone else as owner', async () => {
    await assertFails(
      setDoc(doc(asMallory(), 'invites/NEWONE'), { relationshipID: 'rel1', ownerID: ALICE }),
    );
    await assertSucceeds(
      setDoc(doc(asMallory(), 'invites/MINE01'), { relationshipID: 'rel9', ownerID: MALLORY }),
    );
  });
});

describe('users', () => {
  beforeEach(() => seed((db) => setDoc(doc(db, 'users/alice'), { name: 'Alice' })));

  test('a signed-in user can read a profile to show a partner name', async () => {
    await assertSucceeds(getDoc(doc(asBob(), 'users/alice')));
  });

  test('profiles cannot be enumerated', async () => {
    await assertFails(getDocs(collection(asBob(), 'users')));
  });

  test('you can delete your own profile (account deletion)', async () => {
    await assertSucceeds(deleteDoc(doc(asAlice(), 'users/alice')));
  });

  test('you cannot delete someone else profile', async () => {
    await assertFails(deleteDoc(doc(asBob(), 'users/alice')));
  });

  test('you can only write your own profile', async () => {
    await assertSucceeds(setDoc(doc(asAlice(), 'users/alice'), { name: 'Alice B' }));
    await assertFails(setDoc(doc(asBob(), 'users/alice'), { name: 'Hacked' }));
  });
});

describe('user_tokens', () => {
  beforeEach(() => seed((db) => setDoc(doc(db, 'user_tokens/alice'), { tokens: ['t1'] })));

  test('device tokens are never client-readable, not even your own', async () => {
    await assertFails(getDoc(doc(asAlice(), 'user_tokens/alice')));
    await assertFails(getDoc(doc(asBob(), 'user_tokens/alice')));
  });

  test('you can register your own token', async () => {
    await assertSucceeds(setDoc(doc(asAlice(), 'user_tokens/alice'), { tokens: ['t2'] }));
  });

  test('you cannot write someone else tokens', async () => {
    await assertFails(setDoc(doc(asBob(), 'user_tokens/alice'), { tokens: ['evil'] }));
  });
});

describe('admin access', () => {
  // The admin claim is the whole security model for the operator panel: the in-app tab is a
  // convenience gate, these rules are the enforcement.
  const asAdmin = () =>
    testEnv.authenticatedContext('root', { admin: true }).firestore();

  beforeEach(() => seed(async (db) => {
    await setDoc(doc(db, 'requests/r1'), request());
    await setDoc(doc(db, 'users/alice'), { name: 'Alice' });
    await setDoc(doc(db, 'events/e1'), { userID: ALICE, type: 'app_opened', at: new Date() });
  }));

  test('an admin can read a request they are not part of', async () => {
    await assertFails(getDoc(doc(asMallory(), 'requests/r1')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'requests/r1')));
  });

  test('only an admin can list users', async () => {
    await assertFails(getDocs(collection(asBob(), 'users')));
    await assertSucceeds(getDocs(collection(asAdmin(), 'users')));
  });

  test('events are admin-read-only', async () => {
    // Not even the author may read their own events back, so the log cannot be mined.
    await assertFails(getDocs(collection(asAlice(), 'events')));
    await assertSucceeds(getDocs(collection(asAdmin(), 'events')));
  });

  test('a user may write only their own events', async () => {
    await assertSucceeds(
      setDoc(doc(asAlice(), 'events/mine'), { userID: ALICE, type: 'app_opened', at: new Date() }),
    );
    await assertFails(
      setDoc(doc(asAlice(), 'events/forged'), { userID: BOB, type: 'app_opened', at: new Date() }),
    );
  });

  test('events cannot be edited or deleted, even by an admin', async () => {
    await assertFails(updateDoc(doc(asAdmin(), 'events/e1'), { type: 'signed_up' }));
    await assertFails(deleteDoc(doc(asAdmin(), 'events/e1')));
  });
});

describe('admin audit trail', () => {
  const asAdmin = () =>
    testEnv.authenticatedContext('root', { admin: true }).firestore();

  beforeEach(() => seed((db) => setDoc(doc(db, 'admin_audit/a1'), {
    adminID: 'root', action: 'viewed_user', targetType: 'user', targetID: ALICE, at: new Date(),
  })));

  test('non-admins cannot read the audit trail', async () => {
    await assertFails(getDocs(collection(asAlice(), 'admin_audit')));
  });

  test('an admin can read it and append to it', async () => {
    await assertSucceeds(getDocs(collection(asAdmin(), 'admin_audit')));
    await assertSucceeds(setDoc(doc(asAdmin(), 'admin_audit/a2'), {
      adminID: 'root', action: 'viewed_request', targetType: 'request', targetID: 'r1', at: new Date(),
    }));
  });

  test('an admin cannot attribute an entry to a different admin', async () => {
    await assertFails(setDoc(doc(asAdmin(), 'admin_audit/a3'), {
      adminID: 'someone-else', action: 'viewed_user', targetType: 'user', targetID: ALICE, at: new Date(),
    }));
  });

  test('the trail is append-only — an admin cannot rewrite or erase their tracks', async () => {
    // This is the property that makes the log worth having.
    await assertFails(updateDoc(doc(asAdmin(), 'admin_audit/a1'), { action: 'nothing' }));
    await assertFails(deleteDoc(doc(asAdmin(), 'admin_audit/a1')));
  });
});

describe('gamification mirror', () => {
  const asAdmin = () =>
    testEnv.authenticatedContext('root', { admin: true }).firestore();

  beforeEach(() => seed((db) => setDoc(doc(db, 'gamification/alice'), { relationshipXP: 100 })));

  test('you can read and write your own progress', async () => {
    await assertSucceeds(getDoc(doc(asAlice(), 'gamification/alice')));
    await assertSucceeds(setDoc(doc(asAlice(), 'gamification/alice'), { relationshipXP: 125 }));
  });

  test('you cannot read or write someone else progress', async () => {
    await assertFails(getDoc(doc(asBob(), 'gamification/alice')));
    await assertFails(setDoc(doc(asBob(), 'gamification/alice'), { relationshipXP: 9999 }));
  });

  test('an admin can read it', async () => {
    await assertSucceeds(getDoc(doc(asAdmin(), 'gamification/alice')));
  });
});

describe('unmatched paths', () => {
  test('a collection with no rule is denied', async () => {
    await assertFails(getDoc(doc(asAlice(), 'secrets/s1')));
    await assertFails(setDoc(doc(asAlice(), 'secrets/s1'), { a: 1 }));
  });
});
