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
 * Which clock this person reads, written by the client alongside their FCM token.
 *
 * Falls back to Eastern, which is right for the stated market and was the only behaviour before
 * this existed. Anybody on a build that predates it, or who has never granted notifications, has
 * no value here — and for them the fallback is exactly what they were already getting.
 */
async function getUserTimeZone(userId) {
  try {
    const doc = await db().collection('user_tokens').doc(userId).get();
    return doc.exists ? doc.data().timeZone || DEFAULT_TIME_ZONE : DEFAULT_TIME_ZONE;
  } catch (error) {
    console.error('Error fetching user time zone:', error);
    return DEFAULT_TIME_ZONE;
  }
}

/** Miami, and the fallback for anybody whose zone is unknown. */
const DEFAULT_TIME_ZONE = 'America/New_York';

// A request nobody has settled: someone still owes an answer on it.
const OPEN_STATUSES = ['pending', 'negotiated', 'rescheduled', 'countered', 'saved'];

/**
 * Whether this user is the one who owes a reply.
 *
 * Mirrors `Request.awaitingResponseFrom` in Swift and `isMyTurn()` in firestore.rules: before
 * anyone replies the recipients owe the answer; after that it belongs to whoever did not send
 * the last message. A save is a bookmark rather than an answer, so it leaves the turn put.
 */
function isAwaitingReplyFrom(request, userId) {
  const chain = request.negotiationChain || [];
  const answers = chain.filter((message) => message.responseType !== 'save');
  if (answers.length === 0) return (request.recipientIDs || []).includes(userId);
  return answers[answers.length - 1].senderID !== userId;
}

/**
 * How many requests are waiting on this user right now.
 *
 * The badge used to be a hardcoded `1`, and nothing in the app ever cleared it — so after
 * the first push the icon carried a permanent 1 forever. Sending the real count means the
 * number is meaningful, and the app resets it to this same value on foreground.
 *
 * Counting `recipientIDs + status == 'pending'` was then wrong twice once turn-taking landed,
 * and wrong about exactly the requests that most need attention: a counter-offer sits at status
 * `countered`, and the turn after a counter usually belongs to the **creator**, who is not in
 * `recipientIDs` at all. So the badge stayed silent on every negotiation in flight. Membership
 * plus open status narrows it in the query; whose turn it is has to be computed, because it
 * depends on the last message in the chain.
 *
 * Bounded because this is the most frequently executed read in the system — it runs on every
 * push, once per recipient — and it was unbounded. The result is a badge number, and iOS clamps
 * what it shows long before this; nobody has 200 open plans, and if they somehow did, "200" on
 * the icon says everything "237" would. The cap costs nothing and turns an unbounded fan-out into
 * a fixed one.
 */
const MAX_BADGE_COUNT = 200;

async function pendingCountFor(userId) {
  try {
    const snapshot = await db()
      .collection('requests')
      .where('allParticipantIDs', 'array-contains', userId)
      .where('status', 'in', OPEN_STATUSES)
      .limit(MAX_BADGE_COUNT)
      .get();
    return snapshot.docs.filter((doc) => isAwaitingReplyFrom(doc.data(), userId)).length;
  } catch (error) {
    console.error(`Could not count pending for ${userId}:`, error);
    return 0;
  }
}

/**
 * What kinds of push exist, and therefore what can be switched off.
 *
 * Every send names one. Adding a type without adding it here is the mistake worth preventing:
 * an unnamed type would bypass preferences silently and there would be nothing to notice.
 */
const NotificationType = {
  newRequest: 'newRequest',
  response: 'response',
  confirmPlan: 'confirmPlan',
  planCancelled: 'planCancelled',
  weeklyNudge: 'weeklyNudge',
  planReminder: 'planReminder',
  message: 'message',
};

/**
 * Whether this person wants this kind of push.
 *
 * A missing document means yes, so everyone who predates preferences keeps the behaviour they
 * had and there is nothing to migrate. A failed read also means yes: losing a notification
 * because Firestore hiccupped is worse than sending one somebody had muted.
 */
async function wantsNotification(userId, type) {
  if (!type) return true;
  try {
    const doc = await db().collection('notification_settings').doc(userId).get();
    if (!doc.exists) return true;
    return doc.data()[type] !== false;
  } catch (error) {
    console.error(`Could not read notification settings for ${userId}:`, error);
    return true;
  }
}

/**
 * Sends to everyone who wants this kind of push, one user at a time.
 *
 * Delivery is per-user rather than one pooled multicast: pooling made a per-recipient badge
 * impossible and gave no way to attribute a failed token back to the user who owns it.
 *
 * The preference check lives here rather than at each call site, so there is one place to be
 * wrong instead of six — and a notification added later cannot forget to make it.
 */
async function notifyUsers(userIds, payload, type) {
  await Promise.all(userIds.map((userId) => notifyUser(userId, payload, type)));
  return null;
}

async function notifyUser(userId, payload, type) {
  if (!(await wantsNotification(userId, type))) {
    console.log(`Skipping ${type} for ${userId}: switched off`);
    return;
  }

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

module.exports = {
  getUserTimeZone,
  DEFAULT_TIME_ZONE, getUserName, notifyUsers, NotificationType };
