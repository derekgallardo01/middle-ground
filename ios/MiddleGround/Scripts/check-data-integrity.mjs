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

const [users, requests, relationships, invites, tokens, settings, gamification, itinerary] =
  await Promise.all([
    all('users'), all('requests'), all('relationships'), all('invites'),
    all('user_tokens'), all('notification_settings'), all('gamification'),
    // Collection-group: itinerary items live under every trip, including ones somebody else
    // owns, so there is no other way to find them all.
    all('itinerary', true),
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
// Trips: a range that runs backwards, and a clock nobody has heard of.
//
// Both are tolerated by the client on purpose — `isMultiDay` treats a backwards end as the typo it
// is, and an unknown zone falls back to the reader's clock rather than throwing. That tolerance is
// correct and it is also why neither would ever surface as an error. This is where they surface.
const zones = new Set(Intl.supportedValuesOf('timeZone'));
for (const r of requests) {
  const start = r.f.proposedTime?.timestampValue;
  const end = r.f.endTime?.timestampValue;
  if (start && end && Date.parse(end) <= Date.parse(start)) {
    problems.push(`request ${r.id}: endTime ${end} is not after proposedTime ${start}`);
  }
  if (end && !start) {
    problems.push(`request ${r.id}: has an endTime but no proposedTime`);
  }
  const zone = r.f.timeZoneID?.stringValue;
  if (zone && !zones.has(zone)) {
    problems.push(`request ${r.id}: timeZoneID "${zone}" is not a zone this runtime knows`);
  }
}

// Itinerary items whose author is gone — the shape a missed cascade leaves behind, and the reason
// `purgeItinerary` exists. A subcollection is not deleted with its parent, so without both the
// sweep and this check an item outlives the account that wrote it and, often, the trip itself.
for (const item of itinerary) {
  const author = item.f.authorID?.stringValue;
  if (author && !known.has(author)) {
    problems.push(`itinerary ${item.path}: author ${author} has no user document`);
  }
  if (!author) {
    problems.push(`itinerary ${item.path}: no author at all`);
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
  + `· invites ${invites.length} · itinerary ${itinerary.length}\n`);
if (problems.length === 0) {
  console.log('✓ No dangling references found.');
} else {
  console.log(`${problems.length} problem(s):`);
  for (const p of problems) console.log(`  ✗ ${p}`);
}
