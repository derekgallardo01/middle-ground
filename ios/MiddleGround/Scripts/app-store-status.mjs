#!/usr/bin/env node
/**
 * Where the submission stands, and which builds TestFlight has finished processing.
 *
 * Both answers are needed before a device pass and neither is knowable from the repo: a build
 * that has uploaded is not yet a build anybody can install, and "still in review" versus
 * "approved" changes what it is safe to ship next.
 *
 * Read-only. Requires the App Store Connect API key at
 * ~/.appstoreconnect/private_keys/AuthKey_<id>.p8 — the same one Scripts/upload-screenshots.mjs
 * uses.
 *
 *   node Scripts/app-store-status.mjs
 */

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { sign as cryptoSign } from 'node:crypto';

const KEY_ID = process.env.MG_ASC_KEY_ID || 'T79AHBMV3J';
const ISSUER = process.env.MG_ASC_ISSUER || '7080ef6c-0e05-48e7-b508-72b9259dff45';
const KEY_PATH = process.env.MG_ASC_KEY_PATH
  || `${homedir()}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`;
const BUNDLE_ID = 'app.middleground.MiddleGround';

const b64 = (o) => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');

function jwt() {
  const now = Math.floor(Date.now() / 1000);
  const input = `${b64({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' })}.${b64({
    iss: ISSUER, iat: now, exp: now + 600, aud: 'appstoreconnect-v1',
  })}`;
  const sig = cryptoSign('sha256', Buffer.from(input), {
    key: readFileSync(KEY_PATH, 'utf8'),
    dsaEncoding: 'ieee-p1363',
  }).toString('base64url');
  return `${input}.${sig}`;
}

async function api(path) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    headers: { Authorization: `Bearer ${jwt()}` },
  });
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text.slice(0, 300) };
  }
}

const apps = await api(`/v1/apps?filter[bundleId]=${BUNDLE_ID}`);
const app = apps.data?.[0];
if (!app) {
  console.log('No app found. Response:', JSON.stringify(apps).slice(0, 300));
  process.exit(1);
}
console.log(`${app.attributes.name}  (${app.id})\n`);

const versions = await api(`/v1/apps/${app.id}/appStoreVersions?limit=5`);
console.log('App Store versions:');
for (const v of versions.data ?? []) {
  const a = v.attributes;
  console.log(`  ${a.versionString.padEnd(8)} ${a.appStoreState}   platform ${a.platform}`);
}

// Processing state is what decides whether a build is installable. An uploaded build sits in
// PROCESSING for a while and simply does not appear in TestFlight until it is VALID.
const builds = await api(`/v1/builds?filter[app]=${app.id}&limit=8&sort=-uploadedDate`);
console.log('\nBuilds, newest first:');
for (const b of builds.data ?? []) {
  const a = b.attributes;
  const expired = a.expired ? '  EXPIRED' : '';
  console.log(
    `  ${String(a.version).padEnd(14)} ${String(a.processingState).padEnd(12)}` +
    ` uploaded ${a.uploadedDate}${expired}`
  );
}
