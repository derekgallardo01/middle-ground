const { Resend } = require('resend');

/**
 * Operator alerts.
 *
 * These go to ONE inbox — the person running the service — never to users. There is no
 * unsubscribe, no marketing, and no user-facing transactional mail here; adding any of that
 * would bring CAN-SPAM/GDPR obligations this deliberately avoids.
 *
 * Configuration comes from Cloud Functions secrets/params rather than an env file, so the API
 * key never lands in the repo or in a deployed config document:
 *
 *   firebase functions:secrets:set RESEND_API_KEY
 *   firebase functions:config  -- no; params are set via .env for non-secret values:
 *     CloudFunctions/.env  ->  OPERATOR_EMAIL=you@example.com
 *                              ALERT_FROM=alerts@send.middleground.app
 *
 * `.env` is gitignored. ALERT_FROM must be on a domain verified in Resend, otherwise every
 * send is rejected. Note middleground.app publishes `v=spf1 -all` at the root, which forbids
 * all mail from the bare domain — use a subdomain with its own SPF/DKIM.
 */

const FROM = process.env.ALERT_FROM || 'onboarding@resend.dev';
const TO = process.env.OPERATOR_EMAIL || '';

/**
 * Sends one alert. Never throws.
 *
 * A failed alert must not fail the trigger that produced it — an email outage must not roll
 * back a user's signup or block a deletion cascade. Same fire-and-forget discipline as the
 * analytics writes in AnalyticsService.
 */
async function sendAlert(subject, lines) {
  const apiKey = process.env.RESEND_API_KEY;

  if (!apiKey || !TO) {
    // Not configured is a normal state (e.g. the emulator), not an error worth alarming on.
    console.log(`[alert skipped — not configured] ${subject}`);
    return;
  }

  const body = lines.filter(Boolean).join('\n');
  try {
    const { error } = await new Resend(apiKey).emails.send({
      from: FROM,
      to: TO,
      subject: `[Middle Ground] ${subject}`,
      text: body,
    });
    // The SDK reports delivery failures in `error` rather than throwing, so checking only
    // for exceptions would report success on a rejected send.
    if (error) {
      console.error(`Alert "${subject}" rejected:`, error.message || error);
    } else {
      console.log(`Alert sent: ${subject}`);
    }
  } catch (err) {
    console.error(`Alert "${subject}" failed:`, err.message);
  }
}

/** Formats a timestamp-ish value from Firestore for a plain-text email. */
function when(value) {
  try {
    if (!value) return 'unknown';
    const d = typeof value.toDate === 'function' ? value.toDate() : new Date(value);
    return d.toISOString().replace('T', ' ').slice(0, 19) + ' UTC';
  } catch {
    return 'unknown';
  }
}

module.exports = { sendAlert, when };
