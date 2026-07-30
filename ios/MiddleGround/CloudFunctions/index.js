const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

/**
 * Sends a push notification when a new request is created.
 * Triggered on document create in the `requests` collection.
 */
exports.notifyNewRequest = functions.firestore
  .document('requests/{requestId}')
  .onCreate(async (snap, context) => {
    const request = snap.data();
    const requestId = context.params.requestId;

    if (!request || !request.recipientIDs || request.recipientIDs.length === 0) {
      return null;
    }

    const senderName = await getUserName(request.creatorID);

    return notifyUsers(request.recipientIDs, {
      notification: {
        title: `New request from ${senderName}`,
        body: request.title,
      },
      data: {
        request_id: requestId,
        type: 'new_request',
      },
    });
  });

/**
 * Sends a push notification when a request receives a response.
 * Triggered on document update in the `requests` collection.
 */
exports.notifyRequestResponse = functions.firestore
  .document('requests/{requestId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const requestId = context.params.requestId;

    const beforeCount = (before.negotiationChain || []).length;
    const afterCount = (after.negotiationChain || []).length;

    if (afterCount <= beforeCount) {
      return null;
    }

    const latestMessage = after.negotiationChain[afterCount - 1];
    const responderName = await getUserName(latestMessage.senderID);

    // Notify everyone except the responder
    const notifyUserIds = (after.allParticipantIDs || []).filter(
      (id) => id !== latestMessage.senderID
    );

    return notifyUsers(notifyUserIds, {
      notification: {
        title: `${responderName} responded`,
        body: latestMessage.text || latestMessage.responseType,
      },
      data: {
        request_id: requestId,
        type: 'request_response',
      },
    });
  });

async function getUserName(userId) {
  try {
    const userDoc = await db.collection('users').doc(userId).get();
    return userDoc.exists ? userDoc.data().name || 'Someone' : 'Someone';
  } catch (error) {
    console.error('Error fetching user name:', error);
    return 'Someone';
  }
}

async function getUserTokens(userId) {
  try {
    const tokensDoc = await db.collection('user_tokens').doc(userId).get();
    if (!tokensDoc.exists) return [];
    const data = tokensDoc.data();
    return data.tokens || [];
  } catch (error) {
    console.error('Error fetching user tokens:', error);
    return [];
  }
}

/**
 * How many requests are waiting on this user right now.
 *
 * The badge used to be a hardcoded `1`, and nothing in the app ever cleared it — so after
 * the first push the icon carried a permanent 1 forever. Sending the real count means the
 * number is meaningful, and the app resets it to this same value on foreground.
 */
async function pendingCountFor(userId) {
  try {
    const snapshot = await db
      .collection('requests')
      .where('recipientIDs', 'array-contains', userId)
      .where('status', '==', 'pending')
      .count()
      .get();
    return snapshot.data().count;
  } catch (error) {
    console.error(`Could not count pending for ${userId}:`, error);
    return 0;
  }
}

/**
 * Delivers to each user separately.
 *
 * This used to pool everyone's tokens into one multicast, which made a per-recipient badge
 * impossible and gave no way to attribute a failed token back to the user who owns it.
 */
async function notifyUsers(userIds, payload) {
  await Promise.all(userIds.map((userId) => notifyUser(userId, payload)));
  return null;
}

async function notifyUser(userId, payload) {
  const tokens = await getUserTokens(userId);
  if (tokens.length === 0) return;

  const badge = await pendingCountFor(userId);

  // sendEachForMulticast caps at 500 tokens per call.
  for (let i = 0; i < tokens.length; i += 500) {
    const slice = tokens.slice(i, i + 500);
    const response = await messaging.sendEachForMulticast({
      tokens: slice,
      ...payload,
      apns: { payload: { aps: { sound: 'default', badge } } },
    });

    console.log(`Sent ${response.successCount}/${slice.length} to ${userId}`);
    if (response.failureCount > 0) {
      await pruneDeadTokens(userId, slice, response.responses);
    }
  }
}

/**
 * Drops tokens APNs has told us are gone.
 *
 * `user_tokens/{uid}.tokens` is only ever appended to with arrayUnion — a new install, a
 * restore from backup, or a routine token rotation each add an entry and none is ever
 * removed. Left alone the array grows past the 500-token send limit and every delivery
 * wastes work on addresses that cannot receive.
 */
async function pruneDeadTokens(userId, tokens, responses) {
  const dead = [];
  responses.forEach((resp, idx) => {
    if (resp.success) return;
    const code = resp.error && resp.error.code;
    console.error(`Failed to send to ${tokens[idx]}:`, code);
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token' ||
      code === 'messaging/invalid-argument'
    ) {
      dead.push(tokens[idx]);
    }
  });

  if (dead.length === 0) return;
  try {
    await db
      .collection('user_tokens')
      .doc(userId)
      .update({ tokens: admin.firestore.FieldValue.arrayRemove(...dead) });
    console.log(`Pruned ${dead.length} dead token(s) for ${userId}`);
  } catch (error) {
    console.error(`Could not prune tokens for ${userId}:`, error);
  }
}

/**
 * Purges a user's data when their auth account is deleted.
 *
 * App Store Guideline 5.1.1(v) requires in-app account deletion, and deleting the auth
 * record is not enough on its own — the Firestore documents must go too. This runs with
 * admin privileges so it can perform the multi-document cascade that security rules
 * deliberately forbid the client from doing.
 */
exports.onUserDeleted = functions.auth.user().onDelete(async (user) => {
  const uid = user.uid;
  console.log(`Purging data for deleted user ${uid}`);

  const results = await Promise.allSettled([
    db.collection('users').doc(uid).delete(),
    db.collection('user_tokens').doc(uid).delete(),
    db.collection('gamification').doc(uid).delete(),
    purgeInvites(uid),
    purgeRelationships(uid),
    purgeRequests(uid),
    purgeEvents(uid),
  ]);

  results.forEach((r, i) => {
    if (r.status === 'rejected') {
      console.error(`Purge step ${i} failed for ${uid}:`, r.reason);
    }
  });

  console.log(`Finished purging ${uid}`);
});

/**
 * Usage events attributed to the user.
 *
 * The client purges these too (AccountDataPurger), but only what it managed to reach before
 * the process ended. Reports are deliberately NOT purged: a report is a safety record about
 * somebody else's conduct, and deleting your account should not erase what you reported.
 */
async function purgeEvents(uid) {
  const snapshot = await db.collection('events').where('userID', '==', uid).get();
  const batches = [];
  for (let i = 0; i < snapshot.docs.length; i += 450) {
    const batch = db.batch();
    snapshot.docs.slice(i, i + 450).forEach((doc) => batch.delete(doc.ref));
    batches.push(batch.commit());
  }
  await Promise.all(batches);
}

/** Invite codes the user owns are meaningless once they're gone. */
async function purgeInvites(uid) {
  const snapshot = await db.collection('invites').where('ownerID', '==', uid).get();
  await Promise.all(snapshot.docs.map((doc) => doc.ref.delete()));
}

/**
 * Removes the user from every relationship they belong to. A relationship with nobody
 * left in it is deleted outright; otherwise the remaining partner keeps theirs.
 */
async function purgeRelationships(uid) {
  const snapshot = await db
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
  const snapshot = await db
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
