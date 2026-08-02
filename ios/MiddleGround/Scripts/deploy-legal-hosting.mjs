#!/usr/bin/env node
/**
 * Publishes docs/legal/*.html to Firebase Hosting without the Firebase CLI.
 *
 * The CLI is the normal way to do this. It is not installed here, and installing it was declined,
 * so this speaks the Hosting REST API directly using the CLI's stored refresh token — the same
 * credential Scripts/seed-review-data.mjs already uses.
 *
 * Why this matters enough to exist: App Store Connect's Privacy Policy URL and the review notes
 * pointed at two different hosts. When the policy changed to describe location sharing, only
 * seekmiddleground.com was rebuilt, so the Firebase copy went on claiming the app collects no
 * location while the App Privacy answers on file with Apple declared Coarse Location. A reviewer
 * following the link in the notes would have found the contradiction.
 *
 * The upload is a four-step handshake, not a POST: create a version (carrying the rewrite config,
 * or `/privacy` stops resolving), declare the gzipped SHA-256 of every file, PUT only the hashes
 * Firebase says it is missing, then finalize and release. `cleanUrls` and the two rewrites
 * are replicated from the live version rather than rebuilt from firebase.json, so this cannot
 * silently drop routing that firebase.json and the deployed version disagree about.
 *
 *   node Scripts/deploy-legal-hosting.mjs [--dry-run]
 *
 * Rolling back is a release, not a redeploy: POST releases?versionName=<older version>.
 */

import { readFileSync, readdirSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// The Firebase CLI's own OAuth client. These are public identifiers shipped inside the CLI, not
// secrets: the refresh token in the configstore is the credential, and it stays on this machine.
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';
const SITE = process.env.MG_HOSTING_SITE || 'middle-ground-8fd13';
const API = 'https://firebasehosting.googleapis.com/v1beta1';

const LEGAL = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', 'docs', 'legal');
const DRY = process.argv.includes('--dry-run');

/**
 * Replicated from the deployed version, not from firebase.json. `/privacy` and `/terms` are
 * rewrites rather than files — a version created without them serves 404 on both, which during an
 * App Review is worse than the stale page this script exists to replace.
 */
const CONFIG = {
  headers: [{ glob: '**/*.html', headers: { 'Cache-Control': 'public, max-age=3600' } }],
  rewrites: [
    { glob: '/privacy', path: '/privacy-policy.html' },
    { glob: '/terms', path: '/terms-of-service.html' },
  ],
  cleanUrls: true,
};

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

const call = (token) => async (method, url, body, raw) => {
  const res = await fetch(url.startsWith('http') ? url : `${API}${url}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(raw ? { 'Content-Type': 'application/octet-stream' } : body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: raw ?? (body ? JSON.stringify(body) : undefined),
  });
  if (!res.ok) throw new Error(`${method} ${url} → ${res.status} ${await res.text()}`);
  return res.status === 204 ? {} : res.json().catch(() => ({}));
};

async function main() {
  const api = call(await accessToken());

  // Hosting stores files gzipped and addresses them by the hash of the *compressed* bytes, so the
  // digest has to be taken after gzip, not before.
  const files = readdirSync(LEGAL)
    .filter((f) => f.endsWith('.html'))
    .map((name) => {
      const gz = gzipSync(readFileSync(join(LEGAL, name)), { level: 9 });
      return { path: `/${name}`, gz, hash: createHash('sha256').update(gz).digest('hex') };
    });

  console.log(`${files.length} files from docs/legal:`);
  for (const f of files) console.log(`  ${f.path.padEnd(26)} ${f.hash.slice(0, 12)}…`);
  if (DRY) return console.log('\n--dry-run: nothing uploaded.');

  const version = await api('POST', `/sites/${SITE}/versions`, { config: CONFIG });
  console.log(`\nversion ${version.name}`);

  const populate = await api('POST', `/${version.name}:populateFiles`, {
    files: Object.fromEntries(files.map((f) => [f.path, f.hash])),
  });

  // Only hashes Hosting does not already hold come back. An unchanged deploy uploads nothing.
  const required = new Set(populate.uploadRequiredHashes || []);
  console.log(`${required.size} of ${files.length} need uploading`);
  for (const f of files) {
    if (!required.has(f.hash)) continue;
    await api('PUT', `${populate.uploadUrl}/${f.hash}`, undefined, f.gz);
    console.log(`  uploaded ${f.path}`);
  }

  await api('PATCH', `/${version.name}?update_mask=status`, { status: 'FINALIZED' });
  await api('POST', `/sites/${SITE}/releases?versionName=${version.name}`);
  console.log(`\nreleased ${version.name}`);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
