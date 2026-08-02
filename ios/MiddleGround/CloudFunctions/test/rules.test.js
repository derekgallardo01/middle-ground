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

  // Reversed deliberately, and its Swift counterpart with it. This asserted that an accepted
  // plan could not be cancelled — which meant the only cancellable plan was one nobody had
  // agreed to. A finished plan still cannot be cancelled; see 'calling off an agreed plan'.
  test('an agreed plan can still be called off', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r_done'), request({ status: 'accepted' })));
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'requests/r_done'), { status: 'cancelled', updatedAt: new Date() }),
    );
  });

  test('a completed plan cannot be cancelled', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r_fin'), request({ status: 'completed' })));
    await assertFails(
      updateDoc(doc(asAlice(), 'requests/r_fin'), { status: 'cancelled', updatedAt: new Date() }),
    );
  });

  // Cancelled is settled, so the record must not be removable afterwards either.
  test('a cancelled request cannot then be deleted', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r_x'), request({ status: 'cancelled' })));
    await assertFails(deleteDoc(doc(asAlice(), 'requests/r_x')));
  });
});

// Joining one plan by invite, without joining a group. This is the only branch that lets
// someone who is not already a participant write to a request, so it gets the most scrutiny.
describe('joining a single plan by invite', () => {
  const PLAN = 'requests/r_open';
  const CODE = 'MGPLAN';

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, PLAN), request({ planInviteCode: CODE, planInviteSeats: 3 }));
      await setDoc(doc(db, `invites/${CODE}`), { requestID: 'r_open', ownerID: ALICE });
    });
  });

  // These three are the gap the previous round missed entirely: every test seeded an invite
  // directly, so nothing ever exercised *issuing* one — and `planInviteCode` was pinned
  // immutable in every branch, meaning the feature could not be used by anyone who had not
  // been handed a code that could never have been created.
  test('the creator can issue a code for their own plan', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r_new'), request()));
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'requests/r_new'), {
        planInviteCode: 'MGNEW1',
        planInviteSeats: 3,
        updatedAt: new Date(),
      }),
    );
  });

  test('a recipient cannot issue a code for someone else plan', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r_new2'), request()));
    await assertFails(
      updateDoc(doc(asBob(), 'requests/r_new2'), { planInviteCode: 'MGNEW2', planInviteSeats: 3 }),
    );
  });

  // The hole this replaced: `isStaking` allows any participant to write while a plan is open
  // and did not pin the invite fields, so a recipient could mint a code for someone else's plan
  // by dressing it up as a stake.
  test('a recipient cannot mint a code by disguising it as a stake', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r_st'), request()));
    await assertFails(
      updateDoc(doc(asBob(), 'requests/r_st'), {
        stake: { proposedBy: BOB, points: 10 },
        planInviteCode: 'MGSNEAK',
        planInviteSeats: 9,
      }),
    );
  });

  test('a recipient cannot widen the seats on a code', async () => {
    await assertFails(
      updateDoc(doc(asBob(), PLAN), { planInviteSeats: 99 }),
    );
  });

  test('the creator can revoke by clearing the code', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), PLAN), { planInviteCode: null, planInviteSeats: null }),
    );
  });

  // A one-off invite has to be one-off, or a forwarded code is an open door.
  test('the code stops working once its seats are taken', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'requests/r_full'), request({
        planInviteCode: CODE,
        planInviteSeats: 2, // Alice and Bob already fill it.
      }));
    });
    await assertFails(
      updateDoc(doc(asMallory(), 'requests/r_full'), {
        recipientIDs: [BOB, MALLORY],
        allParticipantIDs: [ALICE, BOB, MALLORY],
      }),
    );
  });

  test('someone holding the code can add themselves', async () => {
    await assertSucceeds(
      updateDoc(doc(asMallory(), PLAN), {
        recipientIDs: [BOB, MALLORY],
        allParticipantIDs: [ALICE, BOB, MALLORY],
      }),
    );
  });

  test('they cannot add anybody else', async () => {
    await assertFails(
      updateDoc(doc(asMallory(), PLAN), {
        recipientIDs: [BOB, 'someone_else'],
        allParticipantIDs: [ALICE, BOB, 'someone_else'],
      }),
    );
  });

  test('a plan with no invite code cannot be joined', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r_private'), request()));
    await assertFails(
      updateDoc(doc(asMallory(), 'requests/r_private'), {
        recipientIDs: [BOB, MALLORY],
        allParticipantIDs: [ALICE, BOB, MALLORY],
      }),
    );
  });

  // The code names one request. Pointing it at a different one must not work.
  test('a code for another plan does not open this one', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'requests/r_other'), request({ planInviteCode: 'MGOTHR', planInviteSeats: 3 }));
      await setDoc(doc(db, 'invites/MGOTHR'), { requestID: 'r_somewhere_else', ownerID: ALICE });
    });
    await assertFails(
      updateDoc(doc(asMallory(), 'requests/r_other'), {
        recipientIDs: [BOB, MALLORY],
        allParticipantIDs: [ALICE, BOB, MALLORY],
      }),
    );
  });

  test('joining cannot rewrite the plan or answer it', async () => {
    await assertFails(
      updateDoc(doc(asMallory(), PLAN), {
        recipientIDs: [BOB, MALLORY],
        allParticipantIDs: [ALICE, BOB, MALLORY],
        title: 'Something else',
      }),
    );
    await assertFails(
      updateDoc(doc(asMallory(), PLAN), {
        recipientIDs: [BOB, MALLORY],
        allParticipantIDs: [ALICE, BOB, MALLORY],
        status: 'accepted',
      }),
    );
  });

  // Rotating the code is how access is revoked; a joiner must not be able to grant themselves
  // a fresh one.
  test('joining cannot rewrite the invite code', async () => {
    await assertFails(
      updateDoc(doc(asMallory(), PLAN), {
        recipientIDs: [BOB, MALLORY],
        allParticipantIDs: [ALICE, BOB, MALLORY],
        planInviteCode: 'MGMINE',
      }),
    );
  });

  test('a settled plan cannot be joined', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'requests/r_done'), request({ status: 'accepted', planInviteCode: CODE, planInviteSeats: 3 }));
    });
    await assertFails(
      updateDoc(doc(asMallory(), 'requests/r_done'), {
        recipientIDs: [BOB, MALLORY],
        allParticipantIDs: [ALICE, BOB, MALLORY],
      }),
    );
  });
});

// Points on a plan happening. Staking is not turn-taking -- either person may propose and the
// *other* must accept, which is exactly when it is not their turn -- so it needs its own branch.
describe('staking points on a plan', () => {
  beforeEach(() => seed((db) => setDoc(doc(db, 'requests/r1'), request())));

  test('a participant can propose a stake', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'requests/r1'), {
        stake: { proposedBy: ALICE, points: 25 },
        updatedAt: new Date(),
      }),
    );
  });

  test('the other person can accept it, even out of turn', async () => {
    await seed((db) =>
      setDoc(doc(db, 'requests/r_s'), request({ stake: { proposedBy: BOB, points: 25 } })),
    );
    // Alice is the creator and it is not her turn to respond, but agreeing to a stake is not
    // a response.
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'requests/r_s'), {
        stake: { proposedBy: BOB, points: 25, acceptedBy: ALICE },
      }),
    );
  });

  test('a non-participant cannot stake', async () => {
    await assertFails(
      updateDoc(doc(asMallory(), 'requests/r1'), { stake: { proposedBy: MALLORY, points: 25 } }),
    );
  });

  test('staking cannot smuggle in an answer', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'requests/r1'), {
        stake: { proposedBy: ALICE, points: 25 },
        status: 'accepted',
      }),
    );
  });

  test('a settled request cannot be staked on', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r_done'), request({ status: 'accepted' })));
    await assertFails(
      updateDoc(doc(asAlice(), 'requests/r_done'), { stake: { proposedBy: ALICE, points: 25 } }),
    );
  });

  // The settlement is derived from the confirmations, never stored, so there is nothing to
  // forge -- but the stake itself must not be rewritable by whoever confirms or responds.
  test('responding cannot rewrite the stake', async () => {
    await seed((db) =>
      setDoc(doc(db, 'requests/r_t'), request({ stake: { proposedBy: ALICE, points: 10 } })),
    );
    await assertFails(
      updateDoc(doc(asBob(), 'requests/r_t'), {
        status: 'accepted',
        stake: { proposedBy: ALICE, points: 500 },
      }),
    );
  });

  test('confirming attendance cannot rewrite the stake', async () => {
    const past = new Date(Date.now() - 24 * 60 * 60 * 1000);
    await seed((db) =>
      setDoc(doc(db, 'requests/r_u'), request({
        status: 'accepted',
        proposedTime: past,
        confirmations: {},
        stake: { proposedBy: ALICE, points: 10, acceptedBy: BOB },
      })),
    );
    await assertFails(
      updateDoc(doc(asBob(), 'requests/r_u'), {
        confirmations: { [BOB]: 'happened' },
        stake: { proposedBy: ALICE, points: 500, acceptedBy: BOB },
      }),
    );
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

// Every group in this app used to hold exactly two people: the join rule required
// `participantIDs.size() == 1`, so a second person could join and a third never could.
// Seats replace that, and the whole risk of the change is in the defaults.
describe('group seats', () => {
  const group = (overrides = {}) =>
    relationship({ type: 'friends', participantIDs: [ALICE, BOB], ...overrides });

  beforeEach(() => seed((db) => setDoc(doc(db, 'invites/MG24KT'), {
    relationshipID: 'g1', ownerID: ALICE,
  })));

  // The backwards-compatibility case, and the one that matters most on deploy day. Absence of
  // `seats` must keep meaning two, or every couple written before this silently gains six seats.
  test('a group with no stored seat count still holds only two', async () => {
    await seed((db) => setDoc(doc(db, 'relationships/g1'), group()));

    await assertFails(
      updateDoc(doc(asMallory(), 'relationships/g1'), { participantIDs: [ALICE, BOB, MALLORY] }),
    );
  });

  test('a third person can join a group with room', async () => {
    await seed((db) => setDoc(doc(db, 'relationships/g1'), group({ seats: 8 })));

    await assertSucceeds(
      updateDoc(doc(asMallory(), 'relationships/g1'), { participantIDs: [ALICE, BOB, MALLORY] }),
    );
  });

  test('nobody can join a group that is full', async () => {
    await seed((db) => setDoc(doc(db, 'relationships/g1'), group({ seats: 2 })));

    await assertFails(
      updateDoc(doc(asMallory(), 'relationships/g1'), { participantIDs: [ALICE, BOB, MALLORY] }),
    );
  });

  // Without this a member turns their couple into an eight-person group, and the couple
  // exclusion that keeps reliability scores and leaderboards out of relationships stops applying
  // to them. The ceiling has to be set once and then be unwritable.
  test('a member cannot raise their own ceiling', async () => {
    await seed((db) => setDoc(doc(db, 'relationships/g1'), group({ seats: 2 })));

    await assertFails(updateDoc(doc(asAlice(), 'relationships/g1'), { seats: 8 }));
  });

  test('a member cannot raise the ceiling while joining either', async () => {
    await seed((db) => setDoc(doc(db, 'relationships/g1'), group({ seats: 2 })));

    await assertFails(
      updateDoc(doc(asMallory(), 'relationships/g1'), {
        participantIDs: [ALICE, BOB, MALLORY],
        seats: 8,
      }),
    );
  });

  test('a couple cannot be created with room for a third', async () => {
    await assertFails(
      setDoc(doc(asBob(), 'relationships/g2'), relationship({
        type: 'couple', participantIDs: [BOB], seats: 3,
      })),
    );
    await assertSucceeds(
      setDoc(doc(asBob(), 'relationships/g3'), relationship({
        type: 'couple', participantIDs: [BOB], seats: 2,
      })),
    );
  });

  test('no group can be created beyond the ceiling', async () => {
    await assertFails(
      setDoc(doc(asBob(), 'relationships/g4'), relationship({
        type: 'friends', participantIDs: [BOB], seats: 99,
      })),
    );
  });
});

// With two people an acceptance settles the plan. With three, one friend saying yes must not
// lock the others out of saying yes too.
describe('group plans stay answerable', () => {
  const CARA = 'cara';
  const groupPlan = (overrides = {}) => request({
    recipientIDs: [BOB, CARA],
    allParticipantIDs: [ALICE, BOB, CARA],
    ...overrides,
  });

  test('a third person can still answer an accepted group plan', async () => {
    await seed((db) => setDoc(doc(db, 'requests/gp1'), groupPlan({
      status: 'accepted',
      negotiationChain: [{ id: 'm1', senderID: BOB, responseType: 'accept', timestamp: new Date() }],
    })));

    const asCara = () => testEnv.authenticatedContext(CARA).firestore();
    await assertSucceeds(
      updateDoc(doc(asCara(), 'requests/gp1'), { status: 'accepted', updatedAt: new Date() }),
    );
  });

  // The exception is scoped to `accepted`. A plan that was called off or already finished is
  // finished for everyone, and widening it to those would reopen settled decisions.
  test('a cancelled group plan is closed to everyone', async () => {
    await seed((db) => setDoc(doc(db, 'requests/gp2'), groupPlan({ status: 'cancelled' })));

    const asCara = () => testEnv.authenticatedContext(CARA).firestore();
    await assertFails(
      updateDoc(doc(asCara(), 'requests/gp2'), { status: 'accepted', updatedAt: new Date() }),
    );
  });

  test('a two-person accepted plan stays closed', async () => {
    await seed((db) => setDoc(doc(db, 'requests/gp3'), request({
      status: 'accepted',
      negotiationChain: [{ id: 'm1', senderID: BOB, responseType: 'accept', timestamp: new Date() }],
    })));

    await assertFails(
      updateDoc(doc(asAlice(), 'requests/gp3'), { status: 'declined', updatedAt: new Date() }),
    );
  });
});

// Calling off a plan people had agreed to. `!isSettled()` used to guard this, and `accepted`
// counts as settled — so the only cancellable plan was one nobody had said yes to, which is the
// one cancellation nobody minds.
describe('calling off an agreed plan', () => {
  const cancel = (extra = {}) => ({ status: 'cancelled', updatedAt: new Date(), ...extra });

  test('the creator can call off a plan that was accepted', async () => {
    await seed((db) => setDoc(doc(db, 'requests/c1'), request({ status: 'accepted' })));

    await assertSucceeds(updateDoc(doc(asAlice(), 'requests/c1'), cancel()));
  });

  test('a recipient still cannot call off someone else plan', async () => {
    await seed((db) => setDoc(doc(db, 'requests/c2'), request({ status: 'accepted' })));

    await assertFails(updateDoc(doc(asBob(), 'requests/c2'), cancel()));
  });

  // Once somebody has said whether it happened, the plan is a record. Allowing a cancellation
  // over the top of it is how a creator would erase their own no-show.
  test('a plan someone has answered about cannot be cancelled', async () => {
    await seed((db) => setDoc(doc(db, 'requests/c3'), request({
      status: 'accepted',
      confirmations: { bob: 'didNotHappen' },
    })));

    await assertFails(updateDoc(doc(asAlice(), 'requests/c3'), cancel()));
  });

  test('what is finished stays finished', async () => {
    for (const status of ['completed', 'cancelled', 'declined']) {
      await seed((db) => setDoc(doc(db, `requests/c_${status}`), request({ status })));
      await assertFails(updateDoc(doc(asAlice(), `requests/c_${status}`), cancel()));
    }
  });

  // Cancelling must not become a way to rewrite the plan on the way out.
  test('cancelling still cannot change the plan', async () => {
    await seed((db) => setDoc(doc(db, 'requests/c4'), request({ status: 'accepted' })));

    await assertFails(
      updateDoc(doc(asAlice(), 'requests/c4'), cancel({ proposedTime: new Date() })),
    );
    await assertFails(updateDoc(doc(asAlice(), 'requests/c4'), cancel({ title: 'Something else' })));
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

// The window is the whole feature. If it is enforced only in Swift, "share my location for this
// plan" means "share my location whenever", and the App Privacy answers become untrue.
describe('shared locations', () => {
  const HOUR = 60 * 60 * 1000;
  const at = (offset) => new Date(Date.now() + offset);
  const asAdmin = () => testEnv.authenticatedContext('root', { admin: true }).firestore();

  const livePlan = (proposedTime) => request({ status: 'accepted', proposedTime });

  // Expiry is derived from the plan's time, exactly as `Request.locationExpiry` does in Swift.
  // The rules pin `expiresAt <= proposedTime + 4h` with no slack, so deriving it from `now`
  // instead — as the first version of these tests did — fails by the handful of milliseconds
  // between seeding the plan and writing the point. The slack does not belong in the rule: an
  // expiry the writer picks freely is a point that outlives its plan.
  const pointFor = (proposedTime, overrides = {}) => ({
    latitude: 40.7128,
    longitude: -74.006,
    sharedAt: at(0),
    expiresAt: new Date(proposedTime.getTime() + 4 * HOUR),
    ...overrides,
  });

  let planTime;

  beforeEach(() => {
    planTime = at(0);
    return seed((db) => setDoc(doc(db, 'requests/r1'), livePlan(planTime)));
  });

  test('a participant can share and read during the plan', async () => {
    await assertSucceeds(
      setDoc(doc(asAlice(), 'requests/r1/locations/alice'), pointFor(planTime)),
    );
    await assertSucceeds(getDoc(doc(asBob(), 'requests/r1/locations/alice')));
  });

  // Including an admin. Every other private collection grants admin read; this one must not,
  // because "where a user was on Tuesday" should not follow from holding the admin flag.
  test('nobody outside the plan can read a point', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r1/locations/alice'), pointFor(planTime)));

    await assertFails(getDoc(doc(asMallory(), 'requests/r1/locations/alice')));
    await assertFails(getDoc(doc(asAnon(), 'requests/r1/locations/alice')));
    await assertFails(getDoc(doc(asAdmin(), 'requests/r1/locations/alice')));
  });

  test('you cannot write a point as somebody else', async () => {
    await assertFails(setDoc(doc(asBob(), 'requests/r1/locations/alice'), pointFor(planTime)));
  });

  test('an outsider cannot write a point at all', async () => {
    await assertFails(
      setDoc(doc(asMallory(), 'requests/r1/locations/mallory'), pointFor(planTime)),
    );
  });

  test('too early is refused', async () => {
    const time = at(3 * HOUR);
    await seed((db) => setDoc(doc(db, 'requests/r2'), livePlan(time)));

    await assertFails(setDoc(doc(asAlice(), 'requests/r2/locations/alice'), pointFor(time)));
  });

  test('too late is refused', async () => {
    const time = at(-6 * HOUR);
    await seed((db) => setDoc(doc(db, 'requests/r3'), livePlan(time)));

    await assertFails(setDoc(doc(asAlice(), 'requests/r3/locations/alice'), pointFor(time)));
  });

  // An hour before is inside the window on purpose: "I'm five minutes away" is said on the way.
  test('an hour before the plan is allowed', async () => {
    const time = at(0.5 * HOUR);
    await seed((db) => setDoc(doc(db, 'requests/r4'), livePlan(time)));

    await assertSucceeds(setDoc(doc(asAlice(), 'requests/r4/locations/alice'), pointFor(time)));
  });

  test('a plan nobody accepted has no window', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r5'), request({ proposedTime: planTime })));

    await assertFails(setDoc(doc(asAlice(), 'requests/r5/locations/alice'), pointFor(planTime)));
  });

  test('an undated request has no window', async () => {
    await seed((db) => setDoc(doc(db, 'requests/r6'), request({ status: 'accepted' })));

    await assertFails(setDoc(doc(asAlice(), 'requests/r6/locations/alice'), pointFor(planTime)));
  });

  // Without this the window is enforced on the write and then ignored by the thing that deletes
  // it — a point that outlives its plan by a year, written entirely within the rules.
  test('an expiry beyond the window is refused', async () => {
    await assertFails(
      setDoc(
        doc(asAlice(), 'requests/r1/locations/alice'),
        pointFor(planTime, { expiresAt: at(48 * HOUR) }),
      ),
    );
  });

  test('an unexpected field is refused', async () => {
    await assertFails(
      setDoc(
        doc(asAlice(), 'requests/r1/locations/alice'),
        { ...pointFor(planTime), accuracy: 5 },
      ),
    );
  });

  // Taking it back must never be the thing that is refused.
  test('you can always withdraw your own point', async () => {
    const time = at(-48 * HOUR);
    await seed((db) => setDoc(doc(db, 'requests/r7'), livePlan(time)));
    await seed((db) => setDoc(doc(db, 'requests/r7/locations/alice'), pointFor(time)));

    await assertSucceeds(deleteDoc(doc(asAlice(), 'requests/r7/locations/alice')));
  });
});

// Editorial content rather than user data — the one collection here that is deliberately
// readable and listable by everyone signed in.
describe('venues', () => {
  const asAdmin = () => testEnv.authenticatedContext('root', { admin: true }).firestore();
  const venue = { name: "Lucia's", city: 'Brooklyn', categories: ['dating'], emoji: '🍝', rank: 0 };

  beforeEach(() => seed((db) => setDoc(doc(db, 'venues/v1'), venue)));

  test('any signed-in user can read and list them', async () => {
    await assertSucceeds(getDoc(doc(asBob(), 'venues/v1')));
    await assertSucceeds(getDocs(collection(asBob(), 'venues')));
  });

  test('an anonymous client cannot', async () => {
    await assertFails(getDoc(doc(asAnon(), 'venues/v1')));
  });

  // The whole point of curating in Firestore is that the list can be fixed without a release —
  // which is only safe if the list cannot be edited by whoever feels like it.
  test('an ordinary user cannot add, change or remove one', async () => {
    await assertFails(setDoc(doc(asBob(), 'venues/v2'), venue));
    await assertFails(updateDoc(doc(asBob(), 'venues/v1'), { name: 'Somewhere else' }));
    await assertFails(deleteDoc(doc(asBob(), 'venues/v1')));
  });

  test('an admin can curate the list', async () => {
    await assertSucceeds(setDoc(doc(asAdmin(), 'venues/v2'), venue));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'venues/v1'), { rank: 3 }));
    await assertSucceeds(deleteDoc(doc(asAdmin(), 'venues/v1')));
  });
});

// What someone has chosen to be interrupted about is theirs to know.
describe('notification settings', () => {
  beforeEach(() =>
    seed((db) => setDoc(doc(db, 'notification_settings/alice'), { newRequest: false })),
  );

  test('you can read and write your own', async () => {
    await assertSucceeds(getDoc(doc(asAlice(), 'notification_settings/alice')));
    await assertSucceeds(
      setDoc(doc(asAlice(), 'notification_settings/alice'), { newRequest: true }),
    );
  });

  test('you cannot read or write someone else settings', async () => {
    await assertFails(getDoc(doc(asBob(), 'notification_settings/alice')));
    await assertFails(
      setDoc(doc(asBob(), 'notification_settings/alice'), { newRequest: true }),
    );
  });

  test('an anonymous client is refused', async () => {
    await assertFails(getDoc(doc(asAnon(), 'notification_settings/alice')));
  });

  // Account deletion depends on this: AccountDataPurger deletes this document from the client
  // before the auth record goes. If the rule ever tightens to read/write only, the delete fails
  // silently and a document keyed by the user's ID outlives the account that owned it.
  test('you can delete your own, which is what account deletion relies on', async () => {
    await assertFails(deleteDoc(doc(asBob(), 'notification_settings/alice')));
    await assertSucceeds(deleteDoc(doc(asAlice(), 'notification_settings/alice')));
  });
});

// These rows are kept when events and requests are not, which is only defensible while they
// cannot identify anyone. The rules are the enforcement, so they are what gets tested.
describe('plan outcomes', () => {
  const asAdmin = () => testEnv.authenticatedContext('root', { admin: true }).firestore();
  const valid = {
    outcome: 'attended',
    groupSize: 3,
    category: 'friends',
    hadProposedTime: true,
    hoursBeforePlan: -2,
    at: new Date(),
  };

  test('a signed-in user can record an anonymous outcome', async () => {
    await assertSucceeds(setDoc(doc(asAlice(), 'plan_outcomes/o1'), valid));
  });

  test('an anonymous client cannot write one', async () => {
    await assertFails(setDoc(doc(asAnon(), 'plan_outcomes/o1'), valid));
  });

  // The point of the collection: a row that cannot be traced to a person survives account
  // deletion honestly. A client that smuggles an identifier in defeats that entirely.
  test('a row carrying a user or request identifier is refused', async () => {
    await assertFails(
      setDoc(doc(asAlice(), 'plan_outcomes/o2'), { ...valid, userID: ALICE }),
    );
    await assertFails(
      setDoc(doc(asAlice(), 'plan_outcomes/o3'), { ...valid, requestID: 'r1' }),
    );
  });

  test('an unrecognised outcome is refused', async () => {
    await assertFails(
      setDoc(doc(asAlice(), 'plan_outcomes/o4'), { ...valid, outcome: 'whatever' }),
    );
  });

  test('a group of fewer than two is refused', async () => {
    await assertFails(setDoc(doc(asAlice(), 'plan_outcomes/o5'), { ...valid, groupSize: 1 }));
  });

  test('append-only: no rewriting or deleting what was recorded', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'plan_outcomes/o6'), valid);
    });
    await assertFails(updateDoc(doc(asAlice(), 'plan_outcomes/o6'), { outcome: 'agreed' }));
    await assertFails(deleteDoc(doc(asAlice(), 'plan_outcomes/o6'), {}));
    await assertFails(updateDoc(doc(asAdmin(), 'plan_outcomes/o6'), { outcome: 'agreed' }));
    await assertFails(deleteDoc(doc(asAdmin(), 'plan_outcomes/o6'), {}));
  });

  test('only an admin reads them back', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'plan_outcomes/o7'), valid);
    });
    await assertFails(getDoc(doc(asAlice(), 'plan_outcomes/o7')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'plan_outcomes/o7')));
  });
});

describe('unmatched paths', () => {
  test('a collection with no rule is denied', async () => {
    await assertFails(getDoc(doc(asAlice(), 'secrets/s1')));
    await assertFails(setDoc(doc(asAlice(), 'secrets/s1'), { a: 1 }));
  });
});
