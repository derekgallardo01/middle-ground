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

/** Whether this runtime recognises a zone at all. An unknown one must not take a push down. */
function isKnownZone(zone) {
  if (!zone) return false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: zone });
    return true;
  } catch {
    return false;
  }
}

/** Offset in minutes at a given instant, so two zones are compared by clock and not by name. */
function offsetMinutes(zone, at) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: zone,
    timeZoneName: 'longOffset',
  }).formatToParts(at);
  const name = parts.find((part) => part.type === 'timeZoneName');
  // "GMT+01:00", or plain "GMT" at zero.
  const match = /GMT([+-])(\d{2}):(\d{2})/.exec(name ? name.value : '');
  if (!match) return 0;
  const sign = match[1] === '-' ? -1 : 1;
  return sign * (Number(match[2]) * 60 + Number(match[3]));
}

/**
 * What to call a clock in a push body — "Japan Time".
 *
 * Generic rather than standard, so a trip does not read "Central European Summer Time" in July and
 * "Central European Standard Time" in January for the same place. Falls back to the offset, which
 * is ugly but never wrong.
 */
function zoneName(zone, at) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: zone,
    timeZoneName: 'shortGeneric',
  }).formatToParts(at);
  const name = parts.find((part) => part.type === 'timeZoneName');
  return name && name.value ? name.value : zone;
}

/**
 * "tomorrow at 7:30 PM", "tonight at 8:00 PM", or "Friday at 1:00 PM". Null with no usable time.
 *
 * The day is compared rather than assumed. Sixteen hours ahead is *usually* tomorrow, but a plan
 * late tonight is reminded this morning — calling that "tomorrow" would send people to the wrong
 * evening, which is a worse failure than not reminding them at all.
 *
 * `planZone` is the zone the plan actually happens in, when it is somewhere else. A trip is the
 * one case where the reader's clock is the wrong answer: telling somebody at home that dinner in
 * Barcelona is "tomorrow at 1:00 PM" is true about their morning and useless about the plan. When
 * the two clocks differ, **everything** is rendered in the plan's — the hour, the weekday and the
 * "tomorrow" alike, because mixing frames is worse than either one — and the clock is named, so
 * the hour is not a bare number in an unstated zone.
 */
function formatPlanTime(value, now = new Date(), zone = DEFAULT_TIME_ZONE, planZone = null) {
  const millis = toMillis(value);
  if (!millis) return null;
  const when = new Date(millis);

  // Only a zone this runtime knows, and only when it is a genuinely different clock at that
  // instant — Europe/Dublin and Europe/London in January are the same hour, and naming one at
  // somebody in the other is noise about a difference they cannot act on.
  const elsewhere =
    isKnownZone(planZone) && offsetMinutes(planZone, when) !== offsetMinutes(zone, when);
  const suffix = elsewhere ? ` ${zoneName(planZone, when)}` : '';
  if (elsewhere) zone = planZone;

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
    return `${hour >= 17 ? 'tonight' : 'today'} at ${time}${suffix}`;
  }
  if (dayDiff === 1) return `tomorrow at ${time}${suffix}`;

  const weekday = new Intl.DateTimeFormat('en-US', {
    weekday: 'long',
    timeZone: zone,
  }).format(when);
  return `${weekday} at ${time}${suffix}`;
}

module.exports = { formatPlanTime, toMillis, zoneName, DEFAULT_TIME_ZONE, HOUR };
