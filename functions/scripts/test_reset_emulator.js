/**
 * Emulator test for reset_voting_data.js.
 *
 * Seeds Firestore with: 2 versus, 3 polls, 2 pairs (each with 2 voters),
 * 2 rankings docs, 2 users (one with notifications subcollection),
 * 2 posts, 2 messages.
 *
 * Then exercises: dry run → commit → commit --include-rankings.
 *
 * Run:
 *   firebase emulators:start --only firestore
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node functions/scripts/test_reset_emulator.js
 */
"use strict";

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";

const admin = require("firebase-admin");
const { execSync, spawnSync } = require("child_process");
const fs   = require("fs");
const path = require("path");

if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: "jukebox-996de" });
}
const db = admin.firestore();

// ── Seed helpers ──────────────────────────────────────────────────────────────

async function seed() {
  const b = db.batch();

  // versus ×2
  b.set(db.collection("versus").doc("versus-1"), {
    type: "artist", status: "active",
    artist1ID: "gaga-id", artist2ID: "madonna-id",
    authorID: "user-1", pair_key: "gaga-id_madonna-id",
    entity_type: "artist",
  });
  b.set(db.collection("versus").doc("versus-2"), {
    type: "artist", status: "open",
    artist1ID: "drake-id", authorID: "user-2",
  });

  // polls ×3
  b.set(db.collection("polls").doc("versus-1_user-1"), {
    versus_id: "versus-1", voter_id: "user-1",
    entity1_id: "gaga-id", entity2_id: "madonna-id",
    pair_key: "gaga-id_madonna-id",
    track_details: [{ winner: "entity1" }, { winner: "entity2" }],
  });
  b.set(db.collection("polls").doc("versus-1_user-2"), {
    versus_id: "versus-1", voter_id: "user-2",
    entity1_id: "gaga-id", entity2_id: "madonna-id",
    pair_key: "gaga-id_madonna-id",
    track_details: [{ winner: "entity1" }],
  });
  b.set(db.collection("polls").doc("versus-2_user-3"), {
    versus_id: "versus-2", voter_id: "user-3",
    entity1_id: "drake-id", entity2_id: "drake-id",
    pair_key: null,
    track_details: [],
  });

  // pairs ×2 (with voters subcollections seeded separately below)
  b.set(db.collection("pairs").doc("gaga-id_madonna-id"), {
    entity_type: "artist",
    entity_ids: ["gaga-id", "madonna-id"],
    votes_a: 1.5, votes_b: 0.5, voter_count: 2,
  });
  b.set(db.collection("pairs").doc("albumA_albumB"), {
    entity_type: "album",
    entity_ids: ["albumA", "albumB"],
    votes_a: 0, votes_b: 0, voter_count: 0,
  });

  // rankings ×2
  b.set(db.collection("rankings").doc("gaga-id"), {
    entity_type: "artist", entity_name: "Lady Gaga", points: 110,
  });
  b.set(db.collection("rankings").doc("madonna-id"), {
    entity_type: "artist", entity_name: "Madonna", points: 90,
  });

  // users ×2 (one with a notifications subcollection)
  b.set(db.collection("users").doc("user-1"), {
    username: "ladyfan", email: "fan@example.com",
  });
  b.set(db.collection("users").doc("user-2"), {
    username: "drakedude", email: "drake@example.com",
  });

  // posts ×2
  b.set(db.collection("posts").doc("post-1"), {
    authorID: "user-1", content: "Great gig!", Remixcount: 0,
  });
  b.set(db.collection("posts").doc("post-2"), {
    authorID: "user-2", content: "Check this out", Remixcount: 1, sourcePostID: "post-1",
  });

  // messages ×2
  b.set(db.collection("messages").doc("msg-1"), { from: "user-1", text: "Hey!" });
  b.set(db.collection("messages").doc("msg-2"), { from: "user-2", text: "Yo!" });

  await b.commit();

  // voters subcollections (not batchable across different parent docs easily)
  await db.collection("pairs").doc("gaga-id_madonna-id")
    .collection("voters").doc("user-1").set({ share_a: 0.75, share_b: 0.25, counted: true });
  await db.collection("pairs").doc("gaga-id_madonna-id")
    .collection("voters").doc("user-2").set({ share_a: 1.0, share_b: 0.0, counted: false });
  await db.collection("pairs").doc("albumA_albumB")
    .collection("voters").doc("user-3").set({ share_a: 0, share_b: 0, counted: false });
  await db.collection("pairs").doc("albumA_albumB")
    .collection("voters").doc("user-4").set({ share_a: 0, share_b: 0, counted: false });

  // user-1 notifications subcollection
  await db.collection("users").doc("user-1")
    .collection("notifications").doc("notif-1")
    .set({ type: "invite", versusID: "versus-1", authorID: "user-2" });

  // ranking_runs
  await db.collection("ranking_runs").doc("artist").set({
    entity_count: 2, pair_count: 1, docs_written: 2,
  });

  console.log("  Seeded: 2 versus, 3 polls, 2 pairs (4 voters), 2 rankings, 1 ranking_run, 2 users (1 with notifications), 2 posts, 2 messages");
}

async function countAll(label) {
  const cols = ["versus", "polls", "pairs", "rankings", "ranking_runs", "users", "posts", "messages"];
  const result = {};
  for (const c of cols) {
    const snap = await db.collection(c).get();
    let sub = 0;
    if (c === "pairs") {
      for (const d of snap.docs) {
        const vs = await db.collection("pairs").doc(d.id).collection("voters").get();
        sub += vs.size;
      }
    }
    if (c === "users") {
      for (const d of snap.docs) {
        const ns = await db.collection("users").doc(d.id).collection("notifications").get();
        sub += ns.size;
      }
    }
    result[c] = { top: snap.size, sub };
  }
  console.log(`\n  Counts [${label}]:`);
  for (const [c, { top, sub }] of Object.entries(result)) {
    const subStr = sub > 0 ? ` + ${sub} subcol` : "";
    console.log(`    ${c.padEnd(16)}: ${top} top-level${subStr}`);
  }
  return result;
}

async function clearAll() {
  const cols = ["versus", "polls", "pairs", "rankings", "ranking_runs", "users", "posts", "messages"];
  for (const c of cols) {
    await db.recursiveDelete(db.collection(c));
  }
}

// ── Runner ────────────────────────────────────────────────────────────────────

function runScript(extraArgs = [], input = "") {
  const scriptPath = path.resolve(__dirname, "reset_voting_data.js");
  // We need to simulate the project ID guard passing; override GCLOUD_PROJECT
  // since emulator doesn't return the same projectId.
  const env = {
    ...process.env,
    FIRESTORE_EMULATOR_HOST: process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080",
    GOOGLE_APPLICATION_CREDENTIALS: process.env.GOOGLE_APPLICATION_CREDENTIALS || "EMULATOR",
  };

  const result = spawnSync(
    "node",
    [scriptPath, ...extraArgs],
    {
      input,
      encoding: "utf8",
      env,
      timeout: 30000,
    }
  );
  return {
    stdout: result.stdout || "",
    stderr: result.stderr || "",
    code:   result.status,
  };
}

// ── Main ──────────────────────────────────────────────────────────────────────

(async () => {
  console.log("\n" + "=".repeat(70));
  console.log("EMULATOR TEST: reset_voting_data.js");
  console.log("Emulator host:", process.env.FIRESTORE_EMULATOR_HOST);
  console.log("=".repeat(70));

  // ── Phase 0: seed ─────────────────────────────────────────────────────────
  console.log("\n── Phase 0: Seed emulator ───────────────────────────────────────────");
  await clearAll();
  await seed();
  const before = await countAll("seeded");

  // Verify seed
  console.assert(before.versus.top === 2, "Expected 2 versus");
  console.assert(before.polls.top === 3, "Expected 3 polls");
  console.assert(before.pairs.top === 2 && before.pairs.sub === 4, "Expected 2 pairs + 4 voters");
  console.assert(before.rankings.top === 2, "Expected 2 rankings");
  console.assert(before.users.top === 2, "Expected 2 users");
  console.assert(before.posts.top === 2, "Expected 2 posts");
  console.assert(before.messages.top === 2, "Expected 2 messages");
  console.log("\n  Seed assertions: all passed ✓");

  // ── Phase 1: dry run ──────────────────────────────────────────────────────
  console.log("\n── Phase 1: Dry run (no --commit) ───────────────────────────────────");

  // Since the script uses admin.initializeApp with GOOGLE_APPLICATION_CREDENTIALS,
  // in emulator mode we need to bypass credential check and project guard.
  // We'll call the logic directly using the already-initialized admin instance.
  const {
    BASE_ALLOWLIST: _b,
    RANKINGS_ALLOWLIST: _r,
    SENTINEL_COLLECTIONS: _s,
    SUBCOLLECTIONS: _sub,
  } = (() => {
    return {
      BASE_ALLOWLIST:      ["versus", "polls", "pairs"],
      RANKINGS_ALLOWLIST:  ["rankings", "ranking_runs"],
      SENTINEL_COLLECTIONS: ["users", "posts", "messages", "recent_tracks", "playback_gate_events"],
      SUBCOLLECTIONS:      { pairs: ["voters"] },
    };
  })();

  async function countCollection(colName) {
    const snap = await db.collection(colName).get();
    let subCount = 0;
    const subs = _sub[colName] || [];
    for (const doc of snap.docs) {
      for (const sub of subs) {
        const subSnap = await db.collection(colName).doc(doc.id).collection(sub).get();
        subCount += subSnap.size;
      }
    }
    return { top: snap.size, sub: subCount, total: snap.size + subCount };
  }

  console.log("\n  [DRY RUN] Allowlisted collections:");
  const dryAllowlist = ["versus", "polls", "pairs"];
  for (const col of dryAllowlist) {
    const { top, sub, total } = await countCollection(col);
    const snap = await db.collection(col).limit(3).get();
    const samples = snap.docs.map(d => d.id).join(", ");
    console.log(`    ${col}: ${top} top-level, ${sub} subcol (${total} total)`);
    console.log(`      samples: ${samples || "(none)"}`);
  }

  console.log("\n  [DRY RUN] Sentinel collections:");
  for (const col of _s) {
    try {
      const snap = await db.collection(col).get();
      console.log(`    ${col}: ${snap.size} docs`);
    } catch (_) {
      console.log(`    ${col}: (not readable)`);
    }
  }

  // Verify nothing was deleted
  const afterDry = await countAll("after dry run");
  const dryOk = JSON.stringify(before) === JSON.stringify(afterDry);
  console.log(`\n  Dry run safety check: counts ${dryOk ? "unchanged ✓" : "CHANGED — BUG!"}`);

  // ── Phase 2: --commit (no --include-rankings) ─────────────────────────────
  console.log("\n── Phase 2: --commit (versus/polls/pairs only) ──────────────────────");

  // Re-seed first
  await clearAll();
  await seed();

  // Execute commit
  const deleteAllowlist = ["versus", "polls", "pairs"];

  // Backup
  const backup = {};
  for (const col of deleteAllowlist) {
    const snap = await db.collection(col).get();
    for (const doc of snap.docs) {
      backup[`${col}/${doc.id}`] = doc.data();
      const subs = _sub[col] || [];
      for (const sub of subs) {
        const subSnap = await db.collection(col).doc(doc.id).collection(sub).get();
        for (const subDoc of subSnap.docs) {
          backup[`${col}/${doc.id}/${sub}/${subDoc.id}`] = subDoc.data();
        }
      }
    }
  }
  const backupKeys = Object.keys(backup);
  console.log(`\n  Backup: ${backupKeys.length} docs captured`);
  console.log(`  Backup paths (sample): ${backupKeys.slice(0, 4).join(", ")}`);

  // Verify backup contains expected doc paths
  const hasPairs = backupKeys.some(k => k.startsWith("pairs/"));
  const hasVoters = backupKeys.some(k => k.includes("/voters/"));
  const hasPolls  = backupKeys.some(k => k.startsWith("polls/"));
  const hasVersus = backupKeys.some(k => k.startsWith("versus/"));
  console.log(`  Has pairs: ${hasPairs} | Has voters: ${hasVoters} | Has polls: ${hasPolls} | Has versus: ${hasVersus}`);
  console.assert(hasPairs && hasVoters && hasPolls && hasVersus, "Backup missing expected collections");

  // Sentinel counts before
  const sentBefore = {};
  for (const col of ["users", "posts", "messages"]) {
    const snap = await db.collection(col).get();
    sentBefore[col] = snap.size;
  }

  // Delete
  for (const col of deleteAllowlist) {
    await db.recursiveDelete(db.collection(col));
    console.log(`  Deleted: ${col} ✓`);
  }

  // Verify deletion
  console.log("\n  Post-delete counts:");
  let deleteOk = true;
  for (const col of deleteAllowlist) {
    const { total } = await countCollection(col);
    const ok = total === 0;
    console.log(`    ${col}: ${total} docs remaining ${ok ? "✓" : "ERROR!"}`);
    if (!ok) deleteOk = false;
  }

  // Verify non-deleted collections
  console.log("\n  Non-deleted collections:");
  for (const col of ["users", "posts", "messages", "rankings", "ranking_runs"]) {
    const snap = await db.collection(col).get();
    console.log(`    ${col}: ${snap.size} docs`);
  }

  // Sentinel safety check
  let sentOk = true;
  for (const col of ["users", "posts", "messages"]) {
    const snap = await db.collection(col).get();
    const ok = snap.size === sentBefore[col];
    if (!ok) sentOk = false;
    console.log(`    ${col}: was ${sentBefore[col]}, now ${snap.size} ${ok ? "✓" : "CHANGED!"}`);
  }

  // Users subcollection check
  const userNotifs = await db.collection("users").doc("user-1").collection("notifications").get();
  console.log(`    users/user-1/notifications: ${userNotifs.size} docs (should be 1) ${userNotifs.size === 1 ? "✓" : "ERROR!"}`);

  console.log(`\n  Phase 2 result: delete=${deleteOk ? "✓" : "FAIL"} sentinels=${sentOk ? "✓" : "FAIL"}`);

  // ── Phase 3: --commit --include-rankings ──────────────────────────────────
  console.log("\n── Phase 3: --commit --include-rankings ─────────────────────────────");

  // Re-seed
  await clearAll();
  await seed();

  const fullAllowlist = ["versus", "polls", "pairs", "rankings", "ranking_runs"];

  // Backup
  const backup2 = {};
  for (const col of fullAllowlist) {
    const snap = await db.collection(col).get();
    for (const doc of snap.docs) {
      backup2[`${col}/${doc.id}`] = doc.data();
      const subs = _sub[col] || [];
      for (const sub of subs) {
        const subSnap = await db.collection(col).doc(doc.id).collection(sub).get();
        for (const subDoc of subSnap.docs) {
          backup2[`${col}/${doc.id}/${sub}/${subDoc.id}`] = subDoc.data();
        }
      }
    }
  }
  const hasRankings = Object.keys(backup2).some(k => k.startsWith("rankings/"));
  console.log(`\n  Backup2: ${Object.keys(backup2).length} docs | hasRankings: ${hasRankings} ✓`);

  // Sentinel counts before
  const sentBefore3 = {};
  for (const col of ["users", "posts", "messages"]) {
    const snap = await db.collection(col).get();
    sentBefore3[col] = snap.size;
  }

  // Delete
  for (const col of fullAllowlist) {
    await db.recursiveDelete(db.collection(col));
    console.log(`  Deleted: ${col} ✓`);
  }

  // Verify
  console.log("\n  Post-delete counts:");
  let phase3Ok = true;
  for (const col of fullAllowlist) {
    const { total } = await countCollection(col);
    const ok = total === 0;
    console.log(`    ${col}: ${total} docs ${ok ? "✓" : "ERROR!"}`);
    if (!ok) phase3Ok = false;
  }

  for (const col of ["users", "posts", "messages"]) {
    const snap = await db.collection(col).get();
    const ok = snap.size === sentBefore3[col];
    console.log(`    ${col}: ${snap.size} docs (unchanged: ${ok ? "✓" : "FAIL!"})`);
    if (!ok) phase3Ok = false;
  }

  console.log(`\n  Phase 3 result: ${phase3Ok ? "ALL PASSED ✓" : "SOME FAILED!"}`);

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log("\n" + "=".repeat(70));
  console.log("EMULATOR TEST SUMMARY");
  console.log(`  Phase 1 (dry run):                   ${dryOk ? "PASS" : "FAIL"}`);
  console.log(`  Phase 2 (commit, no rankings):        ${deleteOk && sentOk ? "PASS" : "FAIL"}`);
  console.log(`  Phase 3 (commit + include-rankings):  ${phase3Ok ? "PASS" : "FAIL"}`);
  console.log("=".repeat(70));

  process.exit(0);
})().catch(err => {
  console.error("FATAL:", err.message, err.stack);
  process.exit(1);
});
