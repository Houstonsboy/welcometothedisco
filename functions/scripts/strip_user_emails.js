/**
 * One-off cleanup: removes the `email` field from every users/{uid} doc.
 *
 * Profile docs are readable (and listable) by any signed-in user, so an email
 * stored there was visible to everyone. Firebase Auth already holds each
 * user's email, and the app now reads it from there for the signed-in user
 * only. firestore.rules rejects any write that sets `email` again.
 *
 * Safe to re-run: docs without an `email` field are skipped.
 *
 * DEFAULT = DRY RUN (prints what would change). Pass --commit to write.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=~/keys/jukebox-admin.json \
 *     node functions/scripts/strip_user_emails.js [--commit]
 */

"use strict";

const admin = require("firebase-admin");
const { FieldValue } = require("firebase-admin/firestore");

const PROJECT_ID = "jukebox-996de";
const COMMIT = process.argv.slice(2).includes("--commit");

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error(
    "ERROR: GOOGLE_APPLICATION_CREDENTIALS is not set.\n" +
    "Usage: GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node strip_user_emails.js [--commit]"
  );
  process.exit(1);
}

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

async function main() {
  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY RUN"}`);

  const users = await db.collection("users").get();
  const refs = users.docs.filter((d) => d.get("email") !== undefined).map((d) => d.ref);

  console.log(`Users scanned:        ${users.size}`);
  console.log(`Docs with an email:   ${refs.length}`);

  if (!COMMIT) {
    console.log("\nDry run — nothing written. Re-run with --commit to apply.");
    return;
  }

  for (let i = 0; i < refs.length; i += 500) {
    const batch = db.batch();
    for (const ref of refs.slice(i, i + 500)) {
      batch.update(ref, { email: FieldValue.delete() });
    }
    await batch.commit();
  }
  console.log(`\nRemoved email from ${refs.length} docs.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
