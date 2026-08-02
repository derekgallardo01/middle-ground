#!/usr/bin/env node
/**
 * Grants or revokes the `admin` custom claim on a Firebase user.
 *
 * The claim is what `firestore.rules` checks (`request.auth.token.admin == true`) and what the
 * app reads from the ID token to decide whether to show the Admin tab. It can only be set
 * server-side, which is exactly why it is trustworthy: an admin flag the client could set would
 * be worthless in a shipped binary.
 *
 * Reuses the Firebase CLI's existing OAuth session, so no service-account key is needed.
 * Requires `firebase login` to have been run.
 *
 *   node Scripts/grant-admin.mjs <email>            # grant
 *   node Scripts/grant-admin.mjs <email> --revoke   # revoke
 *   node Scripts/grant-admin.mjs --list             # show current admins
 *
 * After a change the user must get a fresh ID token. The app forces a refresh on launch
 * (`AuthService.isAdmin`), so signing out and back in — or relaunching — is enough.
 */

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const PROJECT = 'middle-ground-8fd13';
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

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

const api = (token) => async (path, body) => {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/${path}`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }
  );
  const json = await res.json();
  if (json.error) throw new Error(`${path}: ${json.error.message}`);
  return json;
};

async function main() {
  const args = process.argv.slice(2);
  const token = await accessToken();
  const call = api(token);

  if (args.includes('--list')) {
    // accounts:query returns identities but NOT customAttributes, so the claim has to be
    // fetched with a follow-up lookup. Filtering on the query result alone silently reports
    // "no admins" even when admins exist.
    const { userInfo = [] } = await call('accounts:query', { returnUserInfo: true });
    const ids = userInfo.map((u) => u.localId).filter(Boolean);
    if (!ids.length) {
      console.log('No users in this project yet.');
      return;
    }

    const admins = [];
    for (let i = 0; i < ids.length; i += 100) {
      const { users = [] } = await call('accounts:lookup', { localId: ids.slice(i, i + 100) });
      for (const user of users) {
        try {
          if (JSON.parse(user.customAttributes || '{}').admin === true) admins.push(user);
        } catch {
          // Malformed attributes on one account must not hide the rest.
        }
      }
    }

    console.log(admins.length ? 'Admins:' : 'No admins are configured.');
    admins.forEach((u) => console.log(`  ${u.email || '(no email)'}  ${u.localId}`));
    return;
  }

  const email = args[0];
  const revoke = args.includes('--revoke');
  if (!email) {
    console.error('Usage: node Scripts/grant-admin.mjs <email> [--revoke] | --list');
    process.exit(1);
  }

  const { users = [] } = await call('accounts:lookup', { email: [email] });
  const user = users[0];
  if (!user) throw new Error(`No user with email ${email}. They must sign in at least once.`);

  // Preserve any other claims rather than clobbering the whole attribute blob.
  const claims = JSON.parse(user.customAttributes || '{}');
  if (revoke) {
    delete claims.admin;
  } else {
    claims.admin = true;
  }

  await call('accounts:update', {
    localId: user.localId,
    customAttributes: JSON.stringify(claims),
  });

  console.log(`${revoke ? 'Revoked' : 'Granted'} admin for ${email} (${user.localId})`);
  console.log('They need a fresh ID token — relaunching the app is enough.');
}

main().catch((error) => {
  console.error(`Failed: ${error.message}`);
  process.exit(1);
});
