/**
 * `FieldValue` and `FieldPath` stand-ins.
 *
 * Real sentinels are opaque objects the server interprets. The fake has to interpret them itself,
 * so they are tagged and applied on write — otherwise `arrayRemove` would be stored verbatim and
 * a token-pruning test would pass while pruning nothing.
 */

const SENTINEL = Symbol.for('mg.fake.sentinel');

const FieldValueStub = {
  arrayUnion: (...values) => ({ [SENTINEL]: 'arrayUnion', values }),
  arrayRemove: (...values) => ({ [SENTINEL]: 'arrayRemove', values }),
  delete: () => ({ [SENTINEL]: 'delete' }),
  serverTimestamp: () => ({ [SENTINEL]: 'serverTimestamp' }),
};

const FieldPathStub = {
  documentId: () => '__name__',
};

/** Folds a write into existing data, resolving any sentinels against what is already there. */
function applyFieldValues(existing, incoming) {
  const result = { ...existing };
  for (const [key, value] of Object.entries(incoming)) {
    const kind = value && value[SENTINEL];
    if (!kind) {
      result[key] = value;
      continue;
    }
    const current = Array.isArray(result[key]) ? result[key] : [];
    if (kind === 'arrayUnion') {
      result[key] = [...current, ...value.values.filter((v) => !current.includes(v))];
    } else if (kind === 'arrayRemove') {
      result[key] = current.filter((v) => !value.values.includes(v));
    } else if (kind === 'delete') {
      delete result[key];
    } else if (kind === 'serverTimestamp') {
      result[key] = new Date(0);
    }
  }
  return result;
}

module.exports = { FieldValueStub, FieldPathStub, applyFieldValues };
