// Emulator tests for onPollWritten's validation: a poll only counts towards
// rankings when it matches the versus it belongs to.
// Requires the Firestore emulator:
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 npx jest test/poll_trigger.test.js

"use strict";

const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST;
const describeEmulator = EMULATOR_HOST ? describe : describe.skip;

let db, handlePollUpsert;

beforeAll(() => {
  if (!EMULATOR_HOST) return;
  const admin = require("firebase-admin");
  if (admin.apps.length === 0) admin.initializeApp({ projectId: "demo-polls" });
  db = admin.firestore();
  ({ _handlePollUpsert: handlePollUpsert } = require("../index"));
});

beforeEach(async () => {
  if (!EMULATOR_HOST) return;
  await Promise.all(["versus", "pairs", "rankings"].map((c) => db.recursiveDelete(db.collection(c))));
});

const ballot = (winners) => winners.map((w, i) => ({ round_number: i, winner: w, isBonus: false }));

const poll = (over = {}) => ({
  versus_id: "v1", voter_id: "voter1", pair_key: "x1_y1", entity_type: "artist",
  entity1_id: "x1", entity1_name: "X", entity2_id: "y1", entity2_name: "Y",
  track_details: ballot(["entity1", "entity1", "entity2"]),
  ...over,
});

async function seedVersus(data) {
  await db.doc("versus/v1").set({
    type: "artist", status: "open", authorID: "author",
    artist1ID: "x1", artist1Name: "X", artist1TrackIDs: ["t1", "t2", "t3"],
    artist2ID: "y1", artist2Name: "Y", artist2TrackIDs: ["u1", "u2", "u3"],
    ...data,
  });
}

const pair = async () => (await db.doc("pairs/x1_y1").get());

describeEmulator("onPollWritten poll validation", () => {
  test("a matching poll is counted", async () => {
    await seedVersus({});
    await handlePollUpsert("v1_voter1", poll());
    const p = await pair();
    expect(p.exists).toBe(true);
    expect(p.get("rounds_a")).toBe(2);
    expect(p.get("rounds_b")).toBe(1);
  });

  test("a poll for a versus that doesn't exist writes nothing", async () => {
    await handlePollUpsert("v1_voter1", poll());
    expect((await pair()).exists).toBe(false);
    expect((await db.collection("rankings").get()).empty).toBe(true);
  });

  test("a poll naming other entities than its versus writes nothing", async () => {
    await seedVersus({});
    await handlePollUpsert("v1_voter1", poll({ entity2_id: "z9", pair_key: "x1_z9" }));
    expect((await db.doc("pairs/x1_z9").get()).exists).toBe(false);
  });

  test("a poll with the sides swapped writes nothing (it would flip the result)", async () => {
    await seedVersus({});
    await handlePollUpsert("v1_voter1", poll({ entity1_id: "y1", entity2_id: "x1" }));
    expect((await pair()).exists).toBe(false);
  });

  test("a poll on a one-sided versus writes nothing", async () => {
    await seedVersus({ type: "collaboration", artist2ID: "" });
    await handlePollUpsert("v1_voter1", poll());
    expect((await pair()).exists).toBe(false);
  });

  test("names and type come from the versus, not the poll", async () => {
    await seedVersus({});
    await handlePollUpsert("v1_voter1", poll({
      entity1_name: "<b>injected</b>", entity2_name: "spam", entity_type: "album",
    }));
    const p = await pair();
    expect(p.get("entity_type")).toBe("artist");
    expect(p.get("entity_a.entity_name")).toBe("X");
    expect(p.get("entity_b.entity_name")).toBe("Y");
    expect((await db.doc("rankings/x1").get()).get("entity_name")).toBe("X");
  });

  test("stuffed or duplicate rounds are capped to the versus's length", async () => {
    await seedVersus({});
    const stuffed = [
      ...ballot(Array(40).fill("entity1")),
      { round_number: 0, winner: "entity1", isBonus: false },
    ];
    await handlePollUpsert("v1_voter1", poll({ track_details: stuffed }));
    expect((await pair()).get("rounds_a")).toBe(3);
  });
});
