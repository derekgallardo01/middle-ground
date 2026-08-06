/**
 * Cloud Functions for Middle Ground.
 *
 * MIXED GENERATIONS, ON PURPOSE. Everything here is 2nd-gen except `onUserDeleted`, which
 * cannot be: there is no 2nd-gen auth-delete trigger. The 2nd-gen identity hooks are
 * `beforeUserCreated` and `beforeUserSignedIn`, and neither fires on deletion. Since that
 * function is the durable backstop for the account-deletion cascade (App Store Guideline
 * 5.1.1(v)), it stays on 1st-gen via the `firebase-functions/v1` subpath, which is a stable
 * long-standing export rather than a compatibility shim.
 *
 * The 2nd-gen handler shape differs from 1st-gen in ways the compiler cannot catch:
 *   v1  (snap, context)   -> snap.data(),          context.params.x
 *   v2  (event)           -> event.data.data(),    event.params.x
 *   v1  (change, context) -> change.before.data(), change.after.data()
 *   v2  (event)           -> event.data.before.data(), event.data.after.data()
 * `event.data` is undefined on delete events, so every handler guards it.
 */

const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldPath } = require('firebase-admin/firestore');
const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } =
  require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
// 1st-gen, for the auth trigger only. See the note above.
const functionsV1 = require('firebase-functions/v1');

const { getUserName, notifyUsers, getUserTimeZone, DEFAULT_TIME_ZONE, NotificationType } =
  require('./push');
const { formatPlanTime } = require('./time');
const { pagedDocs, mapWithConcurrency } = require('./paging');
const { discover } = require('./discovery');
const { purgeUserData } = require('./purge');
const { sendAlert, when } = require('./alerts');

initializeApp();
const db = () => getFirestore();

const RESEND_API_KEY = defineSecret('RESEND_API_KEY');
const YELP_API_KEY = defineSecret('YELP_API_KEY');
const TICKETMASTER_API_KEY = defineSecret('TICKETMASTER_API_KEY');

const HOUR = 60 * 60 * 1000;

/**
 * Mirrors `CancellationReason.displayName` in Swift.
 *
 * Duplicated rather than shared because there is no code path between the app and the functions;
 * an unknown value falls back rather than showing a raw enum case, so an added reason reads badly
 * for one deploy instead of shipping "somethingCameUp" to someone's lock screen.
 */
const CANCELLATION_REASONS = {
  somethingCameUp: 'Something came up',
  unwell: 'Not feeling well',
  plansChanged: 'Our plans changed',
  runningLate: 'Running too late',
  noLongerNeeded: 'No longer needed',
};

/**
 * Options for every function that sends mail.
 *
 * The document path goes INSIDE the options object. The v2 trigger builders take
 * `(document, handler)` or `(opts, handler)` — never `(document, opts, handler)`. Passing all
 * three means the options object is invoked as the handler and every event dies at runtime
 * with "TypeError: func is not a function"; nothing catches it at deploy time.
 */
const alerting = (document) => ({ document, secrets: [RESEND_API_KEY] });

// ---------------------------------------------------------------- push

/** Notifies the recipients when a request is created. */
exports.notifyNewRequest = onDocumentCreated('requests/{requestId}', async (event) => {
  const request = event.data?.data();
  if (!request?.recipientIDs?.length) return null;

  const senderName = await getUserName(request.creatorID);

  return notifyUsers(request.recipientIDs, {
    notification: {
      title: `New request from ${senderName}`,
      body: request.title,
    },
    data: {
      request_id: event.params.requestId,
      type: 'new_request',
    },
  }, NotificationType.newRequest);
});

/**
 * Notifies everyone except the sender when someone says something on a plan.
 *
 * Conversation moved out of `negotiationChain` and into a subcollection, because a document
 * that rewrites itself on every message cannot carry a conversation. `notifyRequestResponse`
 * watches the chain, so without this function messages would arrive silently -- the feature
 * would look like it worked and simply never notify anybody.
 *
 * Its own notification type, so "somebody answered your plan" and "somebody said something
 * about it" can be turned off independently. A remark is far more frequent than a decision, and
 * bundling them would make people mute both to escape one.
 */
exports.notifyPlanMessage = onDocumentCreated(
  'requests/{requestId}/messages/{messageId}',
  async (event) => {
    const message = event.data?.data();
    if (!message) return null;

    const plan = await db()
      .collection('requests')
      .doc(event.params.requestId)
      .get();
    if (!plan.exists) return null;

    const senderName = await getUserName(message.senderID);
    const notifyUserIds = (plan.data().allParticipantIDs || []).filter(
      (id) => id !== message.senderID
    );

    return notifyUsers(notifyUserIds, {
      notification: {
        title: `${senderName} on ${plan.data().title || 'your plan'}`,
        body: message.text,
      },
      data: {
        request_id: event.params.requestId,
        type: 'plan_message',
      },
    }, NotificationType.message);
  }
);

/** Notifies everyone except the responder when a request gains a response. */
exports.notifyRequestResponse = onDocumentUpdated('requests/{requestId}', async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!before || !after) return null;

  const beforeCount = (before.negotiationChain || []).length;
  const afterCount = (after.negotiationChain || []).length;
  if (afterCount <= beforeCount) return null;

  const latestMessage = after.negotiationChain[afterCount - 1];
  const responderName = await getUserName(latestMessage.senderID);

  const notifyUserIds = (after.allParticipantIDs || []).filter(
    (id) => id !== latestMessage.senderID
  );

  // Per recipient, because a suggested time has to read on their clock. `text` for a reschedule
  // was written by the sender's device, so shipping it verbatim named the sender's hour to
  // everybody — the same fault the reminder had. The message now carries the instant; when it
  // does, it is re-rendered per person, and anything somebody actually typed is left alone.
  return Promise.all(
    notifyUserIds.map(async (userId) => {
      let body = latestMessage.text || latestMessage.responseType;
      if (latestMessage.responseType === 'reschedule' && latestMessage.proposedTime) {
        const zone = await getUserTimeZone(userId);
        const when = formatPlanTime(latestMessage.proposedTime, new Date(), zone);
        if (when) body = `How about ${when}?`;
      }

      return notifyUsers([userId], {
        notification: {
          title: `${responderName} responded`,
          body,
        },
        data: {
          request_id: event.params.requestId,
          type: 'request_response',
        },
      }, NotificationType.response);
    })
  );
});

/**
 * Tells everyone else when a plan is called off.
 *
 * Cancelling does not append to the negotiation chain — it sets the status and a reason — so
 * `notifyRequestResponse` above never sees it. Without this the plan simply disappears from the
 * other person's list with no explanation, which is the worst possible way to learn that dinner
 * is off. Only the creator may cancel, so everybody else is told.
 */
exports.notifyPlanCancelled = onDocumentUpdated('requests/{requestId}', async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!before || !after) return null;
  if (before.status === 'cancelled' || after.status !== 'cancelled') return null;

  const cancellerName = await getUserName(after.creatorID);
  const others = (after.allParticipantIDs || []).filter((id) => id !== after.creatorID);
  if (others.length === 0) return null;

  // Short notice is the part people actually mind, and it is the part a bare "cancelled"
  // hides. Mirrors `Request.wasCancelledLate` and the same 24-hour window the reliability
  // score uses, so the notification cannot say something the score disagrees with.
  const dueIn = after.proposedTime ? toMillis(after.proposedTime) - Date.now() : null;
  const atShortNotice = dueIn !== null && dueIn < 24 * HOUR;
  const reason = CANCELLATION_REASONS[after.cancellationReason] || 'No reason given.';

  return notifyUsers(others, {
    notification: {
      title: atShortNotice
        ? `${cancellerName} called off "${after.title}"`
        : `${cancellerName} cancelled "${after.title}"`,
      body: atShortNotice ? `${reason} — at short notice.` : reason,
    },
    data: {
      request_id: event.params.requestId,
      type: 'plan_cancelled',
    },
  }, NotificationType.planCancelled);
});

/**
 * Asks whether a plan actually happened, a few hours after it was due.
 *
 * Attendance is the input the reliability score, stakes and every missed-plan idea are computed
 * from, and until now nothing asked for it: an accepted plan simply stopped changing and the app
 * waited for someone to open it and notice the prompt.
 *
 * The window is what keeps this exactly-once without storing a "we asked" flag on the request.
 * The hour is floored first, so the boundaries do not drift with the few seconds a scheduled run
 * takes to start, and each plan therefore falls inside exactly one hourly window — no repeats,
 * no gaps. A flag would have been more robust to a missed run, but the client rewrites the whole
 * request document when it responds, which would silently drop a field the Swift model does not
 * know about and re-ask every hour.
 *
 * Four hours of grace, because the stored time is when a plan *starts*. Asking whether dinner
 * happened while people are still at dinner would train them to ignore the question.
 */
/**
 * Deletes usage events older than ninety days.
 *
 * Belt to the TTL policy's braces, and not redundant. Firestore expires a document by reading a
 * timestamp field on it, so a document written *without* that field is never collected — and every
 * build shipped before `expiresAt` existed writes exactly such documents. Those would live forever
 * while the privacy policy promises ninety days.
 *
 * The TTL is still what does the work for current builds; this catches what it cannot see, and
 * costs one query a week against a collection that should nearly always be empty of matches.
 *
 * Deliberately keyed on `at`, not `expiresAt`: the whole point is the rows that have no
 * `expiresAt`, and a `where` on a missing field matches nothing.
 */
const EVENT_RETENTION_DAYS = 90;

exports.purgeStaleEvents = onSchedule(
  { schedule: '0 4 * * 0', timeZone: 'America/New_York' },
  async () => {
    const cutoff = new Date(Date.now() - EVENT_RETENTION_DAYS * 24 * HOUR);
    const snapshot = await db()
      .collection('events')
      .where('at', '<', cutoff)
      .limit(500)
      .get();

    if (snapshot.empty) return;

    // Batched, and capped at 500 a run: this is a safety net for documents the TTL cannot reach,
    // not a bulk deletion tool. If it ever finds a full batch every week, something is writing
    // events without an expiry and that is the thing to fix.
    const batch = db().batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    console.log(`Purged ${snapshot.size} event(s) older than ${EVENT_RETENTION_DAYS} days`);
  }
);

const CONFIRM_AFTER_HOURS = 4;

exports.promptForAttendance = onSchedule(
  { schedule: '0 * * * *', timeZone: 'America/New_York' },
  async () => {
    const hourStart = new Date(Math.floor(Date.now() / HOUR) * HOUR);
    const until = new Date(hourStart.getTime() - CONFIRM_AFTER_HOURS * HOUR);
    const since = new Date(until.getTime() - HOUR);

    const snapshot = await db()
      .collection('requests')
      .where('status', '==', 'accepted')
      .where('proposedTime', '>=', since)
      .where('proposedTime', '<', until)
      .get();

    if (snapshot.empty) return;
    console.log(`Asking about ${snapshot.size} plan(s) that were due between ${since} and ${until}`);

    await Promise.all(
      snapshot.docs.map(async (doc) => {
        const request = doc.data();
        const confirmations = request.confirmations || {};
        const unanswered = (request.allParticipantIDs || []).filter((id) => !confirmations[id]);
        if (unanswered.length === 0) return;

        await notifyUsers(unanswered, {
          notification: {
            title: 'Did it happen?',
            body: `Let us know how "${request.title}" went.`,
          },
          data: {
            request_id: doc.id,
            type: 'confirm_plan',
          },
        }, NotificationType.confirmPlan);
      })
    );
  }
);

// -------------------------------------------------------- the evening before

/**
 * Reminds everyone on an agreed plan, the evening before it happens.
 *
 * Nothing used to occupy the gap between somebody accepting a plan and the plan itself.
 * `promptForAttendance` arrives four hours *after*, and `weeklyNudge` deliberately skips anyone
 * with something coming up — so the interval in which a plan quietly dies was the one interval
 * with nothing in it. Plans falling through is the number the product is judged on.
 *
 * Sixteen hours ahead, floored to the hour, which puts an evening plan into the previous evening
 * and a morning plan into the night before. Close enough to be about tomorrow; far enough that
 * calling it off is still a courtesy rather than an ambush.
 *
 * The same windowing trick as `promptForAttendance` and for the same reason: an exactly-one-hour
 * band walked forward each run, rather than a flag on the request. A flag would be dropped the
 * next time the client wrote the document back, because the Swift model does not know about it.
 *
 * This is not a nag. It asks whether anything has changed, and the honest answer is often "no" —
 * which is why it says nothing further and never asks twice.
 */
const REMIND_BEFORE_HOURS = 16;

exports.remindBeforePlan = onSchedule(
  { schedule: '0 * * * *', timeZone: 'America/New_York' },
  async () => {
    const hourStart = new Date(Math.floor(Date.now() / HOUR) * HOUR);
    const since = new Date(hourStart.getTime() + REMIND_BEFORE_HOURS * HOUR);
    const until = new Date(since.getTime() + HOUR);

    const snapshot = await db()
      .collection('requests')
      .where('status', '==', 'accepted')
      .where('proposedTime', '>=', since)
      .where('proposedTime', '<', until)
      .get();

    if (snapshot.empty) return;
    console.log(`Reminding about ${snapshot.size} plan(s) due between ${since} and ${until}`);

    await Promise.all(
      snapshot.docs.map(async (doc) => {
        const request = doc.data();
        const everyone = request.allParticipantIDs || [];
        if (everyone.length === 0) return;

        // One at a time, because the body differs per person.
        //
        // A plan is a single instant; what people read off a clock is not. Sending everyone the
        // same string meant formatting in New York for all of them, so somebody in Los Angeles
        // was told "tomorrow at 1:00 AM" about the dinner their own screen showed as 10pm the
        // same evening. Whose clock it is has to be part of the message.
        await Promise.all(
          everyone.map(async (userId) => {
            const zone = await getUserTimeZone(userId);
            const when = formatPlanTime(request.proposedTime, new Date(), zone);

            await notifyUsers([userId], {
              notification: {
                title: 'Still on?',
                body: when
                  ? `"${request.title}" is ${when}.`
                  : `"${request.title}" is coming up.`,
              },
              data: {
                request_id: doc.id,
                type: 'plan_reminder',
              },
            }, NotificationType.planReminder);
          })
        );
      })
    );
  }
);


// -------------------------------------------------------- weekly nudge

/**
 * Once a week, tells one person about one group that has nothing planned.
 *
 * Thursday morning on purpose: the weekend is close enough to act on and far enough away that
 * something can still be arranged. A Sunday reminder arrives after the window it is about.
 *
 * The hard constraint is one push, however many groups qualify. Three defensible notifications
 * on the same morning still read as spam, and the cost of that is not the three — it is the
 * notification permission being switched off entirely, taking the cancellation and did-it-happen
 * pushes with it. So the quietest group is picked and the rest wait for next week.
 *
 * Silent when there is nothing to say. A nudge that arrives while you have three plans booked is
 * the fastest way to teach someone this app does not know what it is talking about.
 */
const NUDGE_HISTORY_LIMIT = 50;
const NUDGE_PAGE_SIZE = 200;
/**
 * How many users are evaluated at once.
 *
 * Each one costs a Firestore query and possibly a name lookup and a send, and `Promise.all` over
 * every user in the database started all of them simultaneously. At a few users that is invisible;
 * it is also precisely the kind of thing that stops being invisible without warning, because the
 * failure is a burst rather than a slow climb.
 */
const NUDGE_CONCURRENCY = 20;

exports.weeklyNudge = onSchedule(
  { schedule: '0 10 * * 4', timeZone: 'America/New_York' },
  async () => {
    // Still reads every user and every relationship — that is inherent to "nudge whoever is
    // quiet", and the shape that removes it is a per-user task queue. What has changed is that
    // nothing is now unbounded *within* the run: documents arrive a page at a time and the
    // per-user work runs a fixed number at a time, so the run gets slower as the database grows
    // rather than falling over at some unknown size.
    const groupsByUser = new Map();
    for await (const docs of pagedDocs(db, FieldPath, 'relationships', NUDGE_PAGE_SIZE)) {
      docs.forEach((doc) => {
        const group = doc.data();
        const members = group.participantIDs || [];
        // Was `!== 2`, which silently exempted every group of three or more from the one
        // message aimed at quiet groups — while the setting that turns it on says "a group".
        if (members.length < 2) return; // Unpaired: there is nobody to plan with yet.
        members.forEach((id) => {
          if (!groupsByUser.has(id)) groupsByUser.set(id, []);
          groupsByUser.get(id).push({ id: doc.id, ...group });
        });
      });
    }

    let considered = 0;
    let nudged = 0;
    for await (const docs of pagedDocs(db, FieldPath, 'users', NUDGE_PAGE_SIZE)) {
      considered += docs.length;
      const results = await mapWithConcurrency(docs, NUDGE_CONCURRENCY, (doc) =>
        nudgeIfQuiet(doc.id, groupsByUser.get(doc.id) || []),
      );
      nudged += results.filter(Boolean).length;
    }
    console.log(`Nudged ${nudged} of ${considered} user(s)`);
  }
);

async function nudgeIfQuiet(userId, groups) {
  if (groups.length === 0) return false;

  // Undated requests are deliberately invisible here: ordering by `proposedTime` drops documents
  // that lack the field, and "split the grocery run" is a task rather than a plan. Nudging
  // someone to make plans because their only shared item is a chore would be wrong twice.
  const snapshot = await db()
    .collection('requests')
    .where('allParticipantIDs', 'array-contains', userId)
    .orderBy('proposedTime', 'desc')
    .limit(NUDGE_HISTORY_LIMIT)
    .get();

  const now = Date.now();
  const plans = snapshot.docs
    .map((doc) => doc.data())
    .filter((request) => request.status !== 'cancelled' && request.status !== 'declined');

  const quiet = groups
    .map((group) => {
      const others = group.participantIDs.filter((id) => id !== userId);
      // Anyone else in the group counts. Testing one nominated partner was fine while a group
      // was a pair and would have called a busy group of four quiet.
      const shared = plans.filter((plan) => {
        const participants = plan.allParticipantIDs || [];
        return others.some((id) => participants.includes(id));
      });
      const upcoming = shared.some((plan) => toMillis(plan.proposedTime) > now);
      if (upcoming) return null;

      // No plan ever means measuring from when the group was created, so a pair who have never
      // used it are not silently exempt from the one message aimed squarely at them.
      const last = shared[0] ? toMillis(shared[0].proposedTime) : toMillis(group.createdAt);
      return { group, others, since: last, ever: shared.length > 0 };
    })
    .filter(Boolean)
    .sort((a, b) => a.since - b.since);

  if (quiet.length === 0) return false;

  const quietest = quiet[0];
  // A named group says its own name. A pair has no name, so it borrows the other person's.
  let who = quietest.group.name;
  if (!who) {
    who = quietest.others.length === 1
      ? `you and ${await getUserName(quietest.others[0])}`
      : 'your group';
  }
  const gap = describeGap(now - quietest.since);

  await notifyUsers([userId], {
    notification: {
      title: 'Plan something?',
      body: quietest.ever
        ? `Nothing on the calendar for ${who} in ${gap}.`
        : `${capitalise(who)} haven't planned anything yet.`,
    },
    data: { relationship_id: quietest.group.id, type: 'weekly_nudge' },
  }, NotificationType.weeklyNudge);
  return true;
}

/** Firestore hands back a Timestamp; a seeded or hand-written document might not. */
function toMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === 'function') return value.toMillis();
  return new Date(value).getTime();
}

/** Rounded to the unit somebody would actually use out loud. */
function describeGap(milliseconds) {
  const days = Math.floor(milliseconds / (24 * HOUR));
  if (days >= 60) return `${Math.floor(days / 30)} months`;
  if (days >= 30) return 'a month';
  if (days >= 14) return `${Math.floor(days / 7)} weeks`;
  if (days >= 7) return 'a week';
  return `${days} days`;
}

const capitalise = (text) => text.charAt(0).toUpperCase() + text.slice(1);

// ------------------------------------------------------ operator alerts
//
// Watching Firestore documents rather than auth events, deliberately: the auth triggers are
// 1st-gen only, and the app writes users/{uid} on sign-up and deletes it on account deletion,
// so these carry the same signal while staying 2nd-gen.

exports.alertOnSignup = onDocumentCreated(alerting('users/{uid}'), async (event) => {
  const user = event.data?.data();
  if (!user) return null;

  await sendAlert(`New signup: ${user.name || 'unnamed'}`, [
    `Name: ${user.name || '(none)'}`,
    `UID:  ${event.params.uid}`,
    `At:   ${when(new Date())}`,
    '',
    'They have not paired with anyone yet — the app is empty for them until they do.',
  ]);
  return null;
});

exports.alertOnPairing = onDocumentUpdated(alerting('relationships/{id}'), async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!before || !after) return null;

  // Only the 1 -> 2 transition is a pairing. Any other participant change (someone leaving,
  // a code rotation) is not, and alerting on those would make this noisy and untrustworthy.
  const had = (before.participantIDs || []).length;
  const has = (after.participantIDs || []).length;
  if (!(had === 1 && has === 2)) return null;

  const names = await Promise.all((after.participantIDs || []).map(getUserName));

  await sendAlert(`Paired: ${names.join(' + ')}`, [
    `Group:  ${event.params.id} (${after.type || 'unknown type'})`,
    `Members: ${names.join(', ')}`,
    `UIDs:    ${(after.participantIDs || []).join(', ')}`,
    '',
    'Both can now send each other requests. This is the activation moment.',
  ]);
  return null;
});

/** Abuse reports are the one alert that should interrupt you. */
exports.alertOnReport = onDocumentCreated(alerting('reports/{id}'), async (event) => {
  const report = event.data?.data();
  if (!report) return null;

  const [reporter, reported] = await Promise.all([
    getUserName(report.reporterID),
    getUserName(report.reportedUserID),
  ]);

  await sendAlert(`⚠️ Content reported — ${report.reason}`, [
    `Reason:   ${report.reason}`,
    `Reported: ${reported} (${report.reportedUserID})`,
    `By:       ${reporter} (${report.reporterID})`,
    `Request:  ${report.requestID}`,
    `Note:     ${report.note || '(none)'}`,
    `At:       ${when(report.at)}`,
    '',
    'The published policy commits to reviewing reports within 24 hours.',
    'Open the Admin tab > Reports to see the content.',
  ]);
  return null;
});

exports.alertOnAccountDeleted = onDocumentDeleted(alerting('users/{uid}'), async (event) => {
  await sendAlert('Account deleted', [
    `UID: ${event.params.uid}`,
    `At:  ${when(new Date())}`,
    '',
    'Their data is purged by AccountDataPurger on the client and by onUserDeleted here.',
  ]);
  return null;
});

// -------------------------------------------------------- daily digest

/**
 * A once-a-day summary, so the numbers are visible without opening the app.
 *
 * Request and response volume is deliberately reported here rather than emailed per event:
 * it is the one event class that scales with usage, and per-event mail would train you to
 * ignore the inbox that also carries abuse reports.
 */
exports.dailyDigest = onSchedule(
  { schedule: '0 9 * * *', timeZone: 'America/New_York', secrets: [RESEND_API_KEY] },
  async () => {
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000);

    const countEvents = async (type) => {
      try {
        const snap = await db()
          .collection('events')
          .where('type', '==', type)
          .where('at', '>', since)
          .count()
          .get();
        return snap.data().count;
      } catch (error) {
        console.error(`digest: could not count ${type}:`, error);
        return '?';
      }
    };

    const totalUsers = async () => {
      try {
        return (await db().collection('users').count().get()).data().count;
      } catch {
        return '?';
      }
    };

    const [signups, onboarded, groups, redeemed, created, responded, left, reported, users] =
      await Promise.all([
        countEvents('signed_up'),
        countEvents('onboarding_completed'),
        countEvents('relationship_created'),
        countEvents('invite_redeemed'),
        countEvents('request_created'),
        countEvents('request_responded'),
        countEvents('relationship_left'),
        countEvents('content_reported'),
        totalUsers(),
      ]);

    await sendAlert('Daily digest', [
      'Last 24 hours',
      '',
      `  signed up            ${signups}`,
      `  finished onboarding  ${onboarded}`,
      `  created a group      ${groups}`,
      `  redeemed an invite   ${redeemed}   <- pairing`,
      `  requests created     ${created}`,
      `  requests answered    ${responded}`,
      `  left a group         ${left}`,
      `  content reported     ${reported}`,
      '',
      `Total users: ${users}`,
    ]);
  }
);

// ------------------------------------------------------------- 1st gen
//
// This one CANNOT be 2nd-gen — see the file header. Leave it on v1.

exports.onUserDeleted = functionsV1.auth.user().onDelete(async (user) => {
  await purgeUserData(user.uid);
});

// ---------------------------------------------------------- place discovery

/**
 * Nearby places and events, for the moment before a plan exists.
 *
 * The project's first callable function — everything else here is a trigger or a schedule. It is
 * callable rather than an HTTP endpoint because callable functions carry the caller's identity,
 * which is what the rate limit counts and what stops this being an open proxy to a metered API.
 *
 * The keys stay here. A key shipped in an iOS binary is a key anybody can extract, and the whole
 * reason this function exists rather than the app calling Yelp directly.
 *
 * Errors are deliberately vague to the client and specific in the log: "Yelp 429" tells an
 * attacker which quota to exhaust, and tells the person searching nothing they can act on.
 */
exports.discoverPlaces = onCall(
  { secrets: [YELP_API_KEY, TICKETMASTER_API_KEY], enforceAppCheck: false },
  async (event) => {
    const uid = event.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Sign in to search for places.');
    }

    try {
      return await discover(event.data || {}, uid, {
        yelp: YELP_API_KEY.value(),
        ticketmaster: TICKETMASTER_API_KEY.value(),
      });
    } catch (error) {
      console.error(`discoverPlaces failed for ${uid}:`, error);
      if (/Too many searches/.test(error.message)) {
        throw new HttpsError('resource-exhausted', error.message);
      }
      if (/latitude and longitude/.test(error.message)) {
        throw new HttpsError('invalid-argument', error.message);
      }
      throw new HttpsError('unavailable', "Couldn't search for places just now.");
    }
  }
);
