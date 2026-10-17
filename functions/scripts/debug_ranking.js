/**
 * Read-only production debug script.
 *
 * Reproduces the exact read + compute steps from _runRankingForType
 * for both "artist" and "album" without performing any writes.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     node functions/scripts/debug_ranking.js
 */
"use strict";

const admin = require("firebase-admin");
const {
  computeBradleyTerry,
  computeEntityStats,
  computeRanks,
} = require("../utils");

const PROJECT_ID = "jukebox-996de";
const RANKING_PRIOR             = 1;
const PROVISIONAL_MIN_OPPONENTS = 2;
const PROVISIONAL_MIN_VOTERS    = 5;
const ENTITY_TYPES              = ["artist", "album"];

// ── Init ──────────────────────────────────────────────────────────────────────

try {
  if (admin.apps.length === 0) {
    if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      console.error(
        "ERROR: GOOGLE_APPLICATION_CREDENTIALS env var not set.\n" +
        "Usage: GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node debug_ranking.js"
      );
      process.exit(1);
    }
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: PROJECT_ID,
    });
    console.log(`[init] Firebase Admin initialised for project ${PROJECT_ID}`);
  }
} catch (err) {
  console.error("[init] admin.initializeApp FAILED:", err.message);
  console.error(err.stack);
  process.exit(1);
}

let db;
try {
  db = admin.firestore();
  console.log("[init] admin.firestore() OK");
} catch (err) {
  console.error("[init] admin.firestore() FAILED:", err.message);
  console.error(err.stack);
  process.exit(1);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function findUndefined(obj, prefix = "") {
  const found = [];
  for (const [k, v] of Object.entries(obj)) {
    const path = prefix ? `${prefix}.${k}` : k;
    if (v === undefined) found.push(path);
    else if (v !== null && typeof v === "object" && !Array.isArray(v) &&
             typeof v.toDate !== "function" /* skip Timestamp */) {
      found.push(...findUndefined(v, path));
    }
  }
  return found;
}

function printPayload(id, payload) {
  const undef = findUndefined(payload);
  if (undef.length) {
    console.error(`  !! UNDEFINED fields in payload for ${id}: ${undef.join(", ")}`);
  }
  const pts  = payload.points;
  const rank = payload.rank;
  const prov = payload.provisional;
  const dnf  = payload.distinct_opponents;
  const tv   = payload.total_voters;
  const nl   = payload.entity_name_lower;
  console.log(
    `  [doc ${id}] points=${pts} rank=${rank} prov=${prov} ` +
    `opp=${dnf} voters=${tv} name_lower="${nl}"`
  );
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function debugType(entityType) {
  console.log(`\n${"=".repeat(60)}`);
  console.log(`DEBUG: entityType = "${entityType}"`);
  console.log("=".repeat(60));

  // ── Step 1: Read pairs ────────────────────────────────────────────────────
  let pairsSnap;
  try {
    console.log("\n[step 1] Reading pairs collection ...");
    pairsSnap = await db.collection("pairs")
      .where("entity_type", "==", entityType)
      .get();
    console.log(`[step 1] OK — ${pairsSnap.size} pair docs found`);
  } catch (err) {
    console.error("[step 1] FAILED:", err.message);
    console.error(err.stack);
    return;
  }

  // ── Step 2: Build rows ───────────────────────────────────────────────────
  const rows = [];
  let skippedInvalid = 0;
  let skippedZeroVotes = 0;
  try {
    console.log("\n[step 2] Building rows from pair docs ...");
    for (const doc of pairsSnap.docs) {
      const d = doc.data();
      const ids = d.entity_ids;

      if (!Array.isArray(ids) || ids.length < 2) {
        console.warn(`  WARN pair ${doc.id}: entity_ids missing or not an array — skipped`);
        skippedInvalid++;
        continue;
      }

      const a = (ids[0] || "").trim();
      const b = (ids[1] || "").trim();

      if (!a || !b) {
        console.warn(`  WARN pair ${doc.id}: empty entity ID — a="${a}" b="${b}" — skipped`);
        skippedInvalid++;
        continue;
      }
      if (a === b) {
        console.log(`  INFO pair ${doc.id}: self-matchup (a===b) — skipped`);
        skippedInvalid++;
        continue;
      }

      const votesA = typeof d.votes_a === "number" ? d.votes_a : 0;
      const votesB = typeof d.votes_b === "number" ? d.votes_b : 0;

      if (votesA + votesB <= 0) {
        console.log(`  INFO pair ${doc.id}: zero votes — skipped`);
        skippedZeroVotes++;
        continue;
      }

      rows.push({
        a,
        b,
        votesA,
        votesB,
        voterCount: typeof d.voter_count === "number" ? d.voter_count : 0,
      });
    }
    console.log(
      `[step 2] OK — ${rows.length} valid rows ` +
      `(skipped: invalid=${skippedInvalid}, zero_votes=${skippedZeroVotes})`
    );
    if (rows.length > 0) {
      console.log("  First row sample:", JSON.stringify(rows[0]));
    }
  } catch (err) {
    console.error("[step 2] FAILED:", err.message);
    console.error(err.stack);
    return;
  }

  // ── Step 3: Read rankings ─────────────────────────────────────────────────
  let rankingsSnap;
  try {
    console.log("\n[step 3] Reading rankings collection ...");
    rankingsSnap = await db.collection("rankings")
      .where("entity_type", "==", entityType)
      .get();
    console.log(`[step 3] OK — ${rankingsSnap.size} ranking docs found`);
  } catch (err) {
    console.error("[step 3] FAILED:", err.message);
    console.error(err.stack);
    return;
  }

  const entityIds = rankingsSnap.docs.map(d => d.id);

  if (entityIds.length === 0) {
    console.log(`[step 3] No rankings docs for "${entityType}" — nothing to compute`);
    return;
  }

  // ── Step 4: computeBradleyTerry ──────────────────────────────────────────
  let points, iterations;
  try {
    console.log("\n[step 4] computeBradleyTerry ...");
    ({ points, iterations } = computeBradleyTerry(rows, entityIds, { prior: RANKING_PRIOR }));
    console.log(`[step 4] OK — iterations=${iterations}`);

    // Check for non-finite values.
    const nonFinite = Object.entries(points).filter(([, v]) => !Number.isFinite(v));
    if (nonFinite.length) {
      console.error(`  !! Non-finite points: ${nonFinite.map(([id, v]) => `${id}=${v}`).join(", ")}`);
    } else {
      console.log(`  All ${Object.keys(points).length} points are finite`);
    }

    // Check for IDs missing from points.
    const missingFromPoints = entityIds.filter(id => !(id in points));
    if (missingFromPoints.length) {
      console.error(`  !! Entity IDs missing from points: ${missingFromPoints.join(", ")}`);
    }
  } catch (err) {
    console.error("[step 4] computeBradleyTerry FAILED:", err.message);
    console.error(err.stack);
    return;
  }

  // ── Step 5: computeEntityStats ───────────────────────────────────────────
  let stats;
  try {
    console.log("\n[step 5] computeEntityStats ...");
    stats = computeEntityStats(rows);
    console.log(`[step 5] OK — ${Object.keys(stats).length} entities have stats`);
    const entitiesWithNoStats = entityIds.filter(id => !(id in stats));
    console.log(`  ${entitiesWithNoStats.length} entities have NO stats (will default to 0 opp, 0 voters)`);
  } catch (err) {
    console.error("[step 5] computeEntityStats FAILED:", err.message);
    console.error(err.stack);
    return;
  }

  // ── Step 6: computeRanks ─────────────────────────────────────────────────
  let ranks;
  try {
    console.log("\n[step 6] computeRanks ...");
    ranks = computeRanks(points, stats, {
      minOpponents: PROVISIONAL_MIN_OPPONENTS,
      minVoters:    PROVISIONAL_MIN_VOTERS,
    });
    const provisional = Object.values(ranks).filter(r => r.provisional).length;
    const ranked      = Object.values(ranks).filter(r => !r.provisional).length;
    console.log(`[step 6] OK — provisional=${provisional} ranked=${ranked}`);

    const missingFromRanks = entityIds.filter(id => !(id in ranks));
    if (missingFromRanks.length) {
      console.error(`  !! Entity IDs missing from ranks: ${missingFromRanks.join(", ")}`);
    }
  } catch (err) {
    console.error("[step 6] computeRanks FAILED:", err.message);
    console.error(err.stack);
    return;
  }

  // ── Step 7: Build payloads (no writes) ──────────────────────────────────
  console.log(`\n[step 7] Building write payloads (no writes performed) ...`);
  let wouldWrite = 0;
  let wouldSkip  = 0;

  try {
    for (const snap of rankingsSnap.docs) {
      const id  = snap.id;
      const old = snap.data();

      const newPoints      = Math.round((points[id] ?? 100) * 100) / 100;
      const newRank        = ranks[id]?.rank ?? null;
      const newProvisional = ranks[id]?.provisional ?? true;
      const st             = stats[id] || { distinctOpponents: 0, totalVoters: 0 };
      const newDistinct    = st.distinctOpponents;
      const newTotalVoters = st.totalVoters;
      const entityName     = (old.entity_name || "").trim();
      const newNameLower   = entityName.toLowerCase().trim();

      const oldPoints = typeof old.points === "number"
        ? Math.round(old.points * 100) / 100 : null;

      const changed =
        oldPoints                        !== newPoints      ||
        (old.rank ?? null)               !== newRank        ||
        (old.provisional ?? true)        !== newProvisional ||
        (old.distinct_opponents || 0)    !== newDistinct    ||
        (old.total_voters || 0)          !== newTotalVoters ||
        (old.entity_name_lower || "")    !== newNameLower;

      const payload = {
        points:             newPoints,
        rank:               newRank,
        provisional:        newProvisional,
        distinct_opponents: newDistinct,
        total_voters:       newTotalVoters,
        entity_name_lower:  newNameLower,
        points_updated_at:  "(serverTimestamp)",
      };

      // Scan for undefined fields.
      const undef = findUndefined(payload);
      if (undef.length) {
        console.error(`\n  !! UNDEFINED FIELDS in payload for ${id}: ${undef.join(", ")}`);
        console.error("     Full payload:", JSON.stringify(payload, null, 2));
      }

      if (changed) {
        wouldWrite++;
        printPayload(id, payload);
      } else {
        wouldSkip++;
      }
    }

    console.log(
      `\n[step 7] Summary: would write ${wouldWrite} docs, would skip ${wouldSkip} (unchanged)`
    );
  } catch (err) {
    console.error("[step 7] Payload building FAILED:", err.message);
    console.error(err.stack);
    return;
  }

  // ── Step 8: ranking_runs payload check ───────────────────────────────────
  console.log("\n[step 8] ranking_runs payload check ...");
  try {
    const runsPayload = {
      run_at:                    "(serverTimestamp)",
      entity_count:              entityIds.length,
      pair_count:                rows.length,
      iterations,
      docs_written:              wouldWrite,
      prior:                     RANKING_PRIOR,
      provisional_min_opponents: PROVISIONAL_MIN_OPPONENTS,
      provisional_min_voters:    PROVISIONAL_MIN_VOTERS,
      duration_ms:               0,
    };
    const undef = findUndefined(runsPayload);
    if (undef.length) {
      console.error(`  !! UNDEFINED fields in ranking_runs payload: ${undef.join(", ")}`);
    } else {
      console.log(`[step 8] OK — ranking_runs payload has no undefined values`);
      console.log("  Payload:", JSON.stringify(runsPayload, null, 2));
    }
  } catch (err) {
    console.error("[step 8] ranking_runs payload check FAILED:", err.message);
    console.error(err.stack);
  }

  console.log(`\n[done] "${entityType}" debug complete`);
}

(async () => {
  for (const entityType of ENTITY_TYPES) {
    try {
      await debugType(entityType);
    } catch (err) {
      console.error(`\n[UNCAUGHT] "${entityType}" threw outside all try/catch:`, err.message);
      console.error(err.stack);
    }
  }
  console.log("\n\nAll debug runs complete. No writes were made.");
  process.exit(0);
})();
