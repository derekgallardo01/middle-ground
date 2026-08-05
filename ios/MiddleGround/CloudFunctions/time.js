/**
 * Turning an instant into something a person reads on their own clock.
 *
 * Its own module so it can be tested without loading firebase-functions. That matters more than
 * tidiness here: this shipped naming America/New_York for everybody, so a plan the app showed as
 * 10pm arrived as "tomorrow at 1:00 AM" for anyone outside Eastern — and a test that passed a
 * zone would have caught it on the first run.
 */

const HOUR = 60 * 60 * 1000;

/** Miami, and the fallback for anybody whose zone is unknown. */
const DEFAULT_TIME_ZONE = 'America/New_York';

/** Firestore hands back a Timestamp; a seeded or hand-written document might not. */
function toMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === 'function') return value.toMillis();
  return new Date(value).getTime();
}

/**
 * "tomorrow at 7:30 PM", "tonight at 8:00 PM", or "Friday at 1:00 PM". Null with no usable time.
 *
 * The day is compared rather than assumed. Sixteen hours ahead is *usually* tomorrow, but a plan
 * late tonight is reminded this morning — calling that "tomorrow" would send people to the wrong
 * evening, which is a worse failure than not reminding them at all.
 */
function formatPlanTime(value, now = new Date(), zone = DEFAULT_TIME_ZONE) {
  const millis = toMillis(value);
  if (!millis) return null;
  const when = new Date(millis);

  const time = new Intl.DateTimeFormat('en-US', {
    hour: 'numeric',
    minute: '2-digit',
    timeZone: zone,
  }).format(when);

  const day = (date) =>
    new Intl.DateTimeFormat('en-CA', { timeZone: zone }).format(date);
  const dayDiff = Math.round(
    (Date.parse(`${day(when)}T00:00:00Z`) - Date.parse(`${day(now)}T00:00:00Z`)) / (24 * HOUR)
  );

  if (dayDiff === 0) {
    const hour = Number(
      new Intl.DateTimeFormat('en-US', { hour: 'numeric', hour12: false, timeZone: zone })
        .format(when)
    );
    return `${hour >= 17 ? 'tonight' : 'today'} at ${time}`;
  }
  if (dayDiff === 1) return `tomorrow at ${time}`;

  const weekday = new Intl.DateTimeFormat('en-US', {
    weekday: 'long',
    timeZone: zone,
  }).format(when);
  return `${weekday} at ${time}`;
}

module.exports = { formatPlanTime, toMillis, DEFAULT_TIME_ZONE, HOUR };
