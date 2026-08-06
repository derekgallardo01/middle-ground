/**
 * Enough Firestore to run the trigger handlers, and no more.
 *
 * `push.test.js` carries its own smaller version inline; this one is shared because
 * `handlers.test.js` exercises fourteen handlers whose needs differ — subcollections, batched
 * deletes, collection-group reads, cursors.
 *
 * Documents are keyed by full path (`requests/r1`, `requests/r1/messages/m1`), which is what makes
 * subcollections and `collectionGroup` fall out for free rather than needing a nested structure.
 */

const { FieldPathStub, applyFieldValues, FieldValueStub } = require('./field-values');

/**
 * @param {string} path
 * @param {object|undefined} data
 * @param {(path: string) => object} [makeRef] builds the document reference for `ref`
 *
 * `ref` has to be a real reference rather than `{ path }`: `purge.js` walks from a query result
 * into that document's subcollections (`doc.ref.collection('availability')`). With a bare object
 * that call throws, the surrounding `Promise.allSettled` swallows it, and the test reports the
 * data as "remaining" — blaming the code for a limitation of the fake.
 */
function snapshot(path, data, makeRef) {
  return {
    id: path.split('/').pop(),
    ref: makeRef ? makeRef(path) : { path },
    exists: data !== undefined,
    data: () => data,
  };
}

/** A doc belongs to a collection when it sits exactly one segment below it. */
function docsIn(store, collectionPath) {
  const depth = collectionPath.split('/').length + 1;
  return Object.entries(store)
    .filter(([path]) => path.startsWith(`${collectionPath}/`) && path.split('/').length === depth);
}

/** Collection-group: match on the collection name wherever it appears. */
function docsInGroup(store, name) {
  return Object.entries(store).filter(([path]) => {
    const parts = path.split('/');
    return parts.length >= 2 && parts[parts.length - 2] === name;
  });
}

const toMillis = (v) => {
  if (v === null || v === undefined) return NaN;
  if (typeof v.toMillis === 'function') return v.toMillis();
  return new Date(v).getTime();
};

function matches(data, { field, op, value }) {
  const actual = data[field];
  switch (op) {
    case 'array-contains': return (actual || []).includes(value);
    case 'array-contains-any': return (actual || []).some((x) => value.includes(x));
    case 'in': return value.includes(actual);
    case 'not-in': return !value.includes(actual);
    case '<': return toMillis(actual) < toMillis(value);
    case '<=': return toMillis(actual) <= toMillis(value);
    case '>': return toMillis(actual) > toMillis(value);
    case '>=': return toMillis(actual) >= toMillis(value);
    case '!=': return actual !== value;
    default: return actual === value;
  }
}

/**
 * @param {object} store documents keyed by full path; mutated in place so tests can assert on it
 * @returns {{db: Function, deleted: string[]}}
 */
function fakeFirestore(store) {
  const deleted = [];

  const query = (entriesFor, spec) => ({
    where: (field, op, value) =>
      query(entriesFor, { ...spec, filters: [...spec.filters, { field, op, value }] }),
    orderBy: (field, dir) => query(entriesFor, { ...spec, orderBy: { field, dir } }),
    limit: (n) => query(entriesFor, { ...spec, limit: n }),
    startAfter: (doc) => query(entriesFor, { ...spec, after: doc.ref ? doc.ref.path : doc.path }),
    /// The digest counts rather than reads. Without this it caught its own error and reported
    /// zeroes, so every digest figure would have been a confident nothing.
    count: () => ({
      get: async () => {
        const matching = entriesFor().filter(([, data]) => spec.filters.every((f) => matches(data, f)));
        return { data: () => ({ count: matching.length }) };
      },
    }),
    get: async () => {
      let entries = entriesFor().filter(([, data]) => spec.filters.every((f) => matches(data, f)));

      if (spec.orderBy && spec.orderBy.field === '__name__') {
        // `orderBy(FieldPath.documentId())` — what `pagedDocs` uses as its cursor. Sorts by path
        // and drops nothing, unlike ordering on a real field.
        entries.sort(([a], [b]) => a.localeCompare(b));
        if (spec.orderBy.dir === 'desc') entries.reverse();
      } else if (spec.orderBy) {
        const { field, dir } = spec.orderBy;
        // Firestore drops documents missing the ordered field — the reason undated requests are
        // invisible to the nudge, which is behaviour worth reproducing rather than smoothing over.
        entries = entries.filter(([, d]) => d[field] !== undefined && d[field] !== null);
        entries.sort(([, a], [, b]) => toMillis(a[field]) - toMillis(b[field]));
        if (dir === 'desc') entries.reverse();
      } else {
        entries.sort(([a], [b]) => a.localeCompare(b));
      }

      if (spec.after) {
        const index = entries.findIndex(([path]) => path === spec.after);
        entries = index === -1 ? entries : entries.slice(index + 1);
      }
      if (spec.limit !== undefined) entries = entries.slice(0, spec.limit);

      const docs = entries.map(([path, data]) => snapshot(path, data, docRef));
      return {
        docs,
        empty: docs.length === 0,
        size: docs.length,
        forEach: (fn) => docs.forEach(fn),
      };
    },
  });

  const blank = { filters: [] };

  const docRef = (path) => ({
    path,
    id: path.split('/').pop(),
    get: async () => snapshot(path, store[path], docRef),
    set: async (data, options) => {
      store[path] = options && options.merge
        ? applyFieldValues({ ...(store[path] || {}) }, data)
        : applyFieldValues({}, data);
    },
    update: async (data) => {
      store[path] = applyFieldValues({ ...(store[path] || {}) }, data);
    },
    delete: async () => { delete store[path]; deleted.push(path); },
    collection: (name) => collectionRef(`${path}/${name}`),
  });

  const collectionRef = (path) => ({
    ...query(() => docsIn(store, path), blank),
    doc: (id) => docRef(`${path}/${id}`),
    path,
  });

  const db = () => ({
    collection: collectionRef,
    collectionGroup: (name) => query(() => docsInGroup(store, name), blank),
    batch: () => {
      const ops = [];
      return {
        delete: (ref) => ops.push(ref.path),
        set: (ref, data) => ops.push(() => { store[ref.path] = data; }),
        commit: async () => {
          for (const op of ops) {
            if (typeof op === 'function') op();
            else { delete store[op]; deleted.push(op); }
          }
        },
      };
    },
  });

  return { db, deleted };
}

module.exports = { fakeFirestore, FieldValueStub, FieldPathStub, snapshot };
