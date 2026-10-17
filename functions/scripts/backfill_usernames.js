/**
 * One-off backfill for username uniqueness + substring search.
 *
 * For every users/{uid} doc:
 *   - sets `username_search` (all 2+ char substrings, see utils.usernameSubstrings)
 *   - creates the usernames/{username} claim → { uid } if the name is valid
 *     and held by exactly one user
 *
 * Duplicate or invalid usernames are reported and left unclaimed — those users
 * keep their name (rules allow an unchanged username) until someone renames.
 * Safe to re-run: unchanged search arrays and existing claims are skipped.
 *
 * DEFAULT = DRY RUN (prints what would change). Pass --commit to write.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=~/keys/jukebox-admin.json \
 *     node functions/scripts/backfill_usernames.js [--commit]
 */

"use strict";

const admin = require("firebase-admin");
const { usernameSubstrings } = require("../utils");

const PROJECT_ID = "jukebox-996de";
const COMMIT = process.argv.slice(2).includes("--commit");

// Keep in sync with isValidUsername in firestore.rules.
function isValidUsername(name) {
  return /^[a-z0-9_.]{3,20}$/.test(name) && !/^__.*__$/.test(name);
}

function sameArray(a, b) {
  return Array.isArray(a) && a.length === b.length && a.every((v, i) => v === b[i]);
}

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error(
    "ERROR: GOOGLE_APPLICATION_CREDENTIALS is not set.\n" +
    "Usage: GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node backfill_usernames.js [--commit]"
  );
  process.exit(1);
}

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

async function main() {
  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY RUN"}`);

  const users = await db.collection("users").get();
  const claims = await db.collection("usernames").get();
  const existingClaims = new Map(claims.docs.map((d) => [d.id, d.data().uid]));

  const byName = new Map();
  for (const doc of users.docs) {
    const name = String(doc.data().username || "").trim().toLowerCase();
    if (!name) continue;
    if (!byName.has(name)) byName.set(name, []);
    byName.get(name).push(doc.id);
  }

  const writes = []; // [ref, data]
  for (const doc of users.docs) {
    const wanted = usernameSubstrings(doc.data().username);
    if (!sameArray(doc.data().username_search, wanted)) {
      writes.push([doc.ref, { username_search: wanted }, "update"]);
    }
  }

  const duplicates = [];
  const invalid = [];
  for (const [name, uids] of byName) {
    if (!isValidUsername(name)) { invalid.push({ name, uids }); continue; }
    if (uids.length > 1)       { duplicates.push({ name, uids }); continue; }
    if (existingClaims.has(name)) {
      if (existingClaims.get(name) !== uids[0]) {
        duplicates.push({ name, uids: [...uids, `(claimed by ${existingClaims.get(name)})`] });
      }
      continue;
    }
    writes.push([db.collection("usernames").doc(name), { uid: uids[0] }, "create"]);
  }

  const searchUpdates = writes.filter((w) => w[2] === "update").length;
  const newClaims = writes.filter((w) => w[2] === "create").length;
  console.log(`Users scanned:            ${users.size}`);
  console.log(`username_search updates:  ${searchUpdates}`);
  console.log(`New username claims:      ${newClaims}`);
  console.log(`Duplicate names (skipped): ${duplicates.length}`);
  for (const d of duplicates) console.log(`  ${d.name}: ${d.uids.join(", ")}`);
  console.log(`Invalid names (skipped):   ${invalid.length}`);
  for (const d of invalid) console.log(`  "${d.name}": ${d.uids.join(", ")}`);

  if (!COMMIT) {
    console.log("\nDry run — nothing written. Re-run with --commit to apply.");
    return;
  }

  for (let i = 0; i < writes.length; i += 500) {
    const batch = db.batch();
    for (const [ref, data, kind] of writes.slice(i, i + 500)) {
      if (kind === "create") batch.create(ref, data);
      else batch.update(ref, data);
    }
    await batch.commit();
  }
  console.log(`\nCommitted ${writes.length} writes.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
