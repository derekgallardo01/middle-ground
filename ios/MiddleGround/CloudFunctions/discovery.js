/**
 * Live events near somewhere, from an API key that never leaves the server.
 *
 * **Places do not come through here.** They come from Apple's `MKLocalSearch` on the device, which
 * costs nothing, needs no key, and — the part that matters most — never sends the coordinate to a
 * third party at all. This started out as a Yelp proxy; Yelp retired its free tier and now starts
 * at $229 a month, which is not a sensible dependency for helping two people pick a restaurant.
 * MapKit turned out to be better on every axis except ratings and photos, and those are one tap
 * away through a link.
 *
 * Events are the exception, because no on-device API knows what is *on* tonight. Ticketmaster's
 * Discovery API does, is free, and is self-serve. It is the only reason this file still exists.
 *
 * It runs server-side for three reasons, in order of how much they matter:
 *
 *   1. A key shipped in an iOS binary is a key anybody can extract. It stays here.
 *   2. A slider being dragged is twenty searches. The cache turns that into one.
 *   3. A metered API reached directly from a client is an unbounded bill. The rate limit is the
 *      only thing standing between a loop and a suspended account.
 *
 * The coordinate is still rounded before it is used, which is what makes "coarse location" true
 * rather than a word in a privacy questionnaire — see `roundCoordinate`.
 */

const { getFirestore } = require('firebase-admin/firestore');

const db = () => getFirestore();

/**
 * Ticketmaster accepts up to 19,999 miles, so nothing here is the binding constraint any more.
 * Capped at 25 miles because that is what the UI offers and a wider search returns a different
 * city's listings — Yelp's 40,000 m ceiling was the only reason 25 was ever awkward.
 */
const MAX_RADIUS_METRES = Math.round(25 * 1609.344);
const MIN_RADIUS_METRES = 500;
const METRES_PER_MILE = 1609.344;

/** More than a person will read on a chip row, and enough to be worth caching. */
const MAX_RESULTS = 20;

/** How long a search stays warm. Long enough to cover a slider drag and a change of mind. */
const CACHE_TTL_MS = 10 * 60 * 1000;

/** Per user, per hour. Generous for a person, and a hard stop for a loop. */
const RATE_LIMIT_PER_HOUR = 60;

const CACHE_COLLECTION = 'discovery_cache';
const RATE_COLLECTION = 'discovery_rate';

/**
 * Three decimal places — about 110 m at the equator, less further north.
 *
 * This is the whole coarse-location claim in one function. The app asks CoreLocation for
 * `kCLLocationAccuracyHundredMeters` and then rounds again here, so what reaches a third party is
 * a neighbourhood rather than a doorstep. It also makes the cache useful: two people on the same
 * street produce the same key.
 */
function roundCoordinate(value) {
  return Math.round(value * 1000) / 1000;
}

/** Clamped rather than rejected: a request for 50 miles should return 24 miles of results. */
function clampRadius(miles) {
  const requested = Number(miles);
  if (!Number.isFinite(requested)) return MAX_RADIUS_METRES;
  const metres = Math.round(requested * METRES_PER_MILE);
  return Math.min(Math.max(metres, MIN_RADIUS_METRES), MAX_RADIUS_METRES);
}

function cacheKey({ kind, latitude, longitude, radius, term }) {
  return [kind, latitude, longitude, radius, (term || '').toLowerCase().trim()]
    .join('|')
    .replace(/\//g, '_');
}

/**
 * Refuses rather than spends.
 *
 * Counts calls in a fixed hourly window instead of a rolling one: a rolling window needs the
 * timestamps of every call, and this only needs to know whether to stop.
 */
async function withinRateLimit(uid) {
  const hour = Math.floor(Date.now() / 3600000);
  const ref = db().collection(RATE_COLLECTION).doc(`${uid}_${hour}`);
  const snapshot = await ref.get();
  const used = snapshot.exists ? (snapshot.data().count || 0) : 0;
  if (used >= RATE_LIMIT_PER_HOUR) return false;
  await ref.set({ count: used + 1, hour, expiresAt: new Date(Date.now() + 2 * 3600000) }, { merge: true });
  return true;
}

async function cached(key) {
  const snapshot = await db().collection(CACHE_COLLECTION).doc(key).get();
  if (!snapshot.exists) return null;
  const data = snapshot.data();
  const at = data.at?.toMillis ? data.at.toMillis() : new Date(data.at).getTime();
  if (!Number.isFinite(at) || Date.now() - at > CACHE_TTL_MS) return null;
  return data.results || [];
}

async function remember(key, results) {
  await db().collection(CACHE_COLLECTION).doc(key).set({
    results,
    at: new Date(),
    // A TTL policy on this field is what stops the cache growing forever; the collection is
    // disposable by definition.
    expiresAt: new Date(Date.now() + CACHE_TTL_MS),
  });
}

/**
 * Ticketmaster Discovery. Live events.
 *
 * Ticketmaster takes a radius in miles
 * directly, which is the unit the UI already uses.
 */
async function searchTicketmaster({ latitude, longitude, radius, term }, apiKey) {
  const params = new URLSearchParams({
    apikey: apiKey,
    latlong: `${latitude},${longitude}`,
    radius: String(Math.round(radius / METRES_PER_MILE)),
    unit: 'miles',
    size: String(MAX_RESULTS),
    sort: 'date,asc',
  });
  if (term) params.set('keyword', term);

  const res = await fetch(`https://app.ticketmaster.com/discovery/v2/events.json?${params}`);
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Ticketmaster ${res.status}: ${body.slice(0, 200)}`);
  }
  const json = await res.json();
  const events = json._embedded?.events || [];
  return events.map((e) => {
    const venue = e._embedded?.venues?.[0];
    return {
      id: e.id,
      name: e.name,
      category: e.classifications?.[0]?.segment?.name || 'Event',
      distanceMiles: typeof venue?.distance === 'number'
        ? Math.round(venue.distance * 10) / 10
        : null,
      address: venue?.name || null,
      city: venue?.city?.name || null,
      rating: null,
      price: null,
      imageURL: (e.images || [])[0]?.url || null,
      url: e.url || null,
      // The one field places do not have, and the whole point of an event.
      startsAt: e.dates?.start?.dateTime || null,
      source: 'ticketmaster',
    };
  });
}

/**
 * Only events. Places are answered on the device by MapKit and never reach this function — see
 * the note at the top of the file.
 */
const KINDS = { events: { source: 'ticketmaster' } };

/**
 * One search.
 *
 * @param {object} request  `{ kind, latitude, longitude, radiusMiles, term }`
 * @param {string} uid      the caller, for rate limiting
 * @param {{ticketmaster: string}} keys
 */
async function discover(request, uid, keys) {
  const kind = 'events';

  const latitude = roundCoordinate(Number(request.latitude));
  const longitude = roundCoordinate(Number(request.longitude));
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new Error('A latitude and longitude are required.');
  }

  const radius = clampRadius(request.radiusMiles);
  const term = typeof request.term === 'string' ? request.term.slice(0, 80) : '';
  const key = cacheKey({ kind, latitude, longitude, radius, term });

  const hit = await cached(key);
  // Deliberately before the rate limit: a cached answer costs nothing upstream, so charging
  // somebody's quota for it would only punish them for scrolling back.
  if (hit) return { results: hit, cached: true, radiusMiles: radius / METRES_PER_MILE };

  if (!(await withinRateLimit(uid))) {
    throw new Error('Too many searches just now. Try again shortly.');
  }

  const results = await searchTicketmaster(
    { latitude, longitude, radius, term },
    keys.ticketmaster
  );

  await remember(key, results);
  return { results, cached: false, radiusMiles: radius / METRES_PER_MILE };
}

module.exports = {
  discover,
  roundCoordinate,
  clampRadius,
  cacheKey,
  MAX_RADIUS_METRES,
  MIN_RADIUS_METRES,
  RATE_LIMIT_PER_HOUR,
  CACHE_TTL_MS,
  KINDS,
};
