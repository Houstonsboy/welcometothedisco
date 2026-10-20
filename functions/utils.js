// Pure, side-effect-free helpers shared between index.js and tests.

/**
 * Returns a stable pair key from two Spotify entity IDs.
 * Lower-lex ID is always the a-side.
 */
function makePairKey(id1, id2) {
  const ids = [id1.trim(), id2.trim()].sort();
  return `${ids[0]}_${ids[1]}`;
}

/**
 * Counts non-bonus decided rounds from a track_details list.
 *
 * Each element shape:
 *   { round_number, entity1_track_id, entity2_track_id,
 *     winner: "entity1" | "entity2" | null | undefined,
 *     isBonus?: boolean }
 *
 * Returns { roundsEntity1, roundsEntity2 } — counts on the entity1/entity2 sides
 * (not yet mapped to a/b pair sides).
 */
function countRounds(trackDetails) {
  let roundsEntity1 = 0;
  let roundsEntity2 = 0;
  for (const track of trackDetails) {
    if (track.isBonus === true) continue;
    if (track.winner === "entity1") roundsEntity1++;
    else if (track.winner === "entity2") roundsEntity2++;
  }
  return { roundsEntity1, roundsEntity2 };
}

/**
 * Maps entity1/entity2 round counts onto a/b sides of the pair.
 *
 * The a-side is whichever entity sorts lower lexicographically (same rule as makePairKey).
 * Both entity IDs are required — do NOT derive the a-side by splitting pairKey on "_"
 * because entity IDs may themselves contain underscores.
 */
function mapRoundsToAB(entity1Id, entity2Id, roundsEntity1, roundsEntity2) {
  const isEntity1A = entity1Id.trim() <= entity2Id.trim();
  return isEntity1A
    ? { roundsA: roundsEntity1, roundsB: roundsEntity2 }
    : { roundsA: roundsEntity2, roundsB: roundsEntity1 };
}

/**
 * Recomputes the full voter state after updating one versus entry.
 *
 * storedVersus  — the voter's current versus map (may be empty {})
 * versusId      — the versus being updated (null when handling a delete by passing prunedVersus)
 * newRoundsA/B  — new round totals for this specific versus
 * MIN_ROUNDS    — minimum combined rounds before voter is counted (default 2)
 *
 * Returns:
 *   newVersusMap  — updated versus map (all versus entries incl. new/changed one)
 *   totalRoundsA  — pooled rounds_a across ALL versus
 *   totalRoundsB  — pooled rounds_b across ALL versus
 *   counted       — true when (totalRoundsA + totalRoundsB) >= MIN_ROUNDS
 *   shareA/shareB — voter's fractional contribution to pair votes_a/votes_b
 */
function computeNewVoterState({ storedVersus, versusId, newRoundsA, newRoundsB }, MIN_ROUNDS = 2) {
  const newVersusMap = versusId != null
    ? { ...storedVersus, [versusId]: { rounds_a: newRoundsA, rounds_b: newRoundsB } }
    : { ...storedVersus }; // deletion path: caller already pruned the map

  let totalRoundsA = 0;
  let totalRoundsB = 0;
  for (const entry of Object.values(newVersusMap)) {
    totalRoundsA += (entry.rounds_a || 0);
    totalRoundsB += (entry.rounds_b || 0);
  }

  const total   = totalRoundsA + totalRoundsB;
  const counted = total >= MIN_ROUNDS;
  const shareA  = counted ? totalRoundsA / total : 0;
  const shareB  = counted ? totalRoundsB / total : 0;

  return { newVersusMap, totalRoundsA, totalRoundsB, counted, shareA, shareB };
}

/**
 * Computes the incremental diffs to apply to the pair doc.
 *
 * newVoterState — result of computeNewVoterState()
 * oldVoterData  — previous voter doc data (empty {} for new voter)
 * versusId      — the versus being updated
 *
 * Returns incremental values (can be negative) ready for FieldValue.increment().
 */
function computePairIncrements({ newVoterState, oldVoterData, versusId }) {
  const wasCounted       = oldVoterData.counted || false;
  const oldShareA        = oldVoterData.share_a || 0;
  const oldShareB        = oldVoterData.share_b || 0;
  const oldVersusEntry   = (oldVoterData.versus || {})[versusId] || { rounds_a: 0, rounds_b: 0 };
  const newVersusEntry   = (newVoterState.newVersusMap || {})[versusId] || { rounds_a: 0, rounds_b: 0 };

  return {
    diffShareA:        newVoterState.shareA - oldShareA,
    diffShareB:        newVoterState.shareB - oldShareB,
    diffVoterCount:    (newVoterState.counted ? 1 : 0) - (wasCounted ? 1 : 0),
    diffVersusRoundsA: newVersusEntry.rounds_a - oldVersusEntry.rounds_a,
    diffVersusRoundsB: newVersusEntry.rounds_b - oldVersusEntry.rounds_b,
    isFirstVersusForVoter: !oldVoterData.versus || !oldVoterData.versus[versusId],
  };
}

/**
 * Trusted identity of a versus doc's two sides, used to validate polls — the
 * voter writes the poll doc, so its entity IDs/names/type can't be trusted.
 *
 * Album versus (type "album", or legacy docs with no type) use album1ID/album2ID;
 * artist, collaboration and post-remix ("collaborator") versus use artist1ID/artist2ID.
 *
 * maxPairedRounds is the number of head-to-head (non-bonus) rounds the versus
 * can have — the shorter side's track count — or null when the doc doesn't
 * record its tracks.
 *
 * Returns null when either side is missing (e.g. a collaboration nobody joined yet).
 */
function resolveVersusSides(versus) {
  const v = versus || {};
  const isAlbum = (v.type || "album") === "album";
  const str = (x) => (typeof x === "string" ? x.trim() : "");
  const len = (x) => (Array.isArray(x) ? x.length : 0);

  const sides = isAlbum
    ? {
      entityType: "album",
      entity1Id: str(v.album1ID), entity1Name: str(v.album1Name),
      entity2Id: str(v.album2ID), entity2Name: str(v.album2Name),
      tracks1: len(v.album1Tracklist), tracks2: len(v.album2Tracklist),
    }
    : {
      entityType: "artist",
      entity1Id: str(v.artist1ID), entity1Name: str(v.artist1Name),
      entity2Id: str(v.artist2ID), entity2Name: str(v.artist2Name),
      tracks1: len(v.artist1TrackIDs), tracks2: len(v.artist2TrackIDs),
    };
  if (!sides.entity1Id || !sides.entity2Id) return null;

  const { tracks1, tracks2, ...rest } = sides;
  return {
    ...rest,
    maxPairedRounds: tracks1 > 0 && tracks2 > 0 ? Math.min(tracks1, tracks2) : null,
  };
}

/**
 * Keeps one entry per round_number (first wins) and drops head-to-head rounds
 * beyond what the versus actually has, so a hand-written poll can't stack
 * extra or duplicate rounds. Bonus rounds are kept (countRounds ignores them).
 */
function sanitizeTrackDetails(trackDetails, maxPairedRounds) {
  if (!Array.isArray(trackDetails)) return [];
  const seen = new Set();
  const out = [];
  for (const t of trackDetails) {
    if (!t || typeof t !== "object") continue;
    const n = t.round_number;
    if (!Number.isInteger(n) || n < 0 || seen.has(n)) continue;
    if (t.isBonus !== true && maxPairedRounds != null && n >= maxPairedRounds) continue;
    seen.add(n);
    out.push(t);
  }
  return out;
}

/**
 * Returns true when both entity IDs (trimmed) are identical — a self-matchup.
 * Self-matchups are recorded but excluded from pair docs and rankings.
 */
function isSelfMatchup(id1, id2) {
  const a = (id1 || "").trim();
  const b = (id2 || "").trim();
  return a.length > 0 && b.length > 0 && a === b;
}

/**
 * Bradley–Terry model with a conjugate prior (MM update, normalized).
 *
 * rows: [{ a, b, votesA, votesB }]  (a !== b, votes are doubles)
 * entityIds: every entity of this type that has a rankings doc
 * prior: pretend wins AND losses against a strength-1 ghost opponent
 *
 * Returns { points: { [id]: number }, iterations }
 * Entities with no valid rows get exactly 100.0.
 */
function computeBradleyTerry(rows, entityIds, { prior = 1, maxIter = 500, tol = 1e-6 } = {}) {
  // Defensive filter: skip rows with missing IDs, equal IDs, or non-finite votes.
  const validRows = rows.filter(r =>
    r.a && r.b && r.a !== r.b &&
    typeof r.votesA === "number" && isFinite(r.votesA) &&
    typeof r.votesB === "number" && isFinite(r.votesB) &&
    (r.votesA + r.votesB) > 0
  );

  // Build entity universe: entityIds ∪ every entity found in valid rows.
  // This ensures entities that appear in pair docs but lack a rankings doc
  // are included and never cause an undefined-map crash.
  const allIds = new Set(entityIds);
  for (const r of validRows) { allIds.add(r.a); allIds.add(r.b); }

  // Determine which entities actually appear in valid matchup rows.
  const participating = new Set();
  for (const r of validRows) { participating.add(r.a); participating.add(r.b); }

  const activeIds = [...allIds].filter(id => participating.has(id));

  if (activeIds.length === 0) {
    const points = {};
    for (const id of allIds) points[id] = 100.0;
    return { points, iterations: 0 };
  }

  // Initialize strengths, wins, n for every active entity (including pair-only entities).
  const s    = {};
  const wins = {};
  const n    = {};
  for (const id of activeIds) { s[id] = 1.0; wins[id] = 0; n[id] = {}; }

  for (const r of validRows) {
    wins[r.a] = (wins[r.a] ?? 0) + r.votesA;
    wins[r.b] = (wins[r.b] ?? 0) + r.votesB;
    const tot = r.votesA + r.votesB;
    n[r.a][r.b] = ((n[r.a] ?? {})[r.b] ?? 0) + tot;
    n[r.b][r.a] = ((n[r.b] ?? {})[r.a] ?? 0) + tot;
  }

  let iterations = 0;
  for (let iter = 0; iter < maxIter; iter++) {
    iterations = iter + 1;
    const newS = {};

    for (const i of activeIds) {
      const num = (wins[i] ?? 0) + prior;
      // Prior: 2*prior total comparisons against a ghost of strength 1.
      let den = 2 * prior / (s[i] + 1);
      for (const [j, nij] of Object.entries(n[i] ?? {})) {
        den += nij / (s[i] + (s[j] ?? 1));
      }
      newS[i] = num / den;
    }

    // Normalize so the geometric mean of active strengths = 1.
    const logMean = activeIds.reduce((sum, id) => sum + Math.log(newS[id]), 0) / activeIds.length;
    const gm = Math.exp(logMean);

    let maxChange = 0;
    for (const id of activeIds) {
      newS[id] /= gm;
      maxChange = Math.max(maxChange, Math.abs(newS[id] - s[id]));
      s[id] = newS[id];
    }
    if (maxChange < tol) break;
  }

  const points = {};
  for (const id of allIds) {
    points[id] = participating.has(id) ? 100 * s[id] : 100.0;
  }
  return { points, iterations };
}

/**
 * Summarises per-entity opponent and voter counts from the pair rows.
 *
 * rows: [{ a, b, voterCount, ... }]
 * Returns { [entityId]: { distinctOpponents, totalVoters } }
 * Only pairs with voterCount > 0 are counted.
 */
function computeEntityStats(rows) {
  const stats = {};
  for (const r of rows) {
    if ((r.voterCount || 0) <= 0) continue;
    for (const id of [r.a, r.b]) {
      if (!stats[id]) stats[id] = { distinctOpponents: 0, totalVoters: 0 };
      stats[id].distinctOpponents++;
      stats[id].totalVoters += r.voterCount;
    }
  }
  return stats;
}

/**
 * Assigns dense ranks to non-provisional entities.
 *
 * points: { [id]: number }
 * stats:  result of computeEntityStats
 * Returns { [id]: { rank: int|null, provisional: bool } }
 *
 * provisional = true when distinctOpponents < minOpponents || totalVoters < minVoters.
 * rank = 1-based dense rank by points desc among non-provisional only; null for provisional.
 */
function computeRanks(points, stats, { minOpponents, minVoters }) {
  const result = {};
  for (const id of Object.keys(points)) {
    const st = stats[id] || { distinctOpponents: 0, totalVoters: 0 };
    const provisional = st.distinctOpponents < minOpponents || st.totalVoters < minVoters;
    result[id] = { rank: null, provisional };
  }

  // Dense ranking among non-provisional entities, points descending.
  const active = Object.entries(result)
    .filter(([, v]) => !v.provisional)
    .sort(([a], [b]) => points[b] - points[a]);

  let rank = 1;
  for (let i = 0; i < active.length; i++) {
    if (i > 0 && points[active[i][0]] < points[active[i - 1][0]]) rank++;
    result[active[i][0]].rank = rank;
  }
  return result;
}

/**
 * Every distinct substring (length >= 2) of a lowercased username, used as the
 * `username_search` array so clients can find users with a single
 * `array-contains` query. 1-char queries fall back to a prefix query instead.
 * A 20-char username yields at most 190 entries, well under Firestore's
 * 40k index-entries-per-doc limit.
 */
function usernameSubstrings(username) {
  const name = String(username || "").trim().toLowerCase();
  const out = new Set();
  for (let i = 0; i < name.length; i++) {
    for (let j = i + 2; j <= name.length; j++) {
      out.add(name.slice(i, j));
    }
  }
  return [...out].sort();
}

module.exports = {
  usernameSubstrings,
  makePairKey, countRounds, mapRoundsToAB,
  computeNewVoterState, computePairIncrements, isSelfMatchup,
  resolveVersusSides, sanitizeTrackDetails,
  computeBradleyTerry, computeEntityStats, computeRanks,
};
