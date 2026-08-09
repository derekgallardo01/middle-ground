const test = require('node:test');
const assert = require('node:assert');

const { formatPlanTime, DEFAULT_TIME_ZONE } = require('../time');

/**
 * The test that would have caught it.
 *
 * `formatPlanTime` shipped naming America/New_York in all four of its formatters, and the check
 * run at the time passed three fixed instants and no zone — so it agreed with itself and proved
 * nothing. Every case below passes a zone.
 */
test('formatPlanTime', async (t) => {
  // An LA user's dinner at 22:00 PDT on Thursday 6 August. In New York that is 01:00 on Friday.
  const dinner = new Date('2026-08-07T05:00:00Z');
  // The reminder fires sixteen hours ahead: 06:00 PDT Thursday.
  const reminderTime = new Date('2026-08-06T13:00:00Z');

  await t.test('reads on the recipient clock, not the server one', () => {
    assert.equal(formatPlanTime(dinner, reminderTime, 'America/Los_Angeles'), 'tonight at 10:00 PM');
  });

  await t.test('and is still right for somebody in New York', () => {
    // Genuinely 1am Friday there — the same instant, a different clock.
    assert.equal(formatPlanTime(dinner, reminderTime, 'America/New_York'), 'tomorrow at 1:00 AM');
  });

  await t.test('falls back to Eastern when the zone is unknown', () => {
    // Anybody on a build predating the timezone field, which is what they already had.
    assert.equal(
      formatPlanTime(dinner, reminderTime),
      formatPlanTime(dinner, reminderTime, DEFAULT_TIME_ZONE)
    );
  });

  await t.test('the day word follows the reader too', () => {
    // The bug was not only the hour: the today/tomorrow bucket was computed in Eastern, so a
    // plan this evening was announced as tomorrow's.
    assert.match(formatPlanTime(dinner, reminderTime, 'America/Los_Angeles'), /^tonight/);
    assert.match(formatPlanTime(dinner, reminderTime, 'America/New_York'), /^tomorrow/);
  });

  await t.test('tonight and today split on the reader hour', () => {
    const afternoon = new Date('2026-08-06T21:00:00Z');   // 2pm Pacific, 5pm Eastern
    const morning = new Date('2026-08-06T15:00:00Z');
    assert.equal(formatPlanTime(afternoon, morning, 'America/Los_Angeles'), 'today at 2:00 PM');
    assert.equal(formatPlanTime(afternoon, morning, 'America/New_York'), 'tonight at 5:00 PM');
  });

  await t.test('further out names the weekday', () => {
    const saturday = new Date('2026-08-08T17:00:00Z');
    assert.equal(formatPlanTime(saturday, reminderTime, 'America/New_York'), 'Saturday at 1:00 PM');
  });

  await t.test('a plan with no time has nothing to say', () => {
    assert.equal(formatPlanTime(null, reminderTime, 'America/New_York'), null);
    assert.equal(formatPlanTime(undefined, reminderTime), null);
  });

  await t.test('accepts a Firestore Timestamp, which is what a document read gives', () => {
    const stamp = { toMillis: () => dinner.getTime() };
    assert.equal(formatPlanTime(stamp, reminderTime, 'America/Los_Angeles'), 'tonight at 10:00 PM');
  });

  await t.test('works east of the meridian', () => {
    assert.equal(formatPlanTime(dinner, reminderTime, 'Europe/London'), 'tomorrow at 6:00 AM');
  });
});

/**
 * A plan that is somewhere else.
 *
 * The reader's clock is the right answer for every plan across town and the wrong one for a trip:
 * telling somebody at home that dinner in Barcelona is "tomorrow at 1:00 PM" is true about their
 * afternoon and useless about the plan. Every case here is about *not* changing the domestic
 * behaviour, because `timeZoneID` is absent on every plan that exists.
 */
test('a plan in another time zone', async (t) => {
  // 2027-01-15 19:00 UTC — 2pm Eastern, 4am the next day in Tokyo.
  const dinner = new Date('2027-01-15T19:00:00Z');
  const morningBefore = new Date('2027-01-15T12:00:00Z');

  await t.test('no plan zone leaves the reader on their own clock', () => {
    assert.equal(
      formatPlanTime(dinner, morningBefore, 'America/New_York'),
      formatPlanTime(dinner, morningBefore, 'America/New_York', null)
    );
    assert.equal(formatPlanTime(dinner, morningBefore, 'America/New_York'), 'today at 2:00 PM');
  });

  await t.test('the plan zone renders the hour there, and says whose clock it is', () => {
    const body = formatPlanTime(dinner, morningBefore, 'America/New_York', 'Asia/Tokyo');

    assert.match(body, /4:00 AM/, `expected the Tokyo hour, got "${body}"`);
    assert.match(body, /Japan/, `the hour is unattributed: "${body}"`);
  });

  await t.test('a plan zone equal to the reader zone adds nothing', () => {
    assert.equal(
      formatPlanTime(dinner, morningBefore, 'America/New_York', 'America/New_York'),
      'today at 2:00 PM'
    );
  });

  // Different names, identical clock in January. Naming one at somebody in the other is noise
  // about a difference they cannot act on.
  await t.test('two zones on the same clock are not another time zone', () => {
    assert.equal(
      formatPlanTime(dinner, morningBefore, 'Europe/London', 'Europe/Dublin'),
      formatPlanTime(dinner, morningBefore, 'Europe/London')
    );
  });

  // A push that throws sends nothing. An identifier this runtime has never heard of — a bad write,
  // an old tz database — must degrade to the reader's clock, not take the reminder down.
  await t.test('an unknown zone falls back rather than throwing', () => {
    assert.equal(
      formatPlanTime(dinner, morningBefore, 'America/New_York', 'Mars/Olympus_Mons'),
      'today at 2:00 PM'
    );
    assert.equal(formatPlanTime(dinner, morningBefore, 'America/New_York', ''), 'today at 2:00 PM');
  });

  // Everything in one frame. The day word, the weekday and the hour are all the plan's, because a
  // body that says "tomorrow" on the reader's calendar and an hour on the plan's is two sentences
  // pretending to be one.
  await t.test('the day word is on the plan clock too', () => {
    const body = formatPlanTime(dinner, morningBefore, 'America/New_York', 'Asia/Tokyo');

    assert.match(body, /^tomorrow/, `expected the Tokyo day, got "${body}"`);
  });

  await t.test('a plan with no time still has nothing to say', () => {
    assert.equal(formatPlanTime(null, morningBefore, 'America/New_York', 'Asia/Tokyo'), null);
  });
});
