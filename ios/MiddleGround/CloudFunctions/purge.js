// Modular API — firebase-admin v14 removed `admin.firestore()`. See the note in push.js.
const { getFirestore } = require('firebase-admin/firestore');

const db = () => getFirestore();

/**
 * Removes everything belonging to a deleted user.
 *
 * App Store Guideline 5.1.1(v) requires in-app account deletion, and deleting the auth record
 * is not enough on its own — the Firestore documents must go too. `AccountDataPurger` on the
 * client does most of this before the auth account goes, but a client can be killed mid-purge
 * and there are documents security rules deliberately forbid it from touching. This runs with
 * admin privileges and is the durable backstop.
 */
async function purgeUserData(uid) {
  console.log(`Purging data for deleted user ${uid}`);

  const results = await Promise.allSettled([
    db().collection('users').doc(uid).delete(),
    db().collection('user_tokens').doc(uid).delete(),
    db().collection('gamification').doc(uid).delete(),
    db().collection('notification_settings').doc(uid).delete(),
    purgeInvites(uid),
    purgeRelationships(uid),
    purgeRequests(uid),
    purgeEvents(uid),
    purgeMessages(uid),
  ]);

  results.forEach((r, i) => {
    if (r.status === 'rejected') {
      console.error(`Purge step ${i} failed for ${uid}:`, r.reason);
    }
  });

  console.log(`Finished purging ${uid}`);
}

/**
 * Removes everything this person said, wherever they said it.
 *
 * Subcollections are NOT deleted when their parent document is, so a deleted user's messages
 * outlive both the account and, often, the plan they were written on. A collection-group query is
 * the only way to find them all: they are scattered under every request the person was ever on,
 * including ones somebody else still owns.
 */
async function purgeMessages(uid) {
  const snapshot = await db()
    .collectionGroup('messages')
    .where('senderID', '==', uid)
    .get();
  await Promise.all(snapshot.docs.map((doc) => doc.ref.delete()));
  console.log(`Deleted ${snapshot.size} message(s) by ${uid}`);
}

/**
 * Usage events attributed to the user.
 *
 * Reports are deliberately NOT purged: a report is a safety record about somebody else's
 * conduct, and deleting your account should not erase what you reported.
 */
async function purgeEvents(uid) {
  const snapshot = await db().collection('events').where('userID', '==', uid).get();
  const batches = [];
  for (let i = 0; i < snapshot.docs.length; i += 450) {
    const batch = db().batch();
    snapshot.docs.slice(i, i + 450).forEach((doc) => batch.delete(doc.ref));
    batches.push(batch.commit());
  }
  await Promise.all(batches);
}

/** Invite codes the user owns are meaningless once they're gone. */
async function purgeInvites(uid) {
  const snapshot = await db().collection('invites').where('ownerID', '==', uid).get();
  await Promise.all(snapshot.docs.map((doc) => doc.ref.delete()));
}

/**
 * Removes the user from every relationship they belong to. A relationship with nobody
 * left in it is deleted outright; otherwise the remaining partner keeps theirs.
 */
async function purgeRelationships(uid) {
  const snapshot = await db()
    .collection('relationships')
    .where('participantIDs', 'array-contains', uid)
    .get();

  await Promise.all(
    snapshot.docs.map(async (doc) => {
      const remaining = (doc.data().participantIDs || []).filter((id) => id !== uid);
      if (remaining.length === 0) {
        await doc.ref.delete();
      } else {
        await doc.ref.update({ participantIDs: remaining });
      }
    })
  );
}

/**
 * Deletes requests that only involved this user, and scrubs them from shared ones so the
 * remaining participant keeps their history without a dangling reference.
 */
async function purgeRequests(uid) {
  const snapshot = await db()
    .collection('requests')
    .where('allParticipantIDs', 'array-contains', uid)
    .get();

  await Promise.all(
    snapshot.docs.map(async (doc) => {
      const data = doc.data();
      const remaining = (data.allParticipantIDs || []).filter((id) => id !== uid);
      if (remaining.length === 0) {
        await doc.ref.delete();
      } else {
        await doc.ref.update({
          allParticipantIDs: remaining,
          recipientIDs: (data.recipientIDs || []).filter((id) => id !== uid),
        });
      }
    })
  );
}

module.exports = { purgeUserData };
