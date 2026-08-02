#!/usr/bin/env node
/**
 * Uploads App Store screenshots to the current version's en-US listing.
 *
 * Apple's screenshot upload is a three-step handshake, not a plain POST: reserve the asset to
 * get a set of signed upload operations, PUT each chunk exactly where it says, then commit with
 * an MD5 so Apple can verify what landed. Skipping the commit leaves the asset stuck in
 * UPLOAD_COMPLETE and it never appears on the listing.
 *
 * Produce the PNGs first with Scripts/screenshots.sh.
 *
 *   node Scripts/upload-screenshots.mjs [dir]
 *
 * Requires the App Store Connect API key at ~/.appstoreconnect/private_keys/AuthKey_<id>.p8.
 */

import { sign as cryptoSign, createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { homedir } from 'node:os';

const KEY_ID = process.env.MG_ASC_KEY_ID || 'T79AHBMV3J';
const ISSUER = process.env.MG_ASC_ISSUER || '7080ef6c-0e05-48e7-b508-72b9259dff45';
const KEY_PATH = process.env.MG_ASC_KEY_PATH
  || `${homedir()}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`;
const APP = process.env.MG_ASC_APP_ID || '6796479061';
const DIR = process.argv[2] || `${homedir()}/Desktop/MiddleGround-Screenshots`;

/** 1320x2868 is the 6.9" iPhone size; App Store Connect accepts it in the 6.7" slot. */
const DISPLAY_TYPE = 'APP_IPHONE_67';

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

async function api(path, method = 'GET', body) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method,
    headers: { Authorization: `Bearer ${jwt()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json; try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
  return { status: res.status, json };
}

const ver = await api(`/v1/apps/${APP}/appStoreVersions?limit=1`);
const version = ver.json.data?.[0];
if (!version) throw new Error('no app store version found');

const locs = await api(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations`);
const loc = locs.json.data.find((x) => x.attributes.locale === 'en-US') || locs.json.data[0];

const sets = await api(`/v1/appStoreVersionLocalizations/${loc.id}/appScreenshotSets`);
let set = (sets.json.data || []).find((s) => s.attributes.screenshotDisplayType === DISPLAY_TYPE);
if (!set) {
  const created = await api('/v1/appScreenshotSets', 'POST', {
    data: {
      type: 'appScreenshotSets',
      attributes: { screenshotDisplayType: DISPLAY_TYPE },
      relationships: {
        appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: loc.id } },
      },
    },
  });
  if (created.status !== 201) {
    throw new Error(`could not create screenshot set: ${JSON.stringify(created.json.errors)}`);
  }
  set = created.json.data;
}
console.log(`screenshot set ${set.id} (${DISPLAY_TYPE})`);

// Replace rather than append — re-running should not stack duplicates on the listing.
const existing = await api(`/v1/appScreenshotSets/${set.id}/appScreenshots`);
for (const old of existing.json.data || []) {
  await api(`/v1/appScreenshots/${old.id}`, 'DELETE');
}

for (const name of readdirSync(DIR).filter((f) => f.endsWith('.png')).sort()) {
  const bytes = readFileSync(`${DIR}/${name}`);

  const reserved = await api('/v1/appScreenshots', 'POST', {
    data: {
      type: 'appScreenshots',
      attributes: { fileName: name, fileSize: bytes.length },
      relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set.id } } },
    },
  });
  if (reserved.status !== 201) {
    console.log(`  ${name}: reserve failed ${reserved.status}`,
      JSON.stringify(reserved.json.errors).slice(0, 200));
    continue;
  }
  const shot = reserved.json.data;

  for (const op of shot.attributes.uploadOperations) {
    const headers = Object.fromEntries((op.requestHeaders || []).map((h) => [h.name, h.value]));
    const put = await fetch(op.url, {
      method: op.method,
      headers,
      body: bytes.subarray(op.offset, op.offset + op.length),
    });
    if (!put.ok) console.log(`  ${name}: chunk failed ${put.status}`);
  }

  const committed = await api(`/v1/appScreenshots/${shot.id}`, 'PATCH', {
    data: {
      type: 'appScreenshots',
      id: shot.id,
      attributes: {
        uploaded: true,
        sourceFileChecksum: createHash('md5').update(bytes).digest('hex'),
      },
    },
  });
  console.log(`  ${name}: ${committed.status === 200 ? 'uploaded' : `commit failed ${committed.status}`}`);
}

const final = await api(`/v1/appScreenshotSets/${set.id}/appScreenshots`);
console.log(`\nin set: ${(final.json.data || []).length}`);
for (const s of final.json.data || []) {
  console.log(`  ${s.attributes.fileName}  ${s.attributes.assetDeliveryState?.state}`);
}
