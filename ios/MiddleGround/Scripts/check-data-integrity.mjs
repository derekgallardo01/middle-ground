#!/usr/bin/env node
/**
 * Looks for data that contradicts itself: references to people and plans that no longer exist.
 *
 * Firestore has no foreign keys, so nothing prevents a relationship listing a participant whose
 * account is gone, or a token document outliving its owner. The deletion cascade is what keeps
 * these consistent, and the only way to know it is working is to go and look — a cascade that
 * quietly misses a collection leaves exactly this trail.
 *
 * Read-only.
 *
 *   node Scripts/check-data-integrity.mjs
 */

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const PROJECT = process.env.MG_FIREBASE_PROJECT || 'middle-ground-8fd13';
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

const cfg = JSON.parse(readFileSync(`${homedir()}/.config/configstore/firebase-tools.json`, 'utf8'));
const auth = await (await fetch('https://oauth2.googleapis.com/token', {
  method: 'POST',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET,
    refresh_token: cfg.tokens.refresh_token,
    grant_type: 'refresh_token',
  }),
})).json();
const token = auth.access_token;

async function all(collectionId, allDescendants = false) {
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:runQuery`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ structuredQuery: { from: [{ collectionId, allDescendants }], limit: 300 } }),
    }
  );
  const json = await res.json();
  return (Array.isArray(json) ? json : []).filter((r) => r.document).map((r) => ({
    id: r.document.name.split('/').pop(),
    path: r.document.name.split('/documents/')[1],
    f: r.document.fields || {},
  }));
}

const strings = (field) => (field?.arrayValue?.values ?? []).map((v) => v.stringValue);

const [users, requests, relationships, invites, tokens, settings, gamification] = await Promise.all([
  all('users'), all('requests'), all('relationships'), all('invites'),
  all('user_tokens'), all('notification_settings'), all('gamification'),
]);

const known = new Set(users.map((u) => u.id));
const problems = [];

for (const r of requests) {
  for (const id of strings(r.f.allParticipantIDs)) {
    if (!known.has(id)) problems.push(`request ${r.id}: participant ${id} has no user document`);
  }
  if (strings(r.f.allParticipantIDs).length === 0) {
    problems.push(`request ${r.id}: no participants at all`);
  }
}
for (const rel of relationships) {
  for (const id of strings(rel.f.participantIDs)) {
    if (!known.has(id)) problems.push(`relationship ${rel.id}: participant ${id} has no user document`);
  }
}
// A code pointing at a group that is gone sends whoever redeems it nowhere.
const groupIds = new Set(relationships.map((r) => r.id));
for (const invite of invites) {
  const target = invite.f.relationshipID?.stringValue;
  if (target && !groupIds.has(target)) {
    problems.push(`invite ${invite.id}: points at relationship ${target}, which does not exist`);
  }
}
// Per-user documents whose owner is gone — the shape a missed cascade leaves behind.
for (const [label, docs] of [['user_tokens', tokens], ['notification_settings', settings], ['gamification', gamification]]) {
  for (const d of docs) {
    if (!known.has(d.id)) problems.push(`${label}/${d.id}: no such user`);
  }
}

console.log(`users ${users.length} · requests ${requests.length} · relationships ${relationships.length} `
  + `· invites ${invites.length}\n`);
if (problems.length === 0) {
  console.log('✓ No dangling references found.');
} else {
  console.log(`${problems.length} problem(s):`);
  for (const p of problems) console.log(`  ✗ ${p}`);
}
