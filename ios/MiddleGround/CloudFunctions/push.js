// firebase-admin v14 REMOVED the namespaced accessors: `admin.firestore()` and
// `admin.messaging()` are both undefined, and calling them throws
// "TypeError: admin.firestore is not a function" at runtime — nothing catches it at deploy
// time, so the functions deploy green and then fail on every event.
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

const db = () => getFirestore();
const messaging = () => getMessaging();

async function getUserName(userId) {
  try {
    const userDoc = await db().collection('users').doc(userId).get();
    return userDoc.exists ? userDoc.data().name || 'Someone' : 'Someone';
  } catch (error) {
    console.error('Error fetching user name:', error);
    return 'Someone';
  }
}

async function getUserTokens(userId) {
  try {
    const tokensDoc = await db().collection('user_tokens').doc(userId).get();
    if (!tokensDoc.exists) return [];
    return tokensDoc.data().tokens || [];
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
    const snapshot = await db()
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
    const response = await messaging().sendEachForMulticast({
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
    await db()
      .collection('user_tokens')
      .doc(userId)
      .update({ tokens: FieldValue.arrayRemove(...dead) });
    console.log(`Pruned ${dead.length} dead token(s) for ${userId}`);
  } catch (error) {
    console.error(`Could not prune tokens for ${userId}:`, error);
  }
}

module.exports = { getUserName, notifyUsers };
