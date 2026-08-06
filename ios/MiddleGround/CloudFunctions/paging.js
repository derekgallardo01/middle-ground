/**
 * Reading a lot of documents without reading them all at once.
 *
 * `weeklyNudge` is the only function that touches whole collections, and it did it in one gulp:
 * every user and every relationship in a single response, then a `Promise.all` that started a
 * per-user Firestore query for all of them simultaneously. At the current size that is fine, and
 * that is exactly what makes it worth fixing now — the failure mode is a burst at some unknown
 * threshold rather than a curve anybody watches climb.
 *
 * Its own module, like `time.js`, so it can be tested without `firebase-functions` — which is the
 * only reason these two functions are not sitting in `index.js` next to their caller.
 */

/**
 * Walks a collection a page at a time, ordered by document ID.
 *
 * Document ID because it is the one field every document has and it is unique, which is what a
 * cursor needs: `startAfter` on a non-unique field can skip or repeat documents that share a
 * value. Yields whole pages rather than documents so a caller can process a page as a batch.
 *
 * @param {() => FirebaseFirestore.Firestore} db how to reach Firestore, resolved per call so a
 *   test can substitute one and production keeps its lazy `getFirestore()`
 * @param {FirebaseFirestore.FieldPath} fieldPath the `FieldPath` class, for `documentId()`
 */
async function* pagedDocs(db, fieldPath, collection, pageSize) {
  let cursor = null;
  for (;;) {
    let query = db().collection(collection).orderBy(fieldPath.documentId()).limit(pageSize);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) return;
    yield snapshot.docs;
    // A short page is the last page; asking again would cost a read to learn nothing.
    if (snapshot.size < pageSize) return;
    cursor = snapshot.docs[snapshot.docs.length - 1];
  }
}

/**
 * `Promise.all` with a ceiling: a fixed pool of workers pulling from one shared index.
 *
 * Results stay in input order, because the caller counts them and a reordered array would make
 * "which user was nudged" unanswerable from the return value.
 */
async function mapWithConcurrency(items, limit, work) {
  const results = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next;
      next += 1;
      results[index] = await work(items[index], index);
    }
  });
  await Promise.all(workers);
  return results;
}

module.exports = { pagedDocs, mapWithConcurrency };
