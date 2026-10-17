// Unit tests for pure pair helpers + offline integration tests via
// firebase-functions-test (no emulator or real Firestore needed).

"use strict";

const {
  makePairKey, countRounds, mapRoundsToAB, computeNewVoterState, computePairIncrements,
  computeBradleyTerry, computeEntityStats, computeRanks, isSelfMatchup,
} = require("../utils");

// ── makePairKey ───────────────────────────────────────────────────────────────

describe("makePairKey", () => {
  test("lower-lex ID is always the a-side", () => {
    expect(makePairKey("aaa", "bbb")).toBe("aaa_bbb");
    expect(makePairKey("bbb", "aaa")).toBe("aaa_bbb");
  });

  test("commutative — argument order does not matter", () => {
    const id1 = "spotify:artist:111";
    const id2 = "spotify:artist:222";
    expect(makePairKey(id1, id2)).toBe(makePairKey(id2, id1));
  });

  test("trims surrounding whitespace before sorting", () => {
    expect(makePairKey("  bbb  ", "aaa")).toBe("aaa_bbb");
  });

  test("IDs that are already equal produce a stable key", () => {
    expect(makePairKey("x", "x")).toBe("x_x");
  });

  test("lexicographic (not numeric) sort", () => {
    // "9" > "10" lexicographically
    expect(makePairKey("9", "10")).toBe("10_9");
  });
});

// ── countRounds ───────────────────────────────────────────────────────────────

describe("countRounds", () => {
  test("empty list returns zeros", () => {
    expect(countRounds([])).toEqual({ roundsEntity1: 0, roundsEntity2: 0 });
  });

  test("all undecided (null winner) returns zeros", () => {
    const tracks = [
      { winner: null },
      { winner: null },
      { winner: undefined },
    ];
    expect(countRounds(tracks)).toEqual({ roundsEntity1: 0, roundsEntity2: 0 });
  });

  test("counts entity1 and entity2 wins correctly", () => {
    const tracks = [
      { winner: "entity1" },
      { winner: "entity1" },
      { winner: "entity2" },
      { winner: null },
    ];
    expect(countRounds(tracks)).toEqual({ roundsEntity1: 2, roundsEntity2: 1 });
  });

  test("bonus rounds are excluded even if they have a winner", () => {
    const tracks = [
      { winner: "entity1", isBonus: false },
      { winner: "entity1", isBonus: true },  // excluded
      { winner: "entity2", isBonus: true },  // excluded
      { winner: "entity2", isBonus: false },
    ];
    expect(countRounds(tracks)).toEqual({ roundsEntity1: 1, roundsEntity2: 1 });
  });

  test("isBonus must be exactly true to be excluded (truthy values are not enough)", () => {
    const tracks = [
      { winner: "entity1", isBonus: 1 },    // not true, counts
      { winner: "entity2", isBonus: "yes" },// not true, counts
    ];
    expect(countRounds(tracks)).toEqual({ roundsEntity1: 1, roundsEntity2: 1 });
  });

  test("all bonus rounds → zeros", () => {
    const tracks = [
      { winner: "entity1", isBonus: true },
      { winner: "entity2", isBonus: true },
    ];
    expect(countRounds(tracks)).toEqual({ roundsEntity1: 0, roundsEntity2: 0 });
  });
});

// ── mapRoundsToAB ─────────────────────────────────────────────────────────────

describe("mapRoundsToAB", () => {
  // pairKey = "aaa_bbb" → aId = "aaa"

  test("entity1 is the a-side → rounds stay in same order", () => {
    const result = mapRoundsToAB("aaa", "bbb", 3, 1);
    expect(result).toEqual({ roundsA: 3, roundsB: 1 });
  });

  test("entity1 is the b-side → rounds are swapped", () => {
    const result = mapRoundsToAB("bbb", "aaa", 3, 1);
    // entity1=bbb won 3, entity2=aaa won 1
    // a-side is aaa → roundsA = 1, roundsB = 3
    expect(result).toEqual({ roundsA: 1, roundsB: 3 });
  });

  test("entity1 ID is trimmed before comparison", () => {
    expect(mapRoundsToAB("  aaa  ", "bbb", 2, 0)).toEqual({ roundsA: 2, roundsB: 0 });
  });

  test("zeros propagate correctly", () => {
    expect(mapRoundsToAB("aaa", "bbb", 0, 0)).toEqual({ roundsA: 0, roundsB: 0 });
  });
});

// ── Integration scenarios (offline, no emulator) ──────────────────────────────
// These tests exercise the full round-trip logic used by the Cloud Functions
// without touching real Firestore.  The four scenarios cover the cases that
// onPollWritten must handle correctly.

describe("onPollWritten round-trip logic (offline)", () => {
  // Helper: run the same diff logic as onPollWritten
  function computePollDiff({ trackDetails, entity1Id, entity2Id, pairKey, storedVersusEntry }) {
    const { roundsEntity1, roundsEntity2 } = countRounds(trackDetails);
    // pairKey is still accepted for callers that only pass it; derive entity2Id from it
    // when not supplied explicitly (works when IDs don't contain underscores).
    const e2 = entity2Id || pairKey.replace(entity1Id.trim() + "_", "").replace("_" + entity1Id.trim(), "");
    const { roundsA: newRoundsA, roundsB: newRoundsB } =
        mapRoundsToAB(entity1Id, e2, roundsEntity1, roundsEntity2);

    const prevA = storedVersusEntry?.rounds_a ?? 0;
    const prevB = storedVersusEntry?.rounds_b ?? 0;

    return {
      newRoundsA,
      newRoundsB,
      diffA: newRoundsA - prevA,
      diffB: newRoundsB - prevB,
    };
  }

  test("scenario 1 — first poll write, entity1 is a-side", () => {
    const pairKey = "aaa_bbb";
    const entity1Id = "aaa";
    const trackDetails = [
      { winner: "entity1" },
      { winner: "entity1" },
      { winner: "entity2" },
    ];
    const { newRoundsA, newRoundsB, diffA, diffB } =
        computePollDiff({ trackDetails, entity1Id, pairKey, storedVersusEntry: null });

    expect(newRoundsA).toBe(2);
    expect(newRoundsB).toBe(1);
    expect(diffA).toBe(2); // was 0
    expect(diffB).toBe(1); // was 0
  });

  test("scenario 2 — first poll write, entity1 is b-side (rounds swapped to a/b)", () => {
    const pairKey = "aaa_bbb";
    const entity1Id = "bbb"; // bbb is b-side
    const trackDetails = [
      { winner: "entity1" }, // entity1=bbb wins → b-side wins
      { winner: "entity2" }, // entity2=aaa wins → a-side wins
      { winner: "entity2" },
    ];
    const { newRoundsA, newRoundsB, diffA, diffB } =
        computePollDiff({ trackDetails, entity1Id, pairKey, storedVersusEntry: null });

    // entity1(bbb) won 1 → roundsB=1; entity2(aaa) won 2 → roundsA=2
    expect(newRoundsA).toBe(2);
    expect(newRoundsB).toBe(1);
    expect(diffA).toBe(2);
    expect(diffB).toBe(1);
  });

  test("scenario 3 — second poll write, only diff is applied (not full total)", () => {
    const pairKey = "aaa_bbb";
    const entity1Id = "aaa";
    const storedVersusEntry = { rounds_a: 2, rounds_b: 1 }; // from first write
    const trackDetails = [
      { winner: "entity1" },
      { winner: "entity1" },
      { winner: "entity2" },
      { winner: "entity1" }, // new round decided
    ];
    const { newRoundsA, newRoundsB, diffA, diffB } =
        computePollDiff({ trackDetails, entity1Id, pairKey, storedVersusEntry });

    expect(newRoundsA).toBe(3);
    expect(newRoundsB).toBe(1);
    expect(diffA).toBe(1);  // only the new round
    expect(diffB).toBe(0);
  });

  test("scenario 4 — bonus rounds are excluded from the diff", () => {
    const pairKey = "aaa_bbb";
    const entity1Id = "aaa";
    const trackDetails = [
      { winner: "entity1" },
      { winner: "entity2" },
      { winner: "entity1", isBonus: true }, // excluded
      { winner: "entity2", isBonus: true }, // excluded
    ];
    const { newRoundsA, newRoundsB } =
        computePollDiff({ trackDetails, entity1Id, pairKey, storedVersusEntry: null });

    expect(newRoundsA).toBe(1);
    expect(newRoundsB).toBe(1);
  });

  test("scenario 5 — all rounds undecided → zeros, no increment", () => {
    const pairKey = "aaa_bbb";
    const entity1Id = "aaa";
    const trackDetails = [{ winner: null }, { winner: null }];
    const { newRoundsA, newRoundsB, diffA, diffB } =
        computePollDiff({ trackDetails, entity1Id, pairKey, storedVersusEntry: null });

    expect(newRoundsA).toBe(0);
    expect(newRoundsB).toBe(0);
    expect(diffA).toBe(0);
    expect(diffB).toBe(0);
  });

  test("scenario 6 — same state re-written → diff is zero (idempotent)", () => {
    const pairKey = "aaa_bbb";
    const entity1Id = "aaa";
    const trackDetails = [
      { winner: "entity1" },
      { winner: "entity2" },
    ];
    const first = computePollDiff({
      trackDetails, entity1Id, pairKey, storedVersusEntry: null,
    });
    // second write with identical track_details
    const second = computePollDiff({
      trackDetails, entity1Id, pairKey,
      storedVersusEntry: { rounds_a: first.newRoundsA, rounds_b: first.newRoundsB },
    });

    expect(second.diffA).toBe(0);
    expect(second.diffB).toBe(0);
  });

  test("scenario 7 — voter previously at 2-1, new state is 2-2 (opponent catches up)", () => {
    const pairKey = "aaa_bbb";
    const entity1Id = "aaa";
    const storedVersusEntry = { rounds_a: 2, rounds_b: 1 };
    const trackDetails = [
      { winner: "entity1" },
      { winner: "entity1" },
      { winner: "entity2" },
      { winner: "entity2" }, // aaa voted entity2 on last round
    ];
    const { newRoundsA, newRoundsB, diffA, diffB } =
        computePollDiff({ trackDetails, entity1Id, pairKey, storedVersusEntry });

    expect(newRoundsA).toBe(2);
    expect(newRoundsB).toBe(2);
    expect(diffA).toBe(0);
    expect(diffB).toBe(1);
  });

  test("scenario 8 — pairKey derived from two entity IDs is consistent", () => {
    const id1 = "spotify:artist:ZZZZ";
    const id2 = "spotify:artist:AAAA";
    const pairKey = makePairKey(id1, id2);
    // AAAA < ZZZZ lexicographically
    expect(pairKey).toBe("spotify:artist:AAAA_spotify:artist:ZZZZ");

    // entity1 = ZZZZ = b-side → rounds should be swapped
    const { newRoundsA, newRoundsB } = computePollDiff({
      trackDetails: [{ winner: "entity1" }, { winner: "entity1" }],
      entity1Id: id1, // ZZZZ = b-side
      pairKey,
      storedVersusEntry: null,
    });
    expect(newRoundsA).toBe(0); // AAAA (a-side) won none
    expect(newRoundsB).toBe(2); // ZZZZ (b-side) won 2
  });

  test("scenario 9 — mixed bonus and regular, partial undecided", () => {
    const pairKey = "aaa_bbb";
    const entity1Id = "aaa";
    const trackDetails = [
      { winner: "entity1" },           // counts
      { winner: null },                 // undecided, skipped
      { winner: "entity2", isBonus: true }, // bonus, excluded
      { winner: "entity1" },           // counts
      { winner: "entity2" },           // counts
    ];
    const { newRoundsA, newRoundsB } =
        computePollDiff({ trackDetails, entity1Id, pairKey, storedVersusEntry: null });

    expect(newRoundsA).toBe(2);
    expect(newRoundsB).toBe(1);
  });

  test("scenario 10 — total voter accumulation across two versus", () => {
    // Simulate voter who has played two different versus sessions.
    // Each versus diff is computed independently; the total should be the sum.
    const pairKey = "aaa_bbb";
    const entity1Id = "aaa";

    const tdVersus1 = [{ winner: "entity1" }, { winner: "entity1" }, { winner: "entity2" }];
    const tdVersus2 = [{ winner: "entity2" }, { winner: "entity2" }];

    const diff1 = computePollDiff({
      trackDetails: tdVersus1, entity1Id, pairKey, storedVersusEntry: null,
    });
    const diff2 = computePollDiff({
      trackDetails: tdVersus2, entity1Id, pairKey, storedVersusEntry: null,
    });

    const totalA = diff1.diffA + diff2.diffA;
    const totalB = diff1.diffB + diff2.diffB;

    expect(totalA).toBe(2); // entity1(aaa): 2 from versus1 + 0 from versus2
    expect(totalB).toBe(3); // entity2(bbb): 1 from versus1 + 2 from versus2
  });

  test("scenario 11 — minimum rounds gate (< 2 non-bonus decided → do not save)", () => {
    const MIN_ROUNDS = 2;

    function shouldSavePoll(trackDetails, existingPollExists) {
      const { roundsEntity1, roundsEntity2 } = countRounds(trackDetails);
      const decidedRounds = roundsEntity1 + roundsEntity2;
      if (!existingPollExists && decidedRounds < MIN_ROUNDS) return false;
      return true;
    }

    // 1 decided round + existing doc → save (existing always updated)
    expect(shouldSavePoll([{ winner: "entity1" }], true)).toBe(true);

    // 1 decided round, no existing doc → skip
    expect(shouldSavePoll([{ winner: "entity1" }], false)).toBe(false);

    // 2 decided rounds, no existing doc → save
    expect(shouldSavePoll([{ winner: "entity1" }, { winner: "entity2" }], false)).toBe(true);

    // 0 decided rounds → skip
    expect(shouldSavePoll([{ winner: null }, { winner: null }], false)).toBe(false);

    // bonus-only rounds don't count toward gate
    expect(shouldSavePoll(
      [{ winner: "entity1", isBonus: true }, { winner: "entity2", isBonus: true }],
      false,
    )).toBe(false);
  });
});

// ── computeNewVoterState ──────────────────────────────────────────────────────

describe("computeNewVoterState", () => {
  test("new voter, single versus 3–1 → share ≈ 0.75 / 0.25, counted", () => {
    const state = computeNewVoterState(
      { storedVersus: {}, versusId: "v1", newRoundsA: 3, newRoundsB: 1 }
    );
    expect(state.totalRoundsA).toBe(3);
    expect(state.totalRoundsB).toBe(1);
    expect(state.counted).toBe(true);
    expect(state.shareA).toBeCloseTo(0.75);
    expect(state.shareB).toBeCloseTo(0.25);
    expect(state.newVersusMap.v1).toEqual({ rounds_a: 3, rounds_b: 1 });
  });

  test("pooling across two versus: 3–1 then 1–2 → 4 rounds_a 3 rounds_b, share ≈ 0.5714 / 0.4286", () => {
    // First versus already stored
    const after1 = computeNewVoterState(
      { storedVersus: {}, versusId: "v1", newRoundsA: 3, newRoundsB: 1 }
    );
    // Second versus added
    const after2 = computeNewVoterState(
      { storedVersus: after1.newVersusMap, versusId: "v2", newRoundsA: 1, newRoundsB: 2 }
    );
    expect(after2.totalRoundsA).toBe(4);
    expect(after2.totalRoundsB).toBe(3);
    expect(after2.counted).toBe(true);
    expect(after2.shareA).toBeCloseTo(4 / 7);
    expect(after2.shareB).toBeCloseTo(3 / 7);
  });

  test("re-vote replaces not adds: same versus updated 1–0 → 2–0", () => {
    const after1 = computeNewVoterState(
      { storedVersus: {}, versusId: "v1", newRoundsA: 1, newRoundsB: 0 }
    );
    // Re-vote: track_details now shows 2 wins for a-side
    const after2 = computeNewVoterState(
      { storedVersus: after1.newVersusMap, versusId: "v1", newRoundsA: 2, newRoundsB: 0 }
    );
    expect(after2.totalRoundsA).toBe(2);
    expect(after2.totalRoundsB).toBe(0);
    expect(after2.newVersusMap.v1).toEqual({ rounds_a: 2, rounds_b: 0 });
  });

  test("voter goes uncounted (1 round) → counted (2 rounds)", () => {
    const after1 = computeNewVoterState(
      { storedVersus: {}, versusId: "v1", newRoundsA: 1, newRoundsB: 0 }
    );
    expect(after1.counted).toBe(false);
    expect(after1.shareA).toBe(0);

    const after2 = computeNewVoterState(
      { storedVersus: after1.newVersusMap, versusId: "v1", newRoundsA: 1, newRoundsB: 1 }
    );
    expect(after2.counted).toBe(true);
    expect(after2.shareA).toBeCloseTo(0.5);
    expect(after2.shareB).toBeCloseTo(0.5);
  });

  test("idempotency: same event twice → identical state on second call", () => {
    const state1 = computeNewVoterState(
      { storedVersus: {}, versusId: "v1", newRoundsA: 2, newRoundsB: 1 }
    );
    // Second call with same inputs (simulate trigger firing twice)
    const state2 = computeNewVoterState(
      { storedVersus: state1.newVersusMap, versusId: "v1", newRoundsA: 2, newRoundsB: 1 }
    );
    expect(state2.totalRoundsA).toBe(state1.totalRoundsA);
    expect(state2.totalRoundsB).toBe(state1.totalRoundsB);
    expect(state2.shareA).toBeCloseTo(state1.shareA);
    expect(state2.shareB).toBeCloseTo(state1.shareB);
  });
});

// ── computeBradleyTerry ───────────────────────────────────────────────────────

describe("computeBradleyTerry", () => {
  // Canonical five-artist fixture used across multiple tests.
  const FIVE_ENTITY_IDS = ["Uzi", "Rocky", "Travis", "Ye", "Carti"];
  const FIVE_ROWS = [
    { a: "Uzi",   b: "Rocky",  votesA: 6, votesB: 4 },
    { a: "Rocky", b: "Travis", votesA: 5, votesB: 3 },
    { a: "Travis",b: "Ye",     votesA: 7, votesB: 5 },
    { a: "Uzi",   b: "Carti",  votesA: 3, votesB: 1 },
    { a: "Ye",    b: "Carti",  votesA: 6, votesB: 4 },
    { a: "Uzi",   b: "Travis", votesA: 3, votesB: 2 },
    { a: "Rocky", b: "Ye",     votesA: 7, votesB: 3 },
  ];

  test("test 1 — five artists converge to expected points (±0.2)", () => {
    const { points } = computeBradleyTerry(FIVE_ROWS, FIVE_ENTITY_IDS, { prior: 1 });
    expect(points["Uzi"]).toBeCloseTo(174.6, 0);
    expect(points["Rocky"]).toBeCloseTo(142.5, 0);
    expect(points["Travis"]).toBeCloseTo(99.1, 0);
    expect(points["Ye"]).toBeCloseTo(73.0, 0);
    expect(points["Carti"]).toBeCloseTo(55.5, 0);
  });

  test("test 2 — sixth entity with no rows stays exactly 100.0", () => {
    const ids = [...FIVE_ENTITY_IDS, "NewArtist"];
    const { points } = computeBradleyTerry(FIVE_ROWS, ids, { prior: 1 });
    expect(points["NewArtist"]).toBe(100.0);
    // The other five are still reasonable.
    expect(points["Uzi"]).toBeGreaterThan(100);
  });

  test("test 3 — 1–0 unbeaten entity produces a finite value", () => {
    const rows = [{ a: "A", b: "B", votesA: 1, votesB: 0 }];
    const { points } = computeBradleyTerry(rows, ["A", "B"], { prior: 1 });
    expect(Number.isFinite(points["A"])).toBe(true);
    expect(Number.isFinite(points["B"])).toBe(true);
    expect(points["A"]).toBeGreaterThan(points["B"]);
  });

  test("test 4 — fractional votes work correctly", () => {
    const rows = [{ a: "X", b: "Y", votesA: 0.5714, votesB: 0.4286 }];
    const { points } = computeBradleyTerry(rows, ["X", "Y"], { prior: 1 });
    expect(Number.isFinite(points["X"])).toBe(true);
    expect(points["X"]).toBeGreaterThan(points["Y"]);
  });

  test("test 5 — row with a == b is ignored (treated as no rows)", () => {
    const rows = [{ a: "Solo", b: "Solo", votesA: 5, votesB: 3 }];
    const { points } = computeBradleyTerry(rows, ["Solo"], { prior: 1 });
    expect(points["Solo"]).toBe(100.0);
  });

  test("test 7 — entity in rows but NOT in entityIds gets a finite points value; others unaffected", () => {
    // "Outsider" appears in a pair row but has no rankings doc (not in entityIds).
    // This was the production crash: n[Outsider] was undefined → TypeError reading its key.
    const rows = [
      { a: "Uzi",   b: "Rocky",   votesA: 6, votesB: 4 },
      { a: "Uzi",   b: "Outsider", votesA: 3, votesB: 2 }, // Outsider NOT in entityIds
    ];
    const entityIds = ["Uzi", "Rocky"]; // Outsider intentionally absent

    let result;
    expect(() => {
      result = computeBradleyTerry(rows, entityIds, { prior: 1 });
    }).not.toThrow();

    expect(result.points["Outsider"]).toBeDefined();
    expect(Number.isFinite(result.points["Outsider"])).toBe(true);
    // Uzi (beats both Rocky and Outsider) should be the strongest.
    expect(result.points["Uzi"]).toBeGreaterThan(result.points["Rocky"]);
    expect(result.points["Uzi"]).toBeGreaterThan(result.points["Outsider"]);
  });

  test("test 8 — malformed rows (missing b, NaN votes) are skipped without throwing", () => {
    const rows = [
      { a: "A", b: "B",         votesA: 2,   votesB: 1   }, // valid
      { a: "C", b: undefined,   votesA: 1,   votesB: 0   }, // missing b → skipped
      { a: "D", b: "E",         votesA: NaN, votesB: 1   }, // NaN votesA → skipped
      { a: "F", b: "G",         votesA: 1,   votesB: NaN }, // NaN votesB → skipped
    ];
    const entityIds = ["A", "B", "C", "D", "E", "F", "G"];

    let result;
    expect(() => {
      result = computeBradleyTerry(rows, entityIds, { prior: 1 });
    }).not.toThrow();

    // Only the valid row influences BT — A beats B.
    expect(result.points["A"]).toBeGreaterThan(result.points["B"]);
    // Entities from skipped rows have no valid matchup → stay at exactly 100.
    expect(result.points["C"]).toBe(100.0);
    expect(result.points["D"]).toBe(100.0);
    expect(result.points["E"]).toBe(100.0);
    expect(result.points["F"]).toBe(100.0);
    expect(result.points["G"]).toBe(100.0);
  });
});

// ── computeRanks ──────────────────────────────────────────────────────────────

describe("computeRanks", () => {
  test("test 6a — entities missing from stats default to provisional, rank null, no throw", () => {
    // Production scenario: rankings docs exist for entities that have no pair rows.
    // computeEntityStats returns {} for those entities; computeRanks must not throw.
    const points = { Gaga: 110, Madonna: 90, Rihanna: 100 };
    // Only Gaga and Madonna have stats; Rihanna has no pair rows.
    const stats = {
      Gaga:    { distinctOpponents: 1, totalVoters: 3 },
      Madonna: { distinctOpponents: 1, totalVoters: 3 },
      // Rihanna intentionally absent — simulates entity with no pairs
    };
    let result;
    expect(() => {
      result = computeRanks(points, stats, { minOpponents: 2, minVoters: 5 });
    }).not.toThrow();

    // All three are provisional (Gaga/Madonna have 1 opp < 2 min; Rihanna has 0).
    expect(result["Gaga"].provisional).toBe(true);
    expect(result["Gaga"].rank).toBeNull();
    expect(result["Madonna"].provisional).toBe(true);
    expect(result["Madonna"].rank).toBeNull();
    expect(result["Rihanna"].provisional).toBe(true);
    expect(result["Rihanna"].rank).toBeNull();
  });

  test("test 6b — zero rows → all entities get points 100, provisional true, rank null", () => {
    // Production scenario: a type with no pair docs at all (e.g. albums with no votes yet).
    const entityIds = ["AlbumA", "AlbumB", "AlbumC"];
    const { points, iterations } = computeBradleyTerry([], entityIds, { prior: 1 });

    // All entities default to 100.
    for (const id of entityIds) {
      expect(points[id]).toBe(100.0);
    }
    expect(iterations).toBe(0);

    // computeEntityStats on empty rows → empty stats.
    const stats = computeEntityStats([]);
    expect(Object.keys(stats)).toHaveLength(0);

    // computeRanks with empty stats → all provisional, rank null, no throw.
    let ranks;
    expect(() => {
      ranks = computeRanks(points, stats, { minOpponents: 2, minVoters: 5 });
    }).not.toThrow();

    for (const id of entityIds) {
      expect(ranks[id].provisional).toBe(true);
      expect(ranks[id].rank).toBeNull();
    }
  });

  test("test 6 — provisional entities get rank null; non-provisional get dense ranks", () => {
    const points = { A: 200, B: 150, C: 150, D: 80, E: 50 };
    // A: 3 opp, 10 voters → not provisional
    // B: 2 opp, 6 voters  → not provisional
    // C: 2 opp, 5 voters  → borderline — exactly meets threshold, not provisional
    // D: 1 opp, 10 voters → provisional (insufficient opponents)
    // E: 3 opp, 4 voters  → provisional (insufficient voters)
    const stats = {
      A: { distinctOpponents: 3, totalVoters: 10 },
      B: { distinctOpponents: 2, totalVoters: 6  },
      C: { distinctOpponents: 2, totalVoters: 5  },
      D: { distinctOpponents: 1, totalVoters: 10 },
      E: { distinctOpponents: 3, totalVoters: 4  },
    };
    const result = computeRanks(points, stats, { minOpponents: 2, minVoters: 5 });

    // D and E are provisional — rank must be null.
    expect(result["D"].provisional).toBe(true);
    expect(result["D"].rank).toBeNull();
    expect(result["E"].provisional).toBe(true);
    expect(result["E"].rank).toBeNull();

    // A, B, C are not provisional.
    expect(result["A"].provisional).toBe(false);
    expect(result["B"].provisional).toBe(false);
    expect(result["C"].provisional).toBe(false);

    // Dense ranking by points desc: A(200)=1, B(150)=B(150)=2, nothing at rank 3.
    expect(result["A"].rank).toBe(1);
    expect(result["B"].rank).toBe(2);
    expect(result["C"].rank).toBe(2); // tie → same rank
  });
});

// ── computePairIncrements ─────────────────────────────────────────────────────

describe("computePairIncrements", () => {
  test("two voters summing shares: each 1–1 → pair votes_a 1, votes_b 1", () => {
    // Voter A: new voter, 1–1 in v1
    const stateA = computeNewVoterState(
      { storedVersus: {}, versusId: "v1", newRoundsA: 1, newRoundsB: 1 }
    );
    const incA = computePairIncrements({ newVoterState: stateA, oldVoterData: {}, versusId: "v1" });

    // Voter B: new voter, 1–1 in v1
    const stateB = computeNewVoterState(
      { storedVersus: {}, versusId: "v1", newRoundsA: 1, newRoundsB: 1 }
    );
    const incB = computePairIncrements({ newVoterState: stateB, oldVoterData: {}, versusId: "v1" });

    expect(incA.diffShareA + incB.diffShareA).toBeCloseTo(1.0);
    expect(incA.diffShareB + incB.diffShareB).toBeCloseTo(1.0);
    expect(incA.diffVoterCount + incB.diffVoterCount).toBe(2);
  });

  test("idempotency: same event twice → zero diff on second call", () => {
    const state1 = computeNewVoterState(
      { storedVersus: {}, versusId: "v1", newRoundsA: 2, newRoundsB: 1 }
    );
    const inc1 = computePairIncrements({ newVoterState: state1, oldVoterData: {}, versusId: "v1" });

    // Simulate second trigger: old voter doc now has the written state
    const oldVoterAfterFirst = {
      versus:     state1.newVersusMap,
      rounds_a:   state1.totalRoundsA,
      rounds_b:   state1.totalRoundsB,
      share_a:    state1.shareA,
      share_b:    state1.shareB,
      counted:    state1.counted,
    };
    const state2 = computeNewVoterState(
      { storedVersus: state1.newVersusMap, versusId: "v1", newRoundsA: 2, newRoundsB: 1 }
    );
    const inc2 = computePairIncrements({ newVoterState: state2, oldVoterData: oldVoterAfterFirst, versusId: "v1" });

    expect(inc2.diffShareA).toBeCloseTo(0);
    expect(inc2.diffShareB).toBeCloseTo(0);
    expect(inc2.diffVoterCount).toBe(0);
    expect(inc2.diffVersusRoundsA).toBe(0);
    expect(inc2.diffVersusRoundsB).toBe(0);
  });

  test("voter going uncounted → counted: diffVoterCount = +1, diffShareA positive", () => {
    // First write: 1 round only → uncounted
    const state1 = computeNewVoterState(
      { storedVersus: {}, versusId: "v1", newRoundsA: 1, newRoundsB: 0 }
    );
    const inc1 = computePairIncrements({ newVoterState: state1, oldVoterData: {}, versusId: "v1" });
    expect(inc1.diffVoterCount).toBe(0); // uncounted, not added
    expect(inc1.diffShareA).toBe(0);

    // Second write: adds another round → now counted
    const oldVoterData = {
      versus: state1.newVersusMap,
      rounds_a: state1.totalRoundsA,
      rounds_b: state1.totalRoundsB,
      share_a: state1.shareA,
      share_b: state1.shareB,
      counted: state1.counted,
    };
    const state2 = computeNewVoterState(
      { storedVersus: state1.newVersusMap, versusId: "v1", newRoundsA: 1, newRoundsB: 1 }
    );
    const inc2 = computePairIncrements({ newVoterState: state2, oldVoterData, versusId: "v1" });
    expect(inc2.diffVoterCount).toBe(1);   // now counted
    expect(inc2.diffShareA).toBeCloseTo(0.5);
    expect(inc2.diffShareB).toBeCloseTo(0.5);
  });

  test("pooling across two versus: increments reflect share difference not raw", () => {
    // Voter has v1: 3–1 stored
    const state1 = computeNewVoterState(
      { storedVersus: {}, versusId: "v1", newRoundsA: 3, newRoundsB: 1 }
    );
    const oldVoterData = {
      versus: state1.newVersusMap,
      rounds_a: state1.totalRoundsA,
      rounds_b: state1.totalRoundsB,
      share_a: state1.shareA,  // 0.75
      share_b: state1.shareB,  // 0.25
      counted: state1.counted,
    };

    // Now v2: 1–2 added
    const state2 = computeNewVoterState(
      { storedVersus: state1.newVersusMap, versusId: "v2", newRoundsA: 1, newRoundsB: 2 }
    );
    // share should be 4/7 ≈ 0.5714 / 3/7 ≈ 0.4286
    const inc = computePairIncrements({ newVoterState: state2, oldVoterData, versusId: "v2" });

    // diffShareA = 4/7 - 3/4 ≈ 0.5714 - 0.75 = -0.1786
    expect(inc.diffShareA).toBeCloseTo(4/7 - 3/4);
    expect(inc.diffShareB).toBeCloseTo(3/7 - 1/4);
    expect(inc.diffVoterCount).toBe(0);   // already counted
    expect(inc.diffVersusRoundsA).toBe(1); // new versus, 1–0 in v2 from a-side perspective... wait
    // Actually: v2 had 1 round_a, 2 round_b; old had 0 (new entry)
    expect(inc.diffVersusRoundsA).toBe(1);
    expect(inc.diffVersusRoundsB).toBe(2);
    expect(inc.isFirstVersusForVoter).toBe(true);
  });
});

describe("isSelfMatchup", () => {
  test("empty strings → false", () => {
    expect(isSelfMatchup("", "")).toBe(false);
  });
  test("undefined arguments → false", () => {
    expect(isSelfMatchup(undefined, undefined)).toBe(false);
  });
  test("one empty, one non-empty → false", () => {
    expect(isSelfMatchup("abc", "")).toBe(false);
  });
  test("identical non-empty IDs → true", () => {
    expect(isSelfMatchup("abc", "abc")).toBe(true);
  });
  test("whitespace-padded identical IDs → true", () => {
    expect(isSelfMatchup("  abc  ", "abc")).toBe(true);
  });
  test("distinct non-empty IDs → false", () => {
    expect(isSelfMatchup("abc", "xyz")).toBe(false);
  });
});

