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
