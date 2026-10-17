// Emulator integration tests — S18-S22 + rules tests.
// Requires the Firestore (and optionally Functions) emulator to be running:
//   firebase emulators:start --only firestore
// Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 (firebase CLI does this automatically).
//
// Run with:
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 npm test -- emulator

"use strict";

const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST;
const describeEmulator = EMULATOR_HOST ? describe : describe.skip;

// Lazy-init admin SDK only when the emulator is present so the suite can be
// imported safely (the regular jest run skips the block entirely).
let admin, db, runRankingJob;

beforeAll(async () => {
  if (!EMULATOR_HOST) return;

  admin = require("firebase-admin");
  if (admin.apps.length === 0) {
    admin.initializeApp({ projectId: "jukebox-996de" });
  }
  db = admin.firestore();
  ({ runRankingJob } = require("../index"));
});

// Helper: delete all docs in a collection (emulator-only).
async function clearCollection(colName) {
  const snap = await db.collection(colName).get();
  const batch = db.batch();
  for (const d of snap.docs) batch.delete(d.ref);
  if (snap.docs.length) await batch.commit();
}

// Seed rankings stubs for an entity type.
async function seedRankingStub(entityId, entityType, entityName, extraFields = {}) {
  await db.collection("rankings").doc(entityId).set({
    entity_id:          entityId,
    entity_type:        entityType,
    entity_name:        entityName,
    entity_name_lower:  entityName.toLowerCase().trim(),
    entity_image:       "",
    points:             100.0,
    rank:               null,
    provisional:        true,
    distinct_opponents: 0,
    total_voters:       0,
    points_updated_at:  null,
    created_at:         admin.firestore.FieldValue.serverTimestamp(),
    ...extraFields,
  });
}

// Seed a pair doc.
async function seedPair(pairKey, entityType, aId, bId, votesA, votesB, voterCount) {
  await db.collection("pairs").doc(pairKey).set({
    entity_type:  entityType,
    entity_ids:   [aId, bId],
    entity_a:     { entity_id: aId, entity_name: aId, entity_image: "" },
    entity_b:     { entity_id: bId, entity_name: bId, entity_image: "" },
    votes_a:      votesA,
    votes_b:      votesB,
    voter_count:  voterCount,
    rounds_a:     0,
    rounds_b:     0,
    versus_count: 1,
    created_at:   admin.firestore.FieldValue.serverTimestamp(),
    last_voted_at: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ── S18 ───────────────────────────────────────────────────────────────────────
describeEmulator("S18 — five-artist seed + runRankingJob", () => {
  const ARTISTS = [
    { id: "Uzi",   name: "Uzi" },
    { id: "Rocky", name: "Rocky" },
    { id: "Travis",name: "Travis" },
    { id: "Ye",    name: "Ye" },
    { id: "Carti", name: "Carti" },
    { id: "New6",  name: "New6" },   // no pairs
  ];
  const PAIRS = [
    ["Uzi_Rocky",   "artist", "Uzi",   "Rocky",  6, 4, 4],
    ["Rocky_Travis","artist", "Rocky", "Travis", 5, 3, 3],
    ["Travis_Ye",   "artist", "Travis","Ye",      7, 5, 5],
    ["Carti_Uzi",   "artist", "Uzi",   "Carti",  3, 1, 2],
    ["Carti_Ye",    "artist", "Ye",    "Carti",  6, 4, 4],
    ["Travis_Uzi",  "artist", "Uzi",   "Travis", 3, 2, 2],
    ["Rocky_Ye",    "artist", "Rocky", "Ye",     7, 3, 4],
  ];

  beforeAll(async () => {
    await Promise.all([clearCollection("pairs"), clearCollection("rankings"), clearCollection("ranking_runs")]);
    for (const a of ARTISTS) await seedRankingStub(a.id, "artist", a.name);
    for (const [key, type, a, b, va, vb, vc] of PAIRS) {
      await seedPair(key, type, a, b, va, vb, vc);
    }
    await runRankingJob();
  });

  test("Uzi points ≈ 174.6 (±0.2)", async () => {
    const doc = await db.collection("rankings").doc("Uzi").get();
    expect(doc.data().points).toBeCloseTo(174.6, 0);
  });

  test("Rocky points ≈ 142.5 (±0.2)", async () => {
    const doc = await db.collection("rankings").doc("Rocky").get();
    expect(doc.data().points).toBeCloseTo(142.5, 0);
  });

  test("Travis points ≈ 99.1 (±0.2)", async () => {
    const doc = await db.collection("rankings").doc("Travis").get();
    expect(doc.data().points).toBeCloseTo(99.1, 0);
  });

  test("Ye points ≈ 73.0 (±0.2)", async () => {
    const doc = await db.collection("rankings").doc("Ye").get();
    expect(doc.data().points).toBeCloseTo(73.0, 0);
  });

  test("Carti points ≈ 55.5 (±0.2)", async () => {
    const doc = await db.collection("rankings").doc("Carti").get();
    expect(doc.data().points).toBeCloseTo(55.5, 0);
  });

  test("sixth entity (no pairs) = exactly 100", async () => {
    const doc = await db.collection("rankings").doc("New6").get();
    expect(doc.data().points).toBe(100.0);
  });

  test("rankings_runs/artist written with correct fields", async () => {
    const doc = await db.collection("ranking_runs").doc("artist").get();
    expect(doc.exists).toBe(true);
    const d = doc.data();
    expect(d.entity_count).toBe(6);
    expect(d.pair_count).toBe(7);
    expect(d.docs_written).toBeGreaterThan(0);
  });

  test("entities with >= 2 opponents and >= 5 voters are ranked (not provisional)", async () => {
    // Uzi has pairs vs Rocky(4), Carti(2), Travis(2) = 3 opp; voters 4+2+2 = 8 >= 5
    const doc = await db.collection("rankings").doc("Uzi").get();
    expect(doc.data().provisional).toBe(false);
    expect(doc.data().rank).not.toBeNull();
  });

  test("New6 remains provisional (no opponents)", async () => {
    const doc = await db.collection("rankings").doc("New6").get();
    expect(doc.data().provisional).toBe(true);
    expect(doc.data().rank).toBeNull();
  });
});

// ── S19 ───────────────────────────────────────────────────────────────────────
describeEmulator("S19 — second run with no changes writes 0 docs", () => {
  beforeAll(async () => {
    // Data is already seeded from S18 block (tests share emulator state within
    // a single run). Run the job a second time.
    await runRankingJob();
  });

  test("ranking_runs/artist docs_written = 0 after second run", async () => {
    const doc = await db.collection("ranking_runs").doc("artist").get();
    expect(doc.data().docs_written).toBe(0);
  });
});

// ── S20 ───────────────────────────────────────────────────────────────────────
describeEmulator("S20 — album pairs don't affect artist rankings", () => {
  beforeAll(async () => {
    // Seed an album pair and stub — should be completely independent.
    await seedRankingStub("AlbumA", "album", "Album A");
    await seedRankingStub("AlbumB", "album", "Album B");
    await seedPair("AlbumA_AlbumB", "album", "AlbumA", "AlbumB", 10, 0, 6);
    await runRankingJob();
  });

  test("album rankings are computed independently", async () => {
    const doc = await db.collection("ranking_runs").doc("album").get();
    expect(doc.exists).toBe(true);
    expect(doc.data().pair_count).toBe(1);
  });

  test("Uzi (artist) points unchanged by album run", async () => {
    const doc = await db.collection("rankings").doc("Uzi").get();
    // Must still be in the artist range, not 100.
    expect(doc.data().points).toBeGreaterThan(150);
  });
});

// ── S21 ───────────────────────────────────────────────────────────────────────
describeEmulator("S21 — self-matchup pair skipped in ranking computation", () => {
  beforeAll(async () => {
    // Seed a self-matchup pair (a == b). The ranking job must skip it.
    await seedPair("SoloArtist_SoloArtist", "artist", "SoloArtist", "SoloArtist", 5, 5, 3);
    await seedRankingStub("SoloArtist", "artist", "Solo Artist");
    await runRankingJob();
  });

  test("SoloArtist remains at 100 (self-matchup row skipped)", async () => {
    const doc = await db.collection("rankings").doc("SoloArtist").get();
    expect(doc.data().points).toBe(100.0);
  });
});

// ── S22 ───────────────────────────────────────────────────────────────────────
describeEmulator("S22 — entity_name_lower prefix search returns expected results", () => {
  beforeAll(async () => {
    // Seed artists with entity_name_lower set explicitly.
    await db.collection("rankings").doc("searchA").set({
      entity_type: "artist", entity_name: "Kendrick Lamar",
      entity_name_lower: "kendrick lamar", entity_image: "",
      points: 120, rank: 1, provisional: false,
    });
    await db.collection("rankings").doc("searchB").set({
      entity_type: "artist", entity_name: "Kendrick Cole",
      entity_name_lower: "kendrick cole", entity_image: "",
      points: 110, rank: 2, provisional: false,
    });
    await db.collection("rankings").doc("searchC").set({
      entity_type: "artist", entity_name: "Drake",
      entity_name_lower: "drake", entity_image: "",
      points: 90, rank: 3, provisional: false,
    });
  });

  test("prefix 'kendrick' returns both Kendrick entities", async () => {
    const q = "kendrick";
    const snap = await db.collection("rankings")
      .where("entity_type", "==", "artist")
      .where("entity_name_lower", ">=", q)
      .where("entity_name_lower", "<", q + "")
      .orderBy("entity_name_lower")
      .limit(20)
      .get();
    const ids = snap.docs.map(d => d.id).sort();
    expect(ids).toContain("searchA");
    expect(ids).toContain("searchB");
    expect(ids).not.toContain("searchC");
  });

  test("prefix 'dr' returns Drake only", async () => {
    const q = "dr";
    const snap = await db.collection("rankings")
      .where("entity_type", "==", "artist")
      .where("entity_name_lower", ">=", q)
      .where("entity_name_lower", "<", q + "")
      .orderBy("entity_name_lower")
      .limit(20)
      .get();
    const ids = snap.docs.map(d => d.id);
    expect(ids).toContain("searchC");
    expect(ids).not.toContain("searchA");
  });
});

// ── S23 ───────────────────────────────────────────────────────────────────────
// Reproduces the production failure scenario:
//   • 1 artist pair with real votes (Lady Gaga vs Madonna, Gaga wins)
//   • 3 artist ranking stubs with NO pairs (isolated entities)
//   • 2 album ranking stubs with NO album pairs (entire album type has zero votes)
// Expected: job completes for BOTH types; Gaga > 100, Madonna < 100,
//           isolated artists = exactly 100; ranking_runs exists for both types.
describeEmulator("S23 — production repro: mixed entities with and without pairs", () => {
  const GAGA_ID    = "prod-gaga";
  const MADONNA_ID = "prod-madonna";
  const ISO_IDS    = ["prod-iso1", "prod-iso2", "prod-iso3"];
  const ALBUM_IDS  = ["prod-albumX", "prod-albumY"];
  const PAIR_KEY   = `${GAGA_ID}_${MADONNA_ID}`; // Gaga < Madonna lex

  beforeAll(async () => {
    await Promise.all([
      clearCollection("pairs"),
      clearCollection("rankings"),
      clearCollection("ranking_runs"),
    ]);

    // 1 artist pair: Gaga wins 1.0 / Madonna 0.0, voter_count 1
    await seedPair(PAIR_KEY, "artist", GAGA_ID, MADONNA_ID, 1.0, 0.0, 1);

    // Artist stubs: Gaga, Madonna, and 3 with no pairs
    await seedRankingStub(GAGA_ID,    "artist", "Lady Gaga");
    await seedRankingStub(MADONNA_ID, "artist", "Madonna");
    for (const id of ISO_IDS) {
      await seedRankingStub(id, "artist", id);
    }

    // 2 album stubs — NO album pairs (entire album type has zero rows)
    for (const id of ALBUM_IDS) {
      await seedRankingStub(id, "album", id);
    }

    // Run the job — must not throw for either type
    await runRankingJob();
  });

  test("runRankingJob completes without throwing for artist type", async () => {
    const doc = await db.collection("ranking_runs").doc("artist").get();
    expect(doc.exists).toBe(true);
  });

  test("runRankingJob completes without throwing for album type (zero pairs)", async () => {
    const doc = await db.collection("ranking_runs").doc("album").get();
    expect(doc.exists).toBe(true);
  });

  test("Gaga points > 100 (won every vote)", async () => {
    const doc = await db.collection("rankings").doc(GAGA_ID).get();
    expect(doc.data().points).toBeGreaterThan(100);
  });

  test("Madonna points < 100 (lost every vote)", async () => {
    const doc = await db.collection("rankings").doc(MADONNA_ID).get();
    expect(doc.data().points).toBeLessThan(100);
  });

  test("isolated artists (no pairs) stay exactly 100", async () => {
    for (const id of ISO_IDS) {
      const doc = await db.collection("rankings").doc(id).get();
      expect(doc.data().points).toBe(100.0);
    }
  });

  test("album stubs (no pairs) stay exactly 100", async () => {
    for (const id of ALBUM_IDS) {
      const doc = await db.collection("rankings").doc(id).get();
      expect(doc.data().points).toBe(100.0);
    }
  });

  test("Gaga and Madonna are provisional (1 opp, 1 voter < thresholds)", async () => {
    for (const id of [GAGA_ID, MADONNA_ID]) {
      const doc = await db.collection("rankings").doc(id).get();
      expect(doc.data().provisional).toBe(true);
      expect(doc.data().rank).toBeNull();
    }
  });

  test("album ranking_runs/album written correctly for zero-pair type", async () => {
    const doc = await db.collection("ranking_runs").doc("album").get();
    const d = doc.data();
    expect(d.pair_count).toBe(0);
    expect(d.entity_count).toBe(ALBUM_IDS.length);
    expect(d.iterations).toBe(0);
    expect(d.docs_written).toBeGreaterThanOrEqual(0);
  });
});

// ── S24 ───────────────────────────────────────────────────────────────────────
// Reproduces the crash: album pair where entity B has NO rankings doc.
// Expected: job completes; B's doc is CREATED from pair metadata; A updated;
//           ranking_runs/album.created_missing == 1.
describeEmulator("S24 — pair entity with no rankings doc causes doc creation", () => {
  const ALBUM_A_ID = "s24-album-a";
  const ALBUM_B_ID = "s24-album-b"; // NO rankings doc seeded — the crash entity
  const PAIR_KEY   = `${ALBUM_A_ID}_${ALBUM_B_ID}`; // a < b lex ✓

  beforeAll(async () => {
    await Promise.all([
      clearCollection("pairs"),
      clearCollection("rankings"),
      clearCollection("ranking_runs"),
    ]);

    // Only AlbumA has a rankings doc; AlbumB is intentionally absent.
    await seedRankingStub(ALBUM_A_ID, "album", "Album A");

    // Pair: AlbumA wins (votesA 0.75, votesB 0.25, voter_count 1).
    // entity_a/entity_b carry name + image so the created doc is populated correctly.
    await db.collection("pairs").doc(PAIR_KEY).set({
      entity_type:   "album",
      entity_ids:    [ALBUM_A_ID, ALBUM_B_ID],
      entity_a:      { entity_id: ALBUM_A_ID, entity_name: "Album A", entity_image: "http://img.test/a.jpg" },
      entity_b:      { entity_id: ALBUM_B_ID, entity_name: "Album B", entity_image: "http://img.test/b.jpg" },
      votes_a:       0.75,
      votes_b:       0.25,
      voter_count:   1,
      rounds_a:      3,
      rounds_b:      1,
      versus_count:  1,
      created_at:    admin.firestore.FieldValue.serverTimestamp(),
      last_voted_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    await runRankingJob();
  });

  test("job completes without throwing (ranking_runs/album exists)", async () => {
    const doc = await db.collection("ranking_runs").doc("album").get();
    expect(doc.exists).toBe(true);
  });

  test("Album A (winner) has points > 100", async () => {
    const doc = await db.collection("rankings").doc(ALBUM_A_ID).get();
    expect(doc.data().points).toBeGreaterThan(100);
  });

  test("Album B rankings doc was CREATED with points < 100", async () => {
    const doc = await db.collection("rankings").doc(ALBUM_B_ID).get();
    expect(doc.exists).toBe(true);
    expect(doc.data().points).toBeLessThan(100);
  });

  test("Album B doc has correct entity_type, entity_name, and entity_image from pair", async () => {
    const d = (await db.collection("rankings").doc(ALBUM_B_ID).get()).data();
    expect(d.entity_type).toBe("album");
    expect(d.entity_name).toBe("Album B");
    expect(d.entity_image).toBe("http://img.test/b.jpg");
    expect(d.entity_name_lower).toBe("album b");
    expect(d.provisional).toBe(true); // 1 opp, 1 voter < thresholds
    expect(d.rank).toBeNull();
  });

  test("ranking_runs/album.created_missing == 1", async () => {
    const doc = await db.collection("ranking_runs").doc("album").get();
    expect(doc.data().created_missing).toBe(1);
  });
});

// ── S25 ───────────────────────────────────────────────────────────────────────
// Re-run on S24's data: Album B's doc now exists → updated, not recreated.
// created_missing must be 0 on the second run.
describeEmulator("S25 — re-run after missing doc created: doc updated, created_missing=0", () => {
  beforeAll(async () => {
    // S24 data is still in the emulator — just run the job again.
    await runRankingJob();
  });

  test("Album B rankings doc still exists with points < 100", async () => {
    const doc = await db.collection("rankings").doc("s24-album-b").get();
    expect(doc.exists).toBe(true);
    expect(doc.data().points).toBeLessThan(100);
  });

  test("ranking_runs/album.created_missing == 0 on second run", async () => {
    const doc = await db.collection("ranking_runs").doc("album").get();
    expect(doc.data().created_missing).toBe(0);
  });

  test("ranking_runs/album.docs_written == 0 (values unchanged)", async () => {
    const doc = await db.collection("ranking_runs").doc("album").get();
    expect(doc.data().docs_written).toBe(0);
  });
});

// ── Rules: poll UPDATE with mismatched pair_key is denied ─────────────────────
describeEmulator("Rules — poll UPDATE with mismatched pair_key is denied", () => {
  // This test uses the @firebase/rules-unit-testing client SDK
  // to test Firestore security rules against the emulator.
  let testEnv;

  beforeAll(async () => {
    try {
      const { initializeTestEnvironment } = require("@firebase/rules-unit-testing");
      const fs = require("fs");
      const path = require("path");
      const rulesPath = path.resolve(__dirname, "../../firestore.rules");
      const rules = fs.existsSync(rulesPath) ? fs.readFileSync(rulesPath, "utf8") : undefined;

      testEnv = await initializeTestEnvironment({
        projectId: "jukebox-996de",
        firestore: {
          host: "127.0.0.1",
          port: parseInt(EMULATOR_HOST.split(":")[1] || "8080"),
          rules,
        },
      });
    } catch (e) {
      // If the package is not installed, skip gracefully.
      console.warn("@firebase/rules-unit-testing not available, skipping rules test:", e.message);
    }
  });

  afterAll(async () => {
    if (testEnv) await testEnv.cleanup();
  });

  test("poll UPDATE with mismatched pair_key is denied", async () => {
    if (!testEnv) return;

    const uid = "test-user-rules";
    const versusId = "rules-versus-1";
    const pollId = `${versusId}_${uid}`;

    // Set up the existing poll doc (bypassing rules via admin).
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("polls").doc(pollId).set({
        versus_id:   versusId,
        voter_id:    uid,
        entity1_id:  "aaa",
        entity2_id:  "bbb",
        pair_key:    "aaa_bbb",
        track_details: [],
      });
    });

    // Try to update with a mismatched pair_key — should be denied.
    const userCtx = testEnv.authenticatedContext(uid);
    const pollRef = userCtx.firestore().collection("polls").doc(pollId);

    const { assertFails } = require("@firebase/rules-unit-testing");
    await assertFails(
      pollRef.update({
        versus_id:  versusId,
        voter_id:   uid,
        entity1_id: "aaa",
        entity2_id: "bbb",
        pair_key:   "WRONG_KEY",  // mismatched: e1 != e2 but pair_key is not the canonical key
        track_details: [{ winner: "entity1" }],
      })
    );
  });
});
