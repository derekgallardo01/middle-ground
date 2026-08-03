#!/usr/bin/env node
/**
 * Deploys firestore.rules without the Firebase CLI, which is not installed here.
 *
 * Two steps, not one: a ruleset is created (and compiled server-side, so a syntax error fails
 * here rather than silently), then the `cloud.firestore` release is pointed at it. Until that
 * second call the new ruleset exists and governs nothing.
 *
 *   node Scripts/deploy-firestore-rules.mjs [--dry-run]
 *
 * `--dry-run` creates the ruleset — which is how you find out it compiles — and stops before
 * releasing it. Rulesets are cheap and unreferenced ones are ignored.
 *
 * Rolling back is another release, not another deploy: the previous ruleset ID is printed on
 * every run, and pointing the release back at it is instant. Keep that ID.
 *
 * A rules deploy takes effect immediately for every client, including builds already in the wild
 * and anyone mid-review. Deploy additions freely; check what a *removal* would do to the version
 * currently in App Review before running it.
 */

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';
const PROJECT = process.env.MG_FIREBASE_PROJECT || 'middle-ground-8fd13';
const API = 'https://firebaserules.googleapis.com/v1';

const RULES = join(dirname(fileURLToPath(import.meta.url)), '..', 'firestore.rules');
const DRY = process.argv.includes('--dry-run');

async function accessToken() {
  const cfgPath = `${homedir()}/.config/configstore/firebase-tools.json`;
  let refreshToken;
  try {
    refreshToken = JSON.parse(readFileSync(cfgPath, 'utf8')).tokens?.refresh_token;
  } catch {
    throw new Error('Could not read the Firebase CLI session. Run `firebase login` first.');
  }
  if (!refreshToken) throw new Error('No Firebase CLI session found. Run `firebase login`.');

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error(`Token refresh failed: ${JSON.stringify(json)}`);
  return json.access_token;
}

const call = (token) => async (method, url, body) => {
  const res = await fetch(url.startsWith('http') ? url : `${API}${url}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new Error(`${method} ${url} → ${res.status} ${await res.text()}`);
  return res.json();
};

async function main() {
  const api = call(await accessToken());
  const source = readFileSync(RULES, 'utf8');
  console.log(`firestore.rules — ${source.split('\n').length} lines`);

  const releasePath = `projects/${PROJECT}/releases/cloud.firestore`;
  const current = await api('GET', `/${releasePath}`);
  console.log(`current ruleset  ${current.rulesetName.split('/').pop()}   <-- roll back to this`);

  const ruleset = await api('POST', `/projects/${PROJECT}/rulesets`, {
    source: { files: [{ name: 'firestore.rules', content: source }] },
  });
  const id = ruleset.name.split('/').pop();
  console.log(`created ruleset  ${id}  (compiled clean)`);

  if (DRY) return console.log('\n--dry-run: created but not released. Nothing is live yet.');

  await api('PATCH', `/${releasePath}`, {
    release: { name: releasePath, rulesetName: ruleset.name },
  });
  console.log(`released         ${id}`);

  const after = await api('GET', `/${releasePath}`);
  const live = after.rulesetName.split('/').pop();
  console.log(live === id ? '\nverified live.' : `\n*** MISMATCH: live is ${live} ***`);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
