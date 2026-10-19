// Firestore security rules tests. Each describe block pins down one hole
// found in the security audit so it can't silently reopen.
// Requires the Firestore emulator:
//   firebase emulators:exec --only firestore --project demo-rules \
//     "npx jest test/rules.test.js"

"use strict";

const fs = require("fs");
const path = require("path");

const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST;
const describeEmulator = EMULATOR_HOST ? describe : describe.skip;

let testEnv, assertSucceeds, assertFails;

beforeAll(async () => {
  if (!EMULATOR_HOST) return;
  const rut = require("@firebase/rules-unit-testing");
  ({ assertSucceeds, assertFails } = rut);
  const [host, port] = EMULATOR_HOST.split(":");
  testEnv = await rut.initializeTestEnvironment({
    projectId: "demo-rules",
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8"),
      host,
      port: Number(port),
    },
  });
});

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  if (testEnv) await testEnv.clearFirestore();
});

const asUser = (uid) => testEnv.authenticatedContext(uid).firestore();

async function seed(docPath, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(docPath).set(data);
  });
}

// Mirrors FirebaseService._writeProfileClaimingUsername: profile + claim in one batch.
function createProfile(db, uid, profile) {
  const batch = db.batch();
  batch.set(db.doc(`users/${uid}`), { username: "alice", ...profile });
  batch.set(db.doc("usernames/alice"), { uid });
  return batch.commit();
}

describeEmulator("users/{uid}: email must never be stored", () => {
  test("creating a profile without email is allowed", async () => {
    await assertSucceeds(createProfile(asUser("alice"), "alice", { bio: "" }));
  });

  test("creating a profile with email is rejected", async () => {
    await assertFails(createProfile(asUser("alice"), "alice", { email: "a@x.com" }));
  });

  test("adding email to an existing profile is rejected", async () => {
    await seed("users/alice", { username: "alice", bio: "" });
    await assertFails(asUser("alice").doc("users/alice").update({ email: "a@x.com" }));
  });

  describe("legacy doc that still has an email", () => {
    beforeEach(() => seed("users/alice", { username: "alice", bio: "", email: "a@x.com" }));

    test("editing other fields still works", async () => {
      await assertSucceeds(asUser("alice").doc("users/alice").update({ bio: "hi" }));
    });

    test("removing the email is allowed", async () => {
      const { FieldValue } = require("firebase/compat/app").default.firestore;
      await assertSucceeds(
        asUser("alice").doc("users/alice").update({ email: FieldValue.delete() }));
    });

    test("changing the email is rejected", async () => {
      await assertFails(asUser("alice").doc("users/alice").update({ email: "b@x.com" }));
    });
  });
});
