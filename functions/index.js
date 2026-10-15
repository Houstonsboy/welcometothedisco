const { onCall } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const { HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const axios = require("axios");
const admin = require("firebase-admin");
const { FieldValue } = require("firebase-admin/firestore");
const {
  makePairKey,
  countRounds,
  mapRoundsToAB,
  computeNewVoterState,
  computePairIncrements,
  isSelfMatchup,
  computeBradleyTerry,
  computeEntityStats,
  computeRanks,
} = require("./utils");

// ── Ranking job constants ─────────────────────────────────────────────────────
const RANKING_PRIOR              = 1;
const PROVISIONAL_MIN_OPPONENTS  = 2;
const PROVISIONAL_MIN_VOTERS     = 2;
const ENTITY_TYPES               = ["artist", "album"];

if (admin.apps.length === 0) admin.initializeApp();

const db = admin.firestore();

setGlobalOptions({ maxInstances: 10 });

exports.exchangeSpotifyCode = onCall(async (request) => {
  const code = request.data.code;

  if (!code) {
    throw new Error("Auth code is required");
  }

  const clientId     = process.env.SPOTIFY_CLIENT_ID;
  const clientSecret = process.env.SPOTIFY_CLIENT_SECRET;
  const redirectUri  = process.env.SPOTIFY_REDIRECT_URI;

  logger.info("Exchanging Spotify auth code for tokens");

  const response = await axios.post(
    "https://accounts.spotify.com/api/token",
    new URLSearchParams({
      grant_type:    "authorization_code",
      code:           code,
      redirect_uri:   redirectUri,
      client_id:      clientId,
      client_secret:  clientSecret,
    }),
    { headers: { "Content-Type": "application/x-www-form-urlencoded" } }
  );

  return {
    accessToken:  response.data.access_token,
    refreshToken: response.data.refresh_token,
    expiresIn:    response.data.expires_in,
  };
});

exports.sendFriendNotification = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const { tokens, title, body, data } = request.data;

  if (!Array.isArray(tokens) || tokens.length === 0) {
    throw new HttpsError("invalid-argument", "tokens must be a non-empty array.");
  }
  if (typeof title !== "string" || !title.trim()) {
    throw new HttpsError("invalid-argument", "title is required.");
  }
  if (typeof body !== "string" || !body.trim()) {
    throw new HttpsError("invalid-argument", "body is required.");
  }

  const BATCH = 500;
  let successCount = 0;
  let failureCount = 0;

  for (let i = 0; i < tokens.length; i += BATCH) {
    const chunk = tokens.slice(i, i + BATCH);
    const message = {
      tokens: chunk,
      notification: { title, body },
      data: data && typeof data === "object" ? data : {},
      android: {
        priority: "high",
        notification: { sound: "default" },
      },
      apns: {
        payload: { aps: { sound: "default" } },
      },
    };

    const result = await admin.messaging().sendEachForMulticast(message);
    successCount += result.successCount;
    failureCount += result.failureCount;

    result.responses.forEach((resp, idx) => {
      if (!resp.success) {
        logger.warn("FCM send failed", {
          token: chunk[idx].slice(0, 12) + "…",
          error: resp.error?.code,
        });
      }
    });
  }

  logger.info("sendFriendNotification done", { successCount, failureCount });
  return { successCount, failureCount };
});

// ── Scheduled Bradley–Terry ranking job ──────────────────────────────────────

exports.recomputeRankings = onSchedule(
  { schedule: "every 3 hours", timeZone: "Africa/Nairobi", timeoutSeconds: 540, memory: "512MiB" },
  async () => { await runRankingJob(); }
);

async function _runRankingForType(entityType) {
  const typeStart = Date.now();

  // 1. Read all pairs for this entity type.
  const pairsSnap = await db.collection("pairs")
    .where("entity_type", "==", entityType)
    .get();

  const rows = [];
  // Map from entity ID → { entity_name, entity_image } sourced from pair docs.
  // Used to create rankings docs for entities that appear in pairs but have no doc.
  const entityInfoFromPairs = {};

  for (const doc of pairsSnap.docs) {
    const d = doc.data();
    const ids = d.entity_ids || [];
    const a = (ids[0] || "").trim();
    const b = (ids[1] || "").trim();
    if (!a || !b || a === b) {
      logger.warn(`runRankingJob [${entityType}]: skipping pair ${doc.id} — missing or equal entity_ids`);
      continue;
    }
    const votesA = d.votes_a;
    const votesB = d.votes_b;
    if (typeof votesA !== "number" || !isFinite(votesA) ||
        typeof votesB !== "number" || !isFinite(votesB)) {
      logger.warn(`runRankingJob [${entityType}]: skipping pair ${doc.id} — non-numeric votes`);
      continue;
    }
    if (votesA + votesB <= 0) continue;

    // Collect entity metadata for potential stub creation later.
    const ea = d.entity_a || {};
    const eb = d.entity_b || {};
    if (!entityInfoFromPairs[a]) entityInfoFromPairs[a] = { entity_name: ea.entity_name || "", entity_image: ea.entity_image || "" };
    if (!entityInfoFromPairs[b]) entityInfoFromPairs[b] = { entity_name: eb.entity_name || "", entity_image: eb.entity_image || "" };

    rows.push({ a, b, votesA, votesB, voterCount: d.voter_count || 0 });
  }

  // 2. Read all rankings docs for this type.
  const rankingsSnap = await db.collection("rankings")
    .where("entity_type", "==", entityType)
    .get();

  const existingRankingIds = new Set(rankingsSnap.docs.map(d => d.id));

  // Entities in valid pair rows that have no rankings doc yet — the production crash scenario.
  const missingIds = Object.keys(entityInfoFromPairs).filter(id => !existingRankingIds.has(id));

  // Full entity universe: existing rankings + pair-only entities.
  const allEntityIds = [...existingRankingIds, ...missingIds];

  if (allEntityIds.length === 0) {
    logger.info(`runRankingJob [${entityType}]: no entities, skipping`);
    return;
  }

  // 3. Compute BT ratings, entity stats, and ranks.
  const { points, iterations } = computeBradleyTerry(rows, allEntityIds, { prior: RANKING_PRIOR });
  const stats = computeEntityStats(rows);
  const ranks = computeRanks(points, stats, {
    minOpponents: PROVISIONAL_MIN_OPPONENTS,
    minVoters:    PROVISIONAL_MIN_VOTERS,
  });

  // 4. Write changed docs via BulkWriter.
  const bulkWriter = db.bulkWriter();
  let docsWritten    = 0;
  let createdMissing = 0;

  // 4a. Update existing rankings docs (skip when nothing changed).
  for (const snap of rankingsSnap.docs) {
    const id  = snap.id;
    const old = snap.data();

    // Guard every derived value against undefined so no Firestore write ever
    // receives an undefined field (which Firestore rejects at runtime).
    const newPoints      = Math.round(((typeof points[id] === "number" ? points[id] : 100)) * 100) / 100;
    const rankEntry      = ranks[id] || { rank: null, provisional: true };
    const newRank        = rankEntry.rank !== undefined ? rankEntry.rank : null;
    const newProvisional = typeof rankEntry.provisional === "boolean" ? rankEntry.provisional : true;
    const st             = stats[id] || { distinctOpponents: 0, totalVoters: 0 };
    const newDistinct    = typeof st.distinctOpponents === "number" ? st.distinctOpponents : 0;
    const newTotalVoters = typeof st.totalVoters === "number" ? st.totalVoters : 0;
    const newNameLower   = (old.entity_name || "").toLowerCase().trim();

    // Compare numerically — stubs write points as 100 (integer), which equals 100.0.
    const oldPoints      = typeof old.points === "number"
      ? Math.round(old.points * 100) / 100 : null;

    const changed =
      oldPoints                     !== newPoints      ||
      (old.rank ?? null)            !== newRank        ||
      (old.provisional ?? true)     !== newProvisional ||
      (old.distinct_opponents || 0) !== newDistinct    ||
      (old.total_voters || 0)       !== newTotalVoters ||
      (old.entity_name_lower || "") !== newNameLower;

    if (!changed) continue;

    docsWritten++;
    bulkWriter.update(snap.ref, {
      points:             newPoints,
      rank:               newRank,            // null is valid; undefined is not
      provisional:        newProvisional,
      distinct_opponents: newDistinct,
      total_voters:       newTotalVoters,
      entity_name_lower:  newNameLower,
      points_updated_at:  FieldValue.serverTimestamp(),
    });
  }

  // 4b. Create rankings docs for entities found in pairs but with no existing doc.
  for (const id of missingIds) {
    const info        = entityInfoFromPairs[id] || {};
    const entityName  = info.entity_name  || "";
    const entityImage = info.entity_image || "";

    const newPoints      = Math.round(((typeof points[id] === "number" ? points[id] : 100)) * 100) / 100;
    const rankEntry      = ranks[id] || { rank: null, provisional: true };
    const newRank        = rankEntry.rank !== undefined ? rankEntry.rank : null;
    const newProvisional = typeof rankEntry.provisional === "boolean" ? rankEntry.provisional : true;
    const st             = stats[id] || { distinctOpponents: 0, totalVoters: 0 };
    const newDistinct    = typeof st.distinctOpponents === "number" ? st.distinctOpponents : 0;
    const newTotalVoters = typeof st.totalVoters === "number" ? st.totalVoters : 0;

    createdMissing++;
    docsWritten++;
    // create() is intentional: if a race caused the doc to appear between our read
    // and write, the failure is safe — the next run will find the doc and update it.
    bulkWriter.create(db.collection("rankings").doc(id), {
      entity_id:          id,
      entity_type:        entityType,
      entity_name:        entityName,
      entity_image:       entityImage,
      entity_name_lower:  entityName.toLowerCase().trim(),
      created_at:         FieldValue.serverTimestamp(),
      points:             newPoints,
      rank:               newRank,
      provisional:        newProvisional,
      distinct_opponents: newDistinct,
      total_voters:       newTotalVoters,
      points_updated_at:  FieldValue.serverTimestamp(),
    });
  }

  await bulkWriter.close();

  if (createdMissing > 0) {
    logger.warn(
      `runRankingJob [${entityType}]: created ${createdMissing} missing rankings doc(s): ` +
      missingIds.slice(0, 10).join(", ") + (createdMissing > 10 ? " …" : "")
    );
  }

  // 5. Write ranking_runs summary doc.
  // Always write this even when zero pairs — confirms the job ran for this type.
  const durationMs = Date.now() - typeStart;
  await db.collection("ranking_runs").doc(entityType).set({
    run_at:                    FieldValue.serverTimestamp(),
    entity_count:              allEntityIds.length,
    pair_count:                rows.length,
    iterations:                typeof iterations === "number" ? iterations : 0,
    docs_written:              docsWritten,
    created_missing:           createdMissing,
    prior:                     RANKING_PRIOR,
    provisional_min_opponents: PROVISIONAL_MIN_OPPONENTS,
    provisional_min_voters:    PROVISIONAL_MIN_VOTERS,
    duration_ms:               durationMs,
  });

  // 6. One-line summary log.
  logger.info(
    `runRankingJob [${entityType}]: entities=${allEntityIds.length} pairs=${rows.length} ` +
    `written=${docsWritten} created=${createdMissing} iter=${iterations} ms=${durationMs}`
  );
}

async function runRankingJob() {
  for (const entityType of ENTITY_TYPES) {
    try {
      await _runRankingForType(entityType);
    } catch (err) {
      logger.error(`runRankingJob [${entityType}] failed: ${err?.message}`, { stack: err?.stack });
    }
  }
}

exports.runRankingJob = runRankingJob;

// ── Shared: process a fully-populated versus doc ──────────────────────────────
// Extracts entity info, creates/merges the pair doc, creates ranking stubs.
// Safe to call more than once (idempotent via set+merge and existence checks).
async function _processVersusDoc(versusId, data) {
  let entity1Id, entity2Id, entityType, entity1Name, entity2Name, entity1Image, entity2Image;

  if (data.artist1ID && data.artist2ID) {
    entityType   = "artist";
    entity1Id    = data.artist1ID;
    entity2Id    = data.artist2ID;
    entity1Name  = (data.artist1Name  || "").trim();
    entity2Name  = (data.artist2Name  || "").trim();
    entity1Image = (data.artist1Image || data.artistImage || "").trim();
    entity2Image = (data.artist2Image || "").trim();
  } else if (data.album1ID && data.album2ID) {
    entityType   = "album";
    entity1Id    = data.album1ID;
    entity2Id    = data.album2ID;
    entity1Name  = (data.album1Name  || "").trim();
    entity2Name  = (data.album2Name  || "").trim();
    entity1Image = (data.album1ImageUrl || data.album1Image || "").trim();
    entity2Image = (data.album2ImageUrl || data.album2Image || "").trim();
  } else {
    logger.warn("_processVersusDoc: entity IDs not found", {
      versusId,
      presentKeys: Object.keys(data),
    });
    return null; // not yet fully populated (open-join waiting for entity2)
  }

  // Self-matchup: same entity on both sides — ensure flag is set, skip pair creation.
  if (isSelfMatchup(entity1Id, entity2Id)) {
    const versusRef = db.collection("versus").doc(versusId);
    if (!data.is_self_matchup) {
      await versusRef.update({ is_self_matchup: true });
    }
    return null;
  }

  const pairKey = makePairKey(entity1Id, entity2Id);
  // Direct ID comparison — pairKey.split("_")[0] breaks when IDs contain underscores.
  const isEntity1A = entity1Id.trim() <= entity2Id.trim();

  const entityAId    = isEntity1A ? entity1Id    : entity2Id;
  const entityAName  = isEntity1A ? entity1Name  : entity2Name;
  const entityAImage = isEntity1A ? entity1Image : entity2Image;
  const entityBId    = isEntity1A ? entity2Id    : entity1Id;
  const entityBName  = isEntity1A ? entity2Name  : entity1Name;
  const entityBImage = isEntity1A ? entity2Image : entity1Image;

  const versusRef   = db.collection("versus").doc(versusId);
  const pairRef     = db.collection("pairs").doc(pairKey);
  const rankingARef = db.collection("rankings").doc(entityAId);
  const rankingBRef = db.collection("rankings").doc(entityBId);

  await db.runTransaction(async (tx) => {
    const [pairSnap, rankingASnap, rankingBSnap] = await Promise.all([
      tx.get(pairRef),
      tx.get(rankingARef),
      tx.get(rankingBRef),
    ]);

    // Write pair_key + entity_type back onto versus doc only if the value differs,
    // so the write doesn't re-trigger onVersusJoined unnecessarily.
    if ((data.pair_key || '') !== pairKey || (data.entity_type || '') !== entityType) {
      tx.update(versusRef, { pair_key: pairKey, entity_type: entityType });
    }

    // Create or merge pairs doc.
    if (!pairSnap.exists) {
      tx.set(pairRef, {
        entity_type:  entityType,
        entity_ids:   [entityAId, entityBId],
        entity_a:     { entity_id: entityAId, entity_name: entityAName, entity_image: entityAImage },
        entity_b:     { entity_id: entityBId, entity_name: entityBName, entity_image: entityBImage },
        votes_a:      0,
        votes_b:      0,
        rounds_a:     0,
        rounds_b:     0,
        voter_count:  0,
        versus_count: 1,
        created_at:   FieldValue.serverTimestamp(),
        last_voted_at: FieldValue.serverTimestamp(),
        versus: {
          [versusId]: { rounds_a: 0, rounds_b: 0, poll_count: 0, last_voted_at: FieldValue.serverTimestamp() },
        },
      });
    } else {
      const existing = pairSnap.data();
      const versusAlreadyTracked = existing.versus && existing.versus[versusId] != null;
      if (!versusAlreadyTracked) {
        // Use nested object (not dotted key) so set()+merge creates a proper nested entry.
        tx.set(pairRef, {
          versus_count:  FieldValue.increment(1),
          last_voted_at: FieldValue.serverTimestamp(),
          versus: {
            [versusId]: { rounds_a: 0, rounds_b: 0, poll_count: 0, last_voted_at: FieldValue.serverTimestamp() },
          },
        }, { merge: true });
      }
    }

    // Create ranking stubs if absent.
    if (!rankingASnap.exists) {
      tx.set(rankingARef, {
        entity_id:          entityAId,
        entity_type:        entityType,
        entity_name:        entityAName,
        entity_image:       entityAImage,
        entity_name_lower:  entityAName.toLowerCase().trim(),
        created_at:         FieldValue.serverTimestamp(),
        points:             100.0,
        rank:               null,
        provisional:        true,
        distinct_opponents: 0,
        total_voters:       0,
        points_updated_at:  null,
      });
    }
    if (!rankingBSnap.exists) {
      tx.set(rankingBRef, {
        entity_id:          entityBId,
        entity_type:        entityType,
        entity_name:        entityBName,
        entity_image:       entityBImage,
        entity_name_lower:  entityBName.toLowerCase().trim(),
        created_at:         FieldValue.serverTimestamp(),
        points:             100.0,
        rank:               null,
        provisional:        true,
        distinct_opponents: 0,
        total_voters:       0,
        points_updated_at:  null,
      });
    }
  });

  return pairKey;
}

// ── onVersusCreated ───────────────────────────────────────────────────────────
exports.onVersusCreated = onDocumentCreated("versus/{versusId}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const versusId = event.params.versusId;
  const pairKey = await _processVersusDoc(versusId, snap.data());
  if (pairKey) {
    logger.info("onVersusCreated done", { versusId, pairKey });
  } else {
    logger.info("onVersusCreated: open-join versus, waiting for entity2", { versusId });
  }
});

// ── onVersusJoined ────────────────────────────────────────────────────────────
// Handles versus docs that just became fully populated (both entity IDs present).
exports.onVersusJoined = onDocumentUpdated("versus/{versusId}", async (event) => {
  const before = event.data?.before?.data() ?? {};
  const after  = event.data?.after?.data()  ?? {};

  // Determine whether after state is complete (both entity IDs present).
  let entity1Id, entity2Id;
  if (after.artist1ID && after.artist2ID) {
    entity1Id = after.artist1ID;
    entity2Id = after.artist2ID;
  } else if (after.album1ID && after.album2ID) {
    entity1Id = after.album1ID;
    entity2Id = after.album2ID;
  } else {
    return; // still incomplete — nothing to do
  }

  // (a) The second entity field was absent in before and present in after (genuine join).
  const secondJustAdded =
    (!before.artist2ID && !!after.artist2ID) ||
    (!before.album2ID  && !!after.album2ID);

  const selfMatchup = isSelfMatchup(entity1Id, entity2Id);

  // (b) pair_key absent/wrong — only meaningful for non-self-matchups.
  // Self-matchups intentionally never have a pair_key.
  const pairKeyNeedsSet = !selfMatchup &&
    (!after.pair_key || after.pair_key !== makePairKey(entity1Id, entity2Id));

  // (c) is_self_matchup flag not yet written to the versus doc.
  const selfMatchupFlagNeedsSet = selfMatchup && !after.is_self_matchup;

  // Run only when there is actual work to do — avoids re-firing on unrelated
  // field changes (e.g. status updates) or after _processVersusDoc writes back.
  if (!secondJustAdded && !pairKeyNeedsSet && !selfMatchupFlagNeedsSet) return;

  const versusId = event.params.versusId;
  const pairKey = await _processVersusDoc(versusId, after);
  if (pairKey) {
    logger.info("onVersusJoined done", { versusId, pairKey });
  }
});

// ── onPollWritten ─────────────────────────────────────────────────────────────
// Fires on every create/update/delete of polls/{pollId}.
// pollId format: {versusId}_{voterId}
//
// Per-voter unit: each voter contributes at most 1 unit split across a/b sides.
// share_a = rounds_a / (rounds_a + rounds_b) when counted (>= MIN_ROUNDS total).
// votes_a on the pair accumulates these shares — Bradley–Terry input.
// rounds_a on the pair accumulates raw round counts — display only.
const MIN_ROUNDS = 2;

exports.onPollWritten = onDocumentWritten("polls/{pollId}", async (event) => {
  const after  = event.data?.after;
  const before = event.data?.before;
  const pollId = event.params.pollId;

  const isDelete = before?.exists && (!after || !after.exists);

  if (isDelete) {
    return _handlePollDelete(pollId, before.data());
  }

  if (!after || !after.exists) return;
  return _handlePollUpsert(pollId, after.data());
});

async function _handlePollDelete(pollId, data) {
  const pairKeyFromPoll = (data.pair_key    || "").trim();
  const entity1Id       = (data.entity1_id  || "").trim();
  const entity2Id       = (data.entity2_id  || "").trim();
  const voterId         = (data.voter_id    || "").trim();
  const versusId        = (data.versus_id   || "").trim();

  if (!entity1Id || !voterId || !versusId) {
    logger.warn("onPollWritten delete: missing required fields", { pollId });
    return;
  }

  // Self-matchup polls are not backed by a pair doc — nothing to update.
  if (isSelfMatchup(entity1Id, entity2Id)) {
    logger.info("onPollWritten delete: self-matchup — no pair to update", { pollId });
    return;
  }

  const pairKey = makePairKey(entity1Id, entity2Id);
  if (pairKey !== pairKeyFromPoll) {
    logger.warn("onPollWritten delete: pair_key mismatch", { pollId, pairKeyFromPoll, pairKey });
  }

  const voterRef = db.collection("pairs").doc(pairKey).collection("voters").doc(voterId);
  const pairRef  = db.collection("pairs").doc(pairKey);

  await db.runTransaction(async (tx) => {
    const [voterSnap, pairSnap] = await Promise.all([tx.get(voterRef), tx.get(pairRef)]);
    if (!voterSnap.exists || !pairSnap.exists) return;

    const voterData = voterSnap.data();
    const oldVersusEntry = (voterData.versus || {})[versusId];
    if (!oldVersusEntry) return; // already removed

    // Remove this versus entry and recompute voter state.
    const prunedVersus = Object.fromEntries(
      Object.entries(voterData.versus || {}).filter(([k]) => k !== versusId)
    );
    const newState = computeNewVoterState(
      { storedVersus: prunedVersus, versusId: null, newRoundsA: 0, newRoundsB: 0 },
      MIN_ROUNDS
    );

    const { diffShareA, diffShareB, diffVoterCount, diffVersusRoundsA, diffVersusRoundsB } =
      computePairIncrements({ newVoterState: newState, oldVoterData: voterData, versusId });

    tx.set(voterRef, {
      voter_id:   voterId,
      pair_key:   pairKey,
      versus:     prunedVersus,
      rounds_a:   newState.totalRoundsA,
      rounds_b:   newState.totalRoundsB,
      share_a:    newState.shareA,
      share_b:    newState.shareB,
      counted:    newState.counted,
      updated_at: FieldValue.serverTimestamp(),
    });

    tx.update(pairRef, {
      "votes_a":      FieldValue.increment(diffShareA),
      "votes_b":      FieldValue.increment(diffShareB),
      "rounds_a":     FieldValue.increment(-oldVersusEntry.rounds_a),
      "rounds_b":     FieldValue.increment(-oldVersusEntry.rounds_b),
      "voter_count":  FieldValue.increment(diffVoterCount),
      [`versus.${versusId}.rounds_a`]:      FieldValue.increment(diffVersusRoundsA),
      [`versus.${versusId}.rounds_b`]:      FieldValue.increment(diffVersusRoundsB),
      [`versus.${versusId}.last_voted_at`]: FieldValue.serverTimestamp(),
      "last_voted_at": FieldValue.serverTimestamp(),
    });
  });

  logger.info("onPollWritten delete handled", { pollId, pairKey });
}

async function _handlePollUpsert(pollId, data) {
  const pairKeyFromPoll = (data.pair_key    || "").trim();
  const entity1Id       = (data.entity1_id  || "").trim();
  const entity2Id       = (data.entity2_id  || "").trim();
  const voterId         = (data.voter_id    || "").trim();
  const versusId        = (data.versus_id   || "").trim();
  const entityType      = (data.entity_type || "").trim();
  const entity1Name     = (data.entity1_name || "").trim();
  const entity2Name     = (data.entity2_name || "").trim();
  const trackDetails    = Array.isArray(data.track_details) ? data.track_details : [];

  if (!entity1Id || !entity2Id || !voterId || !versusId) {
    logger.warn("onPollWritten: missing required fields", { pollId });
    return;
  }

  // Self-matchup polls are recorded but excluded from pair/voter/ranking writes.
  if (isSelfMatchup(entity1Id, entity2Id)) {
    logger.info("onPollWritten: self-matchup — skipping pair updates", { pollId });
    return;
  }

  // Always derive pairKey from entity IDs — the stored pair_key is advisory only.
  const pairKey = makePairKey(entity1Id, entity2Id);
  if (pairKey !== pairKeyFromPoll) {
    logger.warn("onPollWritten: pair_key mismatch — using computed key", {
      pollId, stored: pairKeyFromPoll, computed: pairKey,
    });
  }

  const { roundsEntity1, roundsEntity2 } = countRounds(trackDetails);
  const { roundsA: thisVersusNewRoundsA, roundsB: thisVersusNewRoundsB } =
    mapRoundsToAB(entity1Id, entity2Id, roundsEntity1, roundsEntity2);

  // Determine a/b assignment: the entity that sorts first is the a-side.
  const isE1A = entity1Id <= entity2Id;
  const entityAId   = isE1A ? entity1Id   : entity2Id;
  const entityAName = isE1A ? entity1Name : entity2Name;
  const entityBId   = isE1A ? entity2Id   : entity1Id;
  const entityBName = isE1A ? entity2Name : entity1Name;

  const voterRef = db.collection("pairs").doc(pairKey).collection("voters").doc(voterId);
  const pairRef  = db.collection("pairs").doc(pairKey);
  const rankARef = db.collection("rankings").doc(entityAId);
  const rankBRef = db.collection("rankings").doc(entityBId);

  await db.runTransaction(async (tx) => {
    // ALL reads must come before any writes in a Firestore transaction.
    const [voterSnap, pairSnap, rankASnap, rankBSnap] = await Promise.all([
      tx.get(voterRef),
      tx.get(pairRef),
      tx.get(rankARef),
      tx.get(rankBRef),
    ]);

    const oldVoterData = voterSnap.exists ? voterSnap.data() : {};

    // Compute new voter state: set this versus entry, recompute totals + shares.
    const newState = computeNewVoterState(
      { storedVersus: oldVoterData.versus || {}, versusId, newRoundsA: thisVersusNewRoundsA, newRoundsB: thisVersusNewRoundsB },
      MIN_ROUNDS
    );

    // Write voter doc as a full set (we own the entire document shape).
    tx.set(voterRef, {
      voter_id:   voterId,
      pair_key:   pairKey,
      versus:     newState.newVersusMap,
      rounds_a:   newState.totalRoundsA,
      rounds_b:   newState.totalRoundsB,
      share_a:    newState.shareA,
      share_b:    newState.shareB,
      counted:    newState.counted,
      updated_at: FieldValue.serverTimestamp(),
    });

    // Compute diffs to apply to the pair.
    const { diffShareA, diffShareB, diffVoterCount, diffVersusRoundsA, diffVersusRoundsB, isFirstVersusForVoter } =
      computePairIncrements({ newVoterState: newState, oldVoterData, versusId });

    if (pairSnap.exists) {
      const pairUpdate = {
        "votes_a":       FieldValue.increment(diffShareA),
        "votes_b":       FieldValue.increment(diffShareB),
        "rounds_a":      FieldValue.increment(diffVersusRoundsA),
        "rounds_b":      FieldValue.increment(diffVersusRoundsB),
        "voter_count":   FieldValue.increment(diffVoterCount),
        "last_voted_at": FieldValue.serverTimestamp(),
        [`versus.${versusId}.rounds_a`]:      FieldValue.increment(diffVersusRoundsA),
        [`versus.${versusId}.rounds_b`]:      FieldValue.increment(diffVersusRoundsB),
        [`versus.${versusId}.last_voted_at`]: FieldValue.serverTimestamp(),
      };
      if (isFirstVersusForVoter) {
        pairUpdate[`versus.${versusId}.poll_count`] = FieldValue.increment(1);
      }
      tx.update(pairRef, pairUpdate);
    } else {
      // Pair doc doesn't exist yet — create it from the poll's identity fields.
      tx.set(pairRef, {
        entity_type:  entityType,
        entity_ids:   [entityAId, entityBId],
        entity_a:     { entity_id: entityAId, entity_name: entityAName, entity_image: "" },
        entity_b:     { entity_id: entityBId, entity_name: entityBName, entity_image: "" },
        votes_a:      newState.shareA,
        votes_b:      newState.shareB,
        rounds_a:     thisVersusNewRoundsA,
        rounds_b:     thisVersusNewRoundsB,
        voter_count:  newState.counted ? 1 : 0,
        versus_count: 1,
        created_at:   FieldValue.serverTimestamp(),
        last_voted_at: FieldValue.serverTimestamp(),
        versus: {
          [versusId]: {
            rounds_a:      thisVersusNewRoundsA,
            rounds_b:      thisVersusNewRoundsB,
            poll_count:    1,
            last_voted_at: FieldValue.serverTimestamp(),
          },
        },
      });

      if (!rankASnap.exists) {
        tx.set(rankARef, {
          entity_id: entityAId, entity_type: entityType, entity_name: entityAName,
          entity_name_lower: entityAName.toLowerCase().trim(),
          entity_image: "", created_at: FieldValue.serverTimestamp(),
          points: 100.0, rank: null, provisional: true,
          distinct_opponents: 0, total_voters: 0, points_updated_at: null,
        });
      }
      if (!rankBSnap.exists) {
        tx.set(rankBRef, {
          entity_id: entityBId, entity_type: entityType, entity_name: entityBName,
          entity_name_lower: entityBName.toLowerCase().trim(),
          entity_image: "", created_at: FieldValue.serverTimestamp(),
          points: 100.0, rank: null, provisional: true,
          distinct_opponents: 0, total_voters: 0, points_updated_at: null,
        });
      }
    }
  });

  logger.info("onPollWritten done", {
    pollId, pairKey, versusId,
    roundsA: thisVersusNewRoundsA, roundsB: thisVersusNewRoundsB,
  });
}
