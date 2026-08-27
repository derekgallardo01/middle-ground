/**
 * Tests that the queries this app actually issues have indexes to run on — and that they filter
 * on fields that exist.
 *
 * Both halves come from one bug. `FirestoreAdminRepository.activeUsers` filtered `events` on
 * `name`, a field no event has ever carried: the type is written as `type`. Firestore does not
 * complain about a query on a field that does not exist, it just matches nothing, so daily and
 * weekly actives would have read zero forever and looked like an answer.
 *
 * It only surfaced because the phantom field was paired with a range on `at`, and that pair
 * wants a composite index nobody had declared — so the whole admin overview failed with
 * FAILED_PRECONDITION instead. A missing index is loud; a phantom field is silent. This file
 * covers both, because the loud one was the only reason anyone found the quiet one.
 *
 * Runs in Node rather than XCTest because it needs to read the repository's own source and the
 * index manifest, and the simulator can see neither.
 */
const { test, describe } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const indexes = JSON.parse(
  fs.readFileSync(path.join(ROOT, 'firestore.indexes.json'), 'utf8')
);

/** A composite index, flattened to `collection:field dir,field dir` for comparison. */
function shapeOf(index) {
  const fields = index.fields
    .map((f) => `${f.fieldPath} ${f.arrayConfig || f.order}`)
    .join(',');
  return `${index.collectionGroup}:${fields}`;
}

const declared = new Set(indexes.indexes.map(shapeOf));

/**
 * Every composite shape something in this repo depends on, and who depends on it.
 *
 * A query that needs an index and does not have one does not degrade — it throws, and the whole
 * screen or scheduled function goes with it. Deleting an entry here is a deliberate act.
 */
const required = [
  {
    shape: 'events:type ASCENDING,at ASCENDING',
    who: 'FirestoreAdminRepository.activeUsers (DAU/WAU) and dailyDigest',
  },
  {
    shape: 'events:userID ASCENDING,at DESCENDING',
    who: 'FirestoreEventRepository.events(forUser:) — the admin Activity section',
  },
  {
    shape: 'requests:allParticipantIDs CONTAINS,updatedAt DESCENDING',
    who: 'FirestoreRequestRepository.fetchRequests — the home feed',
  },
  {
    shape: 'requests:allParticipantIDs CONTAINS,status ASCENDING',
    who: 'pendingCountFor — the push badge',
  },
  {
    shape: 'requests:allParticipantIDs CONTAINS,proposedTime DESCENDING',
    who: 'weeklyNudge',
  },
  {
    shape: 'requests:status ASCENDING,proposedTime ASCENDING',
    who: 'promptForAttendance — single-day plans',
  },
  {
    shape: 'requests:status ASCENDING,endTime ASCENDING',
    who: 'promptForAttendance — multi-day trips',
  },
  {
    shape: 'relationships:participantIDs CONTAINS,createdAt DESCENDING',
    who: 'FirestoreRelationshipRepository.fetchRelationships',
  },
];

describe('firestore.indexes.json', () => {
  for (const { shape, who } of required) {
    test(`declares ${shape}`, () => {
      assert.ok(
        declared.has(shape),
        `No index for ${shape}, needed by ${who}. Without it that query throws ` +
          `FAILED_PRECONDITION and takes its whole screen with it.`
      );
    });
  }

  test('every declared index is one somebody asked for', () => {
    const wanted = new Set(required.map((r) => r.shape));
    const orphans = [...declared].filter((s) => !wanted.has(s));
    assert.deepStrictEqual(
      orphans,
      [],
      'Indexes nothing in `required` claims. Either add the caller here or drop the index — ' +
        'an index kept for a query that no longer exists is a cost with no reader.'
    );
  });
});

describe('events are queried on fields that exist', () => {
  // The wire shape, from EventDTO. Kept here rather than derived from the Swift, so that
  // renaming a field on the DTO without updating its readers fails rather than quietly
  // agreeing with itself.
  const eventFields = new Set([
    'id', 'userID', 'type', 'requestID', 'relationshipID', 'metadata', 'at', 'expiresAt',
  ]);

  const repositories = path.join(
    ROOT, 'Sources', 'MiddleGround', 'Core', 'Repositories', 'Firestore'
  );

  /**
   * The field literals in each query chain hanging off `collection("events")`.
   *
   * Scoped to the chain because these files query several collections apiece, and `updatedAt`
   * is a perfectly good field on a request. Chains assembled from variables — the admin
   * overview's `CountQuery` — are out of reach here and are covered by `EventField` in Swift.
   */
  function eventQueryFields(source) {
    const found = [];
    const field = (line) => {
      const match = line.match(/(?:whereField|order)\(\s*(?:by:\s*)?"([^"]+)"/);
      return match ? match[1] : null;
    };
    for (const chunk of source.split('collection("events")').slice(1)) {
      const [rest, ...lines] = chunk.split('\n');
      // The chain may continue on the same line as `collection("events")` or below it.
      const sameLine = field(rest);
      if (sameLine) found.push(sameLine);
      for (const line of lines) {
        if (!line.trim().startsWith('.')) break;
        const named = field(line);
        if (named) found.push(named);
      }
    }
    return found;
  }

  test('no repository filters or orders `events` on a phantom field', () => {
    const offenders = [];
    for (const file of fs.readdirSync(repositories).filter((f) => f.endsWith('.swift'))) {
      const source = fs.readFileSync(path.join(repositories, file), 'utf8');
      for (const field of eventQueryFields(source)) {
        // `metadata.kind` addresses into the map, so only the root is a field.
        if (!eventFields.has(field.split('.')[0])) offenders.push(`${file}: "${field}"`);
      }
    }
    assert.deepStrictEqual(
      offenders,
      [],
      'These query a field no event document carries, so they match nothing and report zero ' +
        'as though it were an answer.'
    );
  });

  test('the scan can actually see a bad field', () => {
    const planted = `db.collection("events")\n  .whereField("name", isEqualTo: x)\n`;
    assert.deepStrictEqual(eventQueryFields(planted), ['name']);
  });

  test('and does not reach into a neighbouring collection\u2019s chain', () => {
    const other = `db.collection("events")\n  .order(by: "at")\n\ndb.collection("requests")\n  .order(by: "updatedAt")\n`;
    assert.deepStrictEqual(eventQueryFields(other), ['at']);
  });
});
