// Unit tests for the helpers onPollWritten uses to validate a poll against
// the versus it belongs to (no emulator needed).

"use strict";

const { resolveVersusSides, sanitizeTrackDetails, countRounds } = require("../utils");

// ── resolveVersusSides ────────────────────────────────────────────────────────

describe("resolveVersusSides", () => {
  test("album versus uses album fields and the shorter tracklist as the round cap", () => {
    expect(resolveVersusSides({
      type: "album",
      album1ID: "a1", album1Name: "First", album1Tracklist: [{}, {}, {}],
      album2ID: "a2", album2Name: "Second", album2Tracklist: [{}, {}],
    })).toEqual({
      entityType: "album",
      entity1Id: "a1", entity1Name: "First",
      entity2Id: "a2", entity2Name: "Second",
      maxPairedRounds: 2,
    });
  });

  test("legacy versus with no type is treated as an album versus", () => {
    expect(resolveVersusSides({ album1ID: "a1", album2ID: "a2" }).entityType).toBe("album");
  });

  test.each(["artist", "collaboration", "collaborator"])(
    "%s versus uses artist fields", (type) => {
      const sides = resolveVersusSides({
        type,
        artist1ID: "x1", artist1Name: "X", artist1TrackIDs: ["t1", "t2", "t3"],
        artist2ID: "y1", artist2Name: "Y", artist2TrackIDs: ["u1", "u2", "u3"],
      });
      expect(sides).toMatchObject({
        entityType: "artist", entity1Id: "x1", entity2Id: "y1", maxPairedRounds: 3,
      });
    });

  test("returns null when a side hasn't been filled in yet", () => {
    expect(resolveVersusSides({ type: "collaboration", artist1ID: "x1" })).toBeNull();
    expect(resolveVersusSides({ type: "album", album1ID: "a1", album2ID: "  " })).toBeNull();
    expect(resolveVersusSides(undefined)).toBeNull();
  });

  test("no round cap when the doc doesn't record its tracks", () => {
    expect(resolveVersusSides({ album1ID: "a1", album2ID: "a2" }).maxPairedRounds).toBeNull();
  });

  test("ignores non-string IDs", () => {
    expect(resolveVersusSides({ album1ID: 123, album2ID: "a2" })).toBeNull();
  });
});

// ── sanitizeTrackDetails ──────────────────────────────────────────────────────

describe("sanitizeTrackDetails", () => {
  const round = (n, winner, isBonus = false) => ({ round_number: n, winner, isBonus });

  test("keeps a normal ballot unchanged", () => {
    const details = [round(0, "entity1"), round(1, "entity2"), round(2, "entity1", true)];
    expect(sanitizeTrackDetails(details, 2)).toEqual(details);
  });

  test("duplicate rounds count once (first wins)", () => {
    const stuffed = [round(0, "entity1"), round(0, "entity1"), round(0, "entity1"), round(1, "entity2")];
    const { roundsEntity1, roundsEntity2 } = countRounds(sanitizeTrackDetails(stuffed, 5));
    expect([roundsEntity1, roundsEntity2]).toEqual([1, 1]);
  });

  test("head-to-head rounds beyond the versus's length are dropped", () => {
    const stuffed = Array.from({ length: 50 }, (_, i) => round(i, "entity1"));
    expect(countRounds(sanitizeTrackDetails(stuffed, 3)).roundsEntity1).toBe(3);
  });

  test("bonus rounds past the cap are kept (they never count)", () => {
    expect(sanitizeTrackDetails([round(7, "entity1", true)], 3)).toHaveLength(1);
  });

  test("no cap when maxPairedRounds is null", () => {
    expect(sanitizeTrackDetails([round(40, "entity1")], null)).toHaveLength(1);
  });

  test("drops malformed entries and non-arrays", () => {
    expect(sanitizeTrackDetails([null, "x", { winner: "entity1" }, round(-1, "entity1"),
      round(1.5, "entity1")], 5)).toEqual([]);
    expect(sanitizeTrackDetails("nope", 5)).toEqual([]);
  });
});
