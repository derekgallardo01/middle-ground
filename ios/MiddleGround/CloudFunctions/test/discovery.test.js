/**
 * Tests for finding somewhere to go.
 *
 * `discovery.js` is the only module here that spends money and the only one that sends a user's
 * coordinate to a third party, so the two things worth pinning are the ones nobody would notice
 * were broken: **how much location leaves the device**, and **whether the spending actually
 * stops**. A cache that silently misses costs a bill; a rate limit that silently passes costs a
 * suspended account. Both look identical to a working feature from the outside.
 *
 * `fetch` is stubbed globally rather than injected, because that is the seam the production code
 * genuinely uses — swapping in an HTTP client only to satisfy a test would move the untested part
 * rather than remove it.
 */
const { test, describe, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert');

const { fakeFirestore, FieldValueStub, FieldPathStub } = require('./support/firestore-fake');

const store = {};
let firestore = fakeFirestore(store);

const path = require.resolve('firebase-admin/firestore');
require.cache[path] = {
  id: path,
  filename: path,
  loaded: true,
  exports: {
    getFirestore: () => firestore.db(),
    FieldValue: FieldValueStub,
    FieldPath: FieldPathStub,
  },
};

const {
  discover, roundCoordinate, clampRadius, cacheKey,
  MAX_RADIUS_METRES, MIN_RADIUS_METRES, RATE_LIMIT_PER_HOUR,
} = require('../discovery');

const KEYS = { yelp: 'yelp-key', ticketmaster: 'tm-key' };

/** Every URL fetch() was asked for, so the tests can assert on what actually left. */
let requested = [];
let respondWith = null;
const realFetch = global.fetch;

beforeEach(() => {
  for (const key of Object.keys(store)) delete store[key];
  requested = [];
  respondWith = {
    ok: true,
    json: async () => ({
      businesses: [{
        id: 'b1',
        name: 'Lucia\'s',
        categories: [{ title: 'Italian' }],
        distance: 1609.344,
        location: { display_address: ['1 Main St'], city: 'Brooklyn' },
        rating: 4.5,
        price: '$$',
        image_url: 'https://example.com/1.jpg',
        url: 'https://yelp.com/biz/lucias',
      }],
    }),
    text: async () => '',
  };
  global.fetch = async (url) => {
    requested.push(String(url));
    return respondWith;
  };
});

afterEach(() => { global.fetch = realFetch; });

// ---------------------------------------------------------------- geometry

describe('how much location leaves the device', () => {
  test('a coordinate is rounded to about a hundred metres', () => {
    // A doorstep becomes a neighbourhood. This is the entire coarse-location claim.
    assert.equal(roundCoordinate(40.712776), 40.713);
    assert.equal(roundCoordinate(-74.005974), -74.006);
  });

  test('the rounded coordinate is what is actually sent upstream', async () => {
    await discover(
      { kind: 'restaurants', latitude: 40.712776, longitude: -74.005974, radiusMiles: 5 },
      'alice',
      KEYS
    );

    const url = requested[0];
    assert.match(url, /latitude=40\.713/, 'an unrounded latitude reached Yelp');
    assert.match(url, /longitude=-74\.006/, 'an unrounded longitude reached Yelp');
    assert.ok(!url.includes('40.712776'), 'the precise coordinate must not leave');
  });

  test('two people on the same street share a cache entry', () => {
    const a = cacheKey({ kind: 'restaurants', latitude: roundCoordinate(40.71271), longitude: roundCoordinate(-74.00591), radius: 8047, term: '' });
    const b = cacheKey({ kind: 'restaurants', latitude: roundCoordinate(40.71279), longitude: roundCoordinate(-74.00599), radius: 8047, term: '' });
    assert.equal(a, b);
  });
});

describe('radius', () => {
  test('twenty-five miles is clamped to Yelp\'s ceiling rather than refused', () => {
    // 25 miles is 40,234 m and Yelp stops at 40,000. Clamping is why the UI caps at 24: a slider
    // that reaches 25 and returns nothing would look like the feature is broken.
    assert.equal(clampRadius(25), MAX_RADIUS_METRES);
    assert.equal(clampRadius(1000), MAX_RADIUS_METRES);
  });

  test('a sensible radius is converted to metres', () => {
    assert.equal(clampRadius(5), 8047);
    assert.equal(clampRadius(24), 38624);
  });

  test('nonsense falls back rather than throwing', () => {
    assert.equal(clampRadius(undefined), MAX_RADIUS_METRES);
    assert.equal(clampRadius(-3), MIN_RADIUS_METRES);
    assert.equal(clampRadius('abc'), MAX_RADIUS_METRES);
  });
});

// ---------------------------------------------------------------- spending

describe('not spending more than it has to', () => {
  test('a repeated search is answered from the cache without calling out', async () => {
    const args = { kind: 'restaurants', latitude: 40.713, longitude: -74.006, radiusMiles: 5 };

    const first = await discover(args, 'alice', KEYS);
    assert.equal(first.cached, false);
    assert.equal(requested.length, 1);

    const second = await discover(args, 'alice', KEYS);
    assert.equal(second.cached, true);
    assert.equal(requested.length, 1, 'the second search hit the network anyway');
    assert.deepEqual(second.results, first.results);
  });

  test('a different radius is a different search', async () => {
    const base = { kind: 'restaurants', latitude: 40.713, longitude: -74.006 };
    await discover({ ...base, radiusMiles: 5 }, 'alice', KEYS);
    await discover({ ...base, radiusMiles: 10 }, 'alice', KEYS);
    assert.equal(requested.length, 2, 'dragging the slider must not serve stale results');
  });

  test('the rate limit refuses instead of spending', async () => {
    const base = { kind: 'restaurants', latitude: 40.713, longitude: -74.006 };
    // Each call varies the term so nothing is served from cache.
    for (let i = 0; i < RATE_LIMIT_PER_HOUR; i += 1) {
      await discover({ ...base, term: `t${i}` }, 'bob', KEYS);
    }
    assert.equal(requested.length, RATE_LIMIT_PER_HOUR);

    await assert.rejects(
      discover({ ...base, term: 'one-too-many' }, 'bob', KEYS),
      /Too many searches/
    );
    assert.equal(requested.length, RATE_LIMIT_PER_HOUR, 'it spent anyway after refusing');
  });

  test('one person exhausting their quota does not stop anybody else', async () => {
    const base = { kind: 'restaurants', latitude: 40.713, longitude: -74.006 };
    for (let i = 0; i < RATE_LIMIT_PER_HOUR; i += 1) {
      await discover({ ...base, term: `t${i}` }, 'bob', KEYS);
    }
    await assert.doesNotReject(discover({ ...base, term: 'fresh' }, 'carol', KEYS));
  });

  test('a cached answer does not consume the quota', async () => {
    const args = { kind: 'restaurants', latitude: 40.713, longitude: -74.006, radiusMiles: 5 };
    await discover(args, 'dave', KEYS);
    for (let i = 0; i < RATE_LIMIT_PER_HOUR * 2; i += 1) {
      // Scrolling back to the same results should never be rationed.
      await discover(args, 'dave', KEYS); // eslint-disable-line no-await-in-loop
    }
    assert.equal(requested.length, 1);
  });
});

// ---------------------------------------------------------------- shape

describe('what comes back', () => {
  test('a place is normalised, with distance in miles', async () => {
    const { results } = await discover(
      { kind: 'restaurants', latitude: 40.713, longitude: -74.006, radiusMiles: 5 },
      'alice',
      KEYS
    );

    assert.equal(results.length, 1);
    assert.deepEqual(
      { name: results[0].name, category: results[0].category, distanceMiles: results[0].distanceMiles },
      { name: "Lucia's", category: 'Italian', distanceMiles: 1 }
    );
    assert.equal(results[0].source, 'yelp');
  });

  test('hotels ask for hotels rather than searching the word', async () => {
    // A term search for "hotel" returns restaurants with "hotel" in the name.
    await discover({ kind: 'hotels', latitude: 40.713, longitude: -74.006 }, 'alice', KEYS);
    assert.match(requested[0], /categories=hotels/);
  });

  test('events go to Ticketmaster, with the radius in miles', async () => {
    respondWith = {
      ok: true,
      json: async () => ({
        _embedded: {
          events: [{
            id: 'e1',
            name: 'A Concert',
            classifications: [{ segment: { name: 'Music' } }],
            dates: { start: { dateTime: '2026-09-01T19:00:00Z' } },
            images: [{ url: 'https://example.com/e.jpg' }],
            url: 'https://ticketmaster.com/event/e1',
            _embedded: { venues: [{ name: 'The Hall', city: { name: 'Brooklyn' }, distance: 2.4 }] },
          }],
        },
      }),
      text: async () => '',
    };

    const { results } = await discover(
      { kind: 'events', latitude: 40.713, longitude: -74.006, radiusMiles: 10 },
      'alice',
      KEYS
    );

    assert.match(requested[0], /ticketmaster/);
    assert.match(requested[0], /unit=miles/);
    assert.match(requested[0], /radius=10/);
    assert.equal(results[0].name, 'A Concert');
    assert.equal(results[0].startsAt, '2026-09-01T19:00:00Z', 'an event without a time is not an event');
    assert.equal(results[0].source, 'ticketmaster');
  });

  test('an unknown kind falls back rather than failing', async () => {
    await assert.doesNotReject(
      discover({ kind: 'teleportation', latitude: 40.713, longitude: -74.006 }, 'alice', KEYS)
    );
    assert.match(requested[0], /yelp/);
  });

  test('no coordinate is refused before anything is spent', async () => {
    await assert.rejects(
      discover({ kind: 'restaurants', radiusMiles: 5 }, 'alice', KEYS),
      /latitude and longitude/
    );
    assert.equal(requested.length, 0);
  });

  test('an upstream failure surfaces rather than caching an empty list', async () => {
    respondWith = { ok: false, status: 429, text: async () => 'Too Many Requests', json: async () => ({}) };

    await assert.rejects(
      discover({ kind: 'restaurants', latitude: 40.713, longitude: -74.006 }, 'alice', KEYS),
      /Yelp 429/
    );
    // Caching a failure would serve "nowhere nearby" for the next ten minutes.
    const args = { kind: 'restaurants', latitude: 40.713, longitude: -74.006 };
    respondWith = {
      ok: true,
      json: async () => ({ businesses: [] }),
      text: async () => '',
    };
    const retry = await discover(args, 'alice', KEYS);
    assert.equal(retry.cached, false);
  });

  test('nowhere nearby is an empty list, not an error', async () => {
    respondWith = { ok: true, json: async () => ({ businesses: [] }), text: async () => '' };

    const { results } = await discover(
      { kind: 'restaurants', latitude: 40.713, longitude: -74.006 },
      'alice',
      KEYS
    );
    assert.deepEqual(results, []);
  });
});
