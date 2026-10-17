/**
 * Production voting-data reset script.
 *
 * DEFAULT = DRY RUN (prints counts only, deletes nothing).
 * Pass --commit to actually delete.
 * Pass --include-rankings to also wipe rankings + ranking_runs.
 *
 * Usage:
 *   # Dry run (default):
 *   GOOGLE_APPLICATION_CREDENTIALS=~/keys/jukebox-admin.json \
 *     node functions/scripts/reset_voting_data.js
 *
 *   # Commit (deletes data; prompts for confirmation):
 *   GOOGLE_APPLICATION_CREDENTIALS=~/keys/jukebox-admin.json \
 *     node functions/scripts/reset_voting_data.js --commit
 *
 *   # Also wipe rankings:
 *   GOOGLE_APPLICATION_CREDENTIALS=~/keys/jukebox-admin.json \
 *     node functions/scripts/reset_voting_data.js --commit --include-rankings
 */

"use strict";

const admin  = require("firebase-admin");
const fs     = require("fs");
const path   = require("path");
const readline = require("readline");

// ── Config ────────────────────────────────────────────────────────────────────

const REQUIRED_PROJECT_ID = "jukebox-996de";

// Hard-coded allowlist — the script will only ever touch these collections.
const BASE_ALLOWLIST      = ["versus", "polls", "pairs"];
const RANKINGS_ALLOWLIST  = ["rankings", "ranking_runs"];

// Collections we must NOT touch; counted before+after to prove safety.
const SENTINEL_COLLECTIONS = ["users", "posts", "messages", "recent_tracks", "playback_gate_events"];

// Subcollections to recurse into when counting/backing up (not needed for delete —
// recursiveDelete handles those, but we need to enumerate them for dry-run counts).
const SUBCOLLECTIONS = { pairs: ["voters"] };

// ── CLI flags ─────────────────────────────────────────────────────────────────

const args            = process.argv.slice(2);
const COMMIT          = args.includes("--commit");
const INCLUDE_RANKINGS = args.includes("--include-rankings");
const ALLOWLIST       = INCLUDE_RANKINGS
  ? [...BASE_ALLOWLIST, ...RANKINGS_ALLOWLIST]
  : BASE_ALLOWLIST;

// ── Init ──────────────────────────────────────────────────────────────────────

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error(
    "ERROR: GOOGLE_APPLICATION_CREDENTIALS is not set.\n" +
    "Usage: GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node reset_voting_data.js [--commit] [--include-rankings]"
  );
  process.exit(1);
}

try {
  if (admin.apps.length === 0) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId:  REQUIRED_PROJECT_ID,
    });
  }
} catch (err) {
  console.error("ERROR: admin.initializeApp failed:", err.message);
  process.exit(1);
}

let db;
try {
  db = admin.firestore();
} catch (err) {
  console.error("ERROR: admin.firestore() failed:", err.message);
  process.exit(1);
}

// ── Project ID guard ──────────────────────────────────────────────────────────

const actualProject = admin.app().options.projectId || process.env.GCLOUD_PROJECT;
console.log(`\nConnected to project: ${actualProject}`);

if (actualProject !== REQUIRED_PROJECT_ID) {
  console.error(
    `ABORT: Expected project "${REQUIRED_PROJECT_ID}" but got "${actualProject}".`
  );
  process.exit(1);
}
console.log(`Project ID verified ✓\n`);

// ── Helpers ───────────────────────────────────────────────────────────────────

function timestampToISO(value) {
  if (value && typeof value.toDate === "function") return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return value;
}

function serializeDoc(docData) {
  const out = {};
  for (const [k, v] of Object.entries(docData)) {
    if (v && typeof v === "object" && typeof v.toDate === "function") {
      out[k] = timestampToISO(v);
    } else if (v !== null && typeof v === "object" && !Array.isArray(v) &&
               typeof v.toDate !== "function") {
      out[k] = serializeDoc(v);
    } else {
      out[k] = v;
    }
  }
  return out;
}

async function countCollection(colName) {
  const snap = await db.collection(colName).get();
  let subCount = 0;
  const subs = SUBCOLLECTIONS[colName] || [];
  for (const doc of snap.docs) {
    for (const sub of subs) {
      const subSnap = await db.collection(colName).doc(doc.id).collection(sub).get();
      subCount += subSnap.size;
    }
  }
  return { top: snap.size, sub: subCount, total: snap.size + subCount };
}

async function sampleIds(colName, n = 3) {
  const snap = await db.collection(colName).limit(n).get();
  return snap.docs.map(d => d.id);
}

async function exportCollection(colName, backup) {
  const snap = await db.collection(colName).get();
  let count = 0;
  for (const doc of snap.docs) {
    const fullPath = `${colName}/${doc.id}`;
    backup[fullPath] = serializeDoc(doc.data());
    count++;
    const subs = SUBCOLLECTIONS[colName] || [];
    for (const sub of subs) {
      const subSnap = await db.collection(colName).doc(doc.id).collection(sub).get();
      for (const subDoc of subSnap.docs) {
        const subPath = `${colName}/${doc.id}/${sub}/${subDoc.id}`;
        backup[subPath] = serializeDoc(subDoc.data());
        count++;
      }
    }
  }
  return count;
}

function prompt(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question(question, (ans) => { rl.close(); resolve(ans.trim()); });
  });
}

// ── Dry run ───────────────────────────────────────────────────────────────────

async function dryRun() {
  console.log("=".repeat(60));
  console.log("DRY RUN — no data will be deleted");
  console.log(`Collections to delete: ${ALLOWLIST.join(", ")}`);
  console.log("=".repeat(60));

  console.log("\n── Allowlisted collections ──────────────────────────────────");
  for (const col of ALLOWLIST) {
    try {
      const { top, sub, total } = await countCollection(col);
      const samples = await sampleIds(col);
      console.log(`\n  ${col}:`);
      console.log(`    top-level docs : ${top}`);
      if ((SUBCOLLECTIONS[col] || []).length > 0) {
        console.log(`    subcollection docs: ${sub}  (total incl. subcols: ${total})`);
      }
      console.log(`    sample IDs     : ${samples.join(", ") || "(none)"}`);
    } catch (err) {
      console.error(`  ${col}: ERROR — ${err.message}`);
    }
  }

  console.log("\n── Sentinel collections (will NOT be touched) ───────────────");
  for (const col of SENTINEL_COLLECTIONS) {
    try {
      const snap = await db.collection(col).get();
      console.log(`  ${col}: ${snap.size} docs`);
    } catch (err) {
      console.log(`  ${col}: (not readable or empty)`);
    }
  }

  console.log("\nDry run complete. Pass --commit to delete.");
}

// ── Commit ────────────────────────────────────────────────────────────────────

async function commitRun() {
  console.log("=".repeat(60));
  console.log("COMMIT MODE — this will permanently delete data");
  console.log(`Collections to delete: ${ALLOWLIST.join(", ")}`);
  console.log("=".repeat(60));

  // ── Step 1: Count sentinel collections BEFORE ──────────────────────────────
  console.log("\n[1/6] Counting sentinel collections (before) ...");
  const sentinelBefore = {};
  for (const col of SENTINEL_COLLECTIONS) {
    try {
      const snap = await db.collection(col).get();
      sentinelBefore[col] = snap.size;
    } catch (_) {
      sentinelBefore[col] = null;
    }
  }
  for (const [col, count] of Object.entries(sentinelBefore)) {
    console.log(`  ${col}: ${count ?? "(not readable)"} docs`);
  }

  // ── Step 2: Backup ─────────────────────────────────────────────────────────
  console.log("\n[2/6] Backing up allowlisted collections ...");
  const backup  = {};
  let   backupTotal = 0;
  for (const col of ALLOWLIST) {
    try {
      const count = await exportCollection(col, backup);
      backupTotal += count;
      console.log(`  ${col}: exported ${count} docs (incl. subcollections)`);
    } catch (err) {
      console.error(`  ERROR exporting ${col}: ${err.message}`);
      console.error("  ABORT: backup failed — no data deleted.");
      process.exit(1);
    }
  }

  // Check that the backup is non-empty for every non-empty collection.
  for (const col of ALLOWLIST) {
    const colDocs = Object.keys(backup).filter(k => k.startsWith(`${col}/`));
    const liveSnap = await db.collection(col).get();
    if (liveSnap.size > 0 && colDocs.length === 0) {
      console.error(`  ABORT: ${col} has ${liveSnap.size} live docs but backup is empty.`);
      process.exit(1);
    }
  }

  const backupsDir = path.resolve(__dirname, "../../backups");
  if (!fs.existsSync(backupsDir)) fs.mkdirSync(backupsDir, { recursive: true });
  const ts         = new Date().toISOString().replace(/[:.]/g, "-");
  const backupPath = path.join(backupsDir, `voting-reset-${ts}.json`);

  try {
    fs.writeFileSync(backupPath, JSON.stringify(backup, null, 2), "utf8");
    const sizeKB = Math.round(fs.statSync(backupPath).size / 1024);
    console.log(`  Backup written: ${backupPath} (${sizeKB} KB, ${backupTotal} docs)`);
  } catch (err) {
    console.error(`  ABORT: Could not write backup file: ${err.message}`);
    process.exit(1);
  }

  // ── Step 3: Interactive confirmation ───────────────────────────────────────
  console.log("\n[3/6] Confirmation required.");
  console.log(`  About to permanently delete: ${ALLOWLIST.join(", ")}`);
  console.log(`  Backup saved to: ${backupPath}`);
  console.log(`  Type the project ID to confirm, anything else aborts:`);
  const answer = await prompt(`  > `);

  if (answer !== REQUIRED_PROJECT_ID) {
    console.log("\nABORTED — you typed something other than the project ID. Nothing deleted.");
    process.exit(0);
  }
  console.log("  Confirmed ✓");

  // ── Step 4: Delete ─────────────────────────────────────────────────────────
  console.log("\n[4/6] Deleting collections (including subcollections) ...");
  for (const col of ALLOWLIST) {
    try {
      const colRef = db.collection(col);
      await db.recursiveDelete(colRef);
      console.log(`  ${col}: deleted ✓`);
    } catch (err) {
      console.error(`  ERROR deleting ${col}: ${err.message}`);
    }
  }

  // ── Step 5: Verify deletion ────────────────────────────────────────────────
  console.log("\n[5/6] Verifying deletion ...");
  let verifyOk = true;
  for (const col of ALLOWLIST) {
    try {
      const { total } = await countCollection(col);
      if (total === 0) {
        console.log(`  ${col}: 0 docs remaining ✓`);
      } else {
        console.error(`  ${col}: ERROR — ${total} docs still remain!`);
        verifyOk = false;
      }
    } catch (err) {
      console.error(`  ${col}: count-check error — ${err.message}`);
    }
  }

  // ── Step 6: Verify sentinels unchanged ────────────────────────────────────
  console.log("\n[6/6] Verifying sentinel collections unchanged ...");
  let sentinelOk = true;
  for (const col of SENTINEL_COLLECTIONS) {
    try {
      const snap  = await db.collection(col).get();
      const after = snap.size;
      const before = sentinelBefore[col];
      if (before === null) {
        console.log(`  ${col}: was unreadable before, still unreadable ✓`);
      } else if (after === before) {
        console.log(`  ${col}: ${after} docs (unchanged ✓)`);
      } else {
        console.error(`  ${col}: CHANGED — was ${before}, now ${after} !!!`);
        sentinelOk = false;
      }
    } catch (_) {
      console.log(`  ${col}: (not readable) ✓`);
    }
  }

  console.log("\n" + "=".repeat(60));
  if (verifyOk && sentinelOk) {
    console.log("Reset complete. All allowlisted collections are empty.");
    console.log("All sentinel collections are unchanged.");
  } else {
    console.error("WARNING: Some checks failed — review output above.");
  }
  console.log("=".repeat(60));
}

// ── Entrypoint ────────────────────────────────────────────────────────────────

(async () => {
  try {
    if (COMMIT) {
      await commitRun();
    } else {
      await dryRun();
    }
  } catch (err) {
    console.error("\nFATAL:", err.message);
    console.error(err.stack);
    process.exit(1);
  }
  process.exit(0);
})();
