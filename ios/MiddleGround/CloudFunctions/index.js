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

    const tokens = [];
    for (const userId of request.recipientIDs) {
      const userTokens = await getUserTokens(userId);
      tokens.push(...userTokens);
    }

    if (tokens.length === 0) {
      return null;
    }

    const payload = {
      notification: {
        title: `New request from ${senderName}`,
        body: request.title,
      },
      data: {
        request_id: requestId,
        type: 'new_request',
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    return sendToTokens(tokens, payload);
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
    const notifyUserIds = after.allParticipantIDs || [];
    const tokens = [];

    for (const userId of notifyUserIds) {
      if (userId === latestMessage.senderID) continue;
      const userTokens = await getUserTokens(userId);
      tokens.push(...userTokens);
    }

    if (tokens.length === 0) {
      return null;
    }

    const payload = {
      notification: {
        title: `${responderName} responded`,
        body: latestMessage.text || latestMessage.responseType,
      },
      data: {
        request_id: requestId,
        type: 'request_response',
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    return sendToTokens(tokens, payload);
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

async function sendToTokens(tokens, payload) {
  const response = await messaging.sendEachForMulticast({ tokens, ...payload });
  console.log(`Sent ${response.successCount} messages successfully`);

  if (response.failureCount > 0) {
    response.responses.forEach((resp, idx) => {
      if (!resp.success) {
        console.error(`Failed to send to ${tokens[idx]}:`, resp.error);
      }
    });
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
    purgeInvites(uid),
    purgeRelationships(uid),
    purgeRequests(uid),
  ]);

  results.forEach((r, i) => {
    if (r.status === 'rejected') {
      console.error(`Purge step ${i} failed for ${uid}:`, r.reason);
    }
  });

  console.log(`Finished purging ${uid}`);
});

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
