/**
 * Operator alerts when nothing is configured.
 *
 * Its own file because `alerts.js` reads `OPERATOR_EMAIL` and `RESEND_API_KEY` into module
 * constants at load time. Toggling them inside `handlers.test.js` after the module is already
 * loaded proves nothing — the values are captured. `node --test` runs each file in its own
 * process, which is what makes "never set" expressible at all.
 *
 * Worth pinning because unconfigured is the normal state in the emulator and in CI: if this path
 * threw, every trigger that alerts would fail alongside the alert.
 */
const { test, describe } = require('node:test');
const assert = require('node:assert');

delete process.env.RESEND_API_KEY;
delete process.env.OPERATOR_EMAIL;

let sends = 0;
const resendPath = require.resolve('resend');
require.cache[resendPath] = {
  id: resendPath,
  filename: resendPath,
  loaded: true,
  exports: {
    Resend: class {
      get emails() {
        return { send: async () => { sends += 1; return { error: null }; } };
      }
    },
  },
};

const { sendAlert } = require('../alerts');

describe('alerts with nothing configured', () => {
  test('sends nothing and does not throw', async () => {
    await assert.doesNotReject(sendAlert('New signup', ['Alex', 'just now']));
    assert.equal(sends, 0, 'no operator address means no mail, not a failed send');
  });

  test('tolerates empty and missing lines', async () => {
    await assert.doesNotReject(sendAlert('Subject', [null, '', undefined]));
    assert.equal(sends, 0);
  });
});
