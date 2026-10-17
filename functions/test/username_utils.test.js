"use strict";

const { usernameSubstrings } = require("../utils");

describe("usernameSubstrings", () => {
  test("includes every substring of length >= 2", () => {
    const subs = usernameSubstrings("mrnolan");
    for (const q of ["mr", "nolan", "nol", "rnol", "mrnolan", "an"]) {
      expect(subs).toContain(q);
    }
    expect(subs).not.toContain("n");
  });

  test("lowercases, trims and dedupes", () => {
    expect(usernameSubstrings("  AAA ")).toEqual(["aa", "aaa"]);
  });

  test("handles empty / missing input", () => {
    expect(usernameSubstrings("")).toEqual([]);
    expect(usernameSubstrings(undefined)).toEqual([]);
    expect(usernameSubstrings("a")).toEqual([]);
  });

  test("20-char username stays small", () => {
    expect(usernameSubstrings("abcdefghijklmnopqrst").length).toBe(190);
  });
});
