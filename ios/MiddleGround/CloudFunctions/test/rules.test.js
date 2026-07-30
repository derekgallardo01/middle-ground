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
  savedForLater: false,
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

describe('unmatched paths', () => {
  test('a collection with no rule is denied', async () => {
    await assertFails(getDoc(doc(asAlice(), 'secrets/s1')));
    await assertFails(setDoc(doc(asAlice(), 'secrets/s1'), { a: 1 }));
  });
});
