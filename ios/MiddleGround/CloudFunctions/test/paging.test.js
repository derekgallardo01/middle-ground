/**
 * Tests for reading a collection without reading it all at once.
 *
 * `weeklyNudge` is the only function that touches whole collections, and it cannot be run here —
 * it needs `firebase-functions` and a scheduler. So the two things that make it bounded live in
 * `paging.js` and are tested directly: that the cursor walks every document exactly once, and
 * that the fan-out has a ceiling. The second one has no observable effect on the *result*, which
 * is precisely why it needs a test — a broken limit looks perfect until the day it doesn't.
 */
const { test, describe } = require('node:test');
const assert = require('node:assert');

const { pagedDocs, mapWithConcurrency } = require('../paging');

/** Just enough Firestore to page: ordered ids, a cursor, and a limit. */
function fakeDb(ids) {
  const docs = ids.map((id) => ({ id, data: () => ({ id }) }));
  let queriesIssued = 0;

  const query = (after, cap) => ({
    orderBy: () => query(after, cap),
    limit: (count) => query(after, count),
    startAfter: (doc) => query(doc.id, cap),
    get: async () => {
      queriesIssued += 1;
      const start = after === null ? 0 : docs.findIndex((d) => d.id === after) + 1;
      const page = docs.slice(start, cap === undefined ? undefined : start + cap);
      return { docs: page, empty: page.length === 0, size: page.length };
    },
  });

  const db = () => ({ collection: () => query(null, undefined) });
  db.queriesIssued = () => queriesIssued;
  return db;
}

const fieldPath = { documentId: () => 'id' };

describe('paging a collection', () => {
  test('walks every document exactly once', async () => {
    const ids = Array.from({ length: 25 }, (_, i) => `u${String(i).padStart(3, '0')}`);
    const db = fakeDb(ids);

    const seen = [];
    for await (const page of pagedDocs(db, fieldPath, 'users', 10)) {
      seen.push(...page.map((doc) => doc.id));
    }

    assert.deepEqual(seen, ids);
    assert.equal(new Set(seen).size, ids.length, 'a cursor that repeats would nudge twice');
  });

  test('stops on a short page rather than paying for an empty one', async () => {
    const db = fakeDb(['a', 'b', 'c']);

    // 3 documents, page size 10: one query returns everything, and there is nothing to learn
    // from a second.
    for await (const page of pagedDocs(db, fieldPath, 'users', 10)) {
      assert.equal(page.length, 3);
    }

    assert.equal(db.queriesIssued(), 1);
  });

  test('an exactly-full last page still terminates', async () => {
    const db = fakeDb(['a', 'b', 'c', 'd']);

    const seen = [];
    for await (const page of pagedDocs(db, fieldPath, 'users', 2)) {
      seen.push(...page.map((doc) => doc.id));
    }

    // Two full pages, then one empty query to discover there is no more. Terminating matters
    // more than the extra read: this loop has no other stopping condition.
    assert.deepEqual(seen, ['a', 'b', 'c', 'd']);
    assert.equal(db.queriesIssued(), 3);
  });

  test('an empty collection yields nothing', async () => {
    const db = fakeDb([]);

    const pages = [];
    for await (const page of pagedDocs(db, fieldPath, 'users', 10)) pages.push(page);

    assert.equal(pages.length, 0);
  });
});

describe('bounded fan-out', () => {
  test('never runs more than the limit at once', async () => {
    const items = Array.from({ length: 50 }, (_, i) => i);
    let running = 0;
    let peak = 0;

    await mapWithConcurrency(items, 5, async () => {
      running += 1;
      peak = Math.max(peak, running);
      await new Promise((resolve) => setTimeout(resolve, 1));
      running -= 1;
    });

    assert.equal(peak, 5, `ran ${peak} at once against a limit of 5`);
  });

  test('results keep their input order', async () => {
    const items = ['a', 'b', 'c', 'd'];

    // Deliberately finishing out of order: the first item takes longest.
    const results = await mapWithConcurrency(items, 4, async (item, index) => {
      await new Promise((resolve) => setTimeout(resolve, (items.length - index) * 2));
      return item.toUpperCase();
    });

    assert.deepEqual(results, ['A', 'B', 'C', 'D']);
  });

  test('every item is processed exactly once', async () => {
    const items = Array.from({ length: 37 }, (_, i) => i);
    const touched = [];

    await mapWithConcurrency(items, 8, async (item) => {
      touched.push(item);
    });

    assert.equal(touched.length, 37);
    assert.equal(new Set(touched).size, 37);
  });

  test('a limit larger than the work is not a problem', async () => {
    const results = await mapWithConcurrency([1, 2], 100, async (n) => n * 2);

    assert.deepEqual(results, [2, 4]);
  });

  test('no items means no workers', async () => {
    const results = await mapWithConcurrency([], 10, async () => {
      throw new Error('nothing should run');
    });

    assert.deepEqual(results, []);
  });
});
