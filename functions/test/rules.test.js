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

const fieldValue = () => require("firebase/compat/app").default.firestore.FieldValue;
const IMG = "https://i.scdn.co/image/ab67616d0000b273abcdef";

describeEmulator("versus: authorship on create", () => {
  test("album versus authored by the caller is allowed", async () => {
    await assertSucceeds(asUser("alice").collection("versus").add(
      { type: "album", status: "open", Author: "alice", album1ID: "a", album2ID: "b" }));
  });

  test("artist versus authored by the caller is allowed", async () => {
    await assertSucceeds(asUser("alice").collection("versus").add(
      { type: "artist", status: "open", authorID: "alice", artist1ID: "a" }));
  });

  test("versus attributed to someone else is rejected", async () => {
    await assertFails(asUser("mallory").collection("versus").add(
      { type: "album", status: "open", Author: "alice" }));
    await assertFails(asUser("mallory").collection("versus").add(
      { type: "artist", status: "open", authorID: "alice" }));
  });

  test("versus with no author is rejected", async () => {
    await assertFails(asUser("mallory").collection("versus").add({ type: "album" }));
  });

  describe("post remix (author = source post's author)", () => {
    beforeEach(() => seed("posts/p1", { authorID: "bob" }));
    const remix = (over) => ({
      type: "collaborator", status: "open", sourcePostID: "p1",
      authorID: "bob", collaboratorID: "alice", ...over,
    });

    test("remixer may create it", async () => {
      await assertSucceeds(asUser("alice").collection("versus").add(remix({})));
    });

    test("naming someone other than the post's author is rejected", async () => {
      await assertFails(asUser("alice").collection("versus").add(remix({ authorID: "carol" })));
    });

    test("a missing source post is rejected", async () => {
      await assertFails(asUser("alice").collection("versus").add(remix({ sourcePostID: "nope" })));
    });

    test("the caller must be the collaborator", async () => {
      await assertFails(asUser("alice").collection("versus").add(remix({ collaboratorID: "carol" })));
    });
  });
});

describeEmulator("versus: updates by non-authors", () => {
  beforeEach(() => seed("versus/v1", {
    type: "album", status: "open", Author: "alice", album1ID: "a", album2ID: "b",
    album1ImageUrl: IMG,
  }));

  test("changing type is rejected", async () => {
    await assertFails(asUser("mallory").doc("versus/v1").update({ type: "artist" }));
  });

  test("filling an empty image with a Spotify URL is allowed", async () => {
    await assertSucceeds(asUser("bob").doc("versus/v1").update({ album2ImageUrl: IMG }));
  });

  test("filling an empty image with a non-Spotify URL is rejected", async () => {
    await assertFails(asUser("mallory").doc("versus/v1").update(
      { album2ImageUrl: "https://evil.example/x.png" }));
    await assertFails(asUser("mallory").doc("versus/v1").update(
      { album2ImageUrl: "https://i.scdn.co.evil.example/image/x" }));
  });

  test("overwriting an existing image is rejected", async () => {
    await assertFails(asUser("mallory").doc("versus/v1").update(
      { album1ImageUrl: "https://i.scdn.co/image/other" }));
  });

  test("re-sending an unchanged image alongside a new one is allowed", async () => {
    await assertSucceeds(asUser("bob").doc("versus/v1").update(
      { album1ImageUrl: IMG, album2ImageUrl: IMG }));
  });

  test("the author can still edit their versus", async () => {
    await assertSucceeds(asUser("alice").doc("versus/v1").update({ status: "closed" }));
  });
});

describeEmulator("notifications", () => {
  const follow = (over) => ({
    type: "follow", read: false, followerID: "alice",
    follower_username: "alice", follower_avatar: "", follower_bio: "", ...over,
  });

  test("follow keyed by the follower's uid is allowed", async () => {
    await assertSucceeds(asUser("alice").doc("users/bob/notifications/alice").set(follow({})));
  });

  test("follow under any other doc ID is rejected (no spam)", async () => {
    await assertFails(asUser("alice").doc("users/bob/notifications/x1").set(follow({})));
  });

  test("notifying yourself is rejected", async () => {
    await assertFails(asUser("alice").doc("users/alice/notifications/alice").set(follow({})));
  });

  test("extra fields or pre-read notifications are rejected", async () => {
    await assertFails(asUser("alice").doc("users/bob/notifications/alice")
      .set(follow({ message: "click this link" })));
    await assertFails(asUser("alice").doc("users/bob/notifications/alice")
      .set(follow({ read: true })));
  });

  describe("invite", () => {
    beforeEach(() => seed("versus/v1",
      { type: "collaboration", status: "incomplete", authorID: "alice", collaboratorID: "bob" }));
    const invite = { type: "invite", read: false, authorID: "alice", authorName: "alice",
      author_avatar: "", versusID: "v1", artist1ID: "a", artist1Name: "A", artist2Name: "" };

    test("author may invite the versus's collaborator", async () => {
      await assertSucceeds(asUser("alice").collection("users/bob/notifications").add(invite));
    });

    test("inviting someone who isn't the collaborator is rejected", async () => {
      await assertFails(asUser("alice").collection("users/carol/notifications").add(invite));
    });

    test("a non-author can't send an invite for the versus", async () => {
      await assertFails(asUser("mallory").collection("users/bob/notifications")
        .add({ ...invite, authorID: "mallory" }));
    });

    test("an invite for a missing versus is rejected", async () => {
      await assertFails(asUser("alice").collection("users/bob/notifications")
        .add({ ...invite, versusID: "nope" }));
    });
  });

  describe("mention", () => {
    beforeEach(() => seed("posts/p1", { authorID: "alice", mentionedUids: ["bob"] }));
    const mention = { type: "mention", read: false, authorID: "alice", authorName: "alice",
      author_avatar: "", postID: "p1" };

    test("post author may notify a mentioned user", async () => {
      await assertSucceeds(asUser("alice").collection("users/bob/notifications").add(mention));
    });

    test("notifying a user the post doesn't mention is rejected", async () => {
      await assertFails(asUser("alice").collection("users/carol/notifications").add(mention));
    });
  });
});

describeEmulator("posts: counters", () => {
  beforeEach(() => seed("posts/p1", { authorID: "alice", Remixcount: 3, Sharecount: 0 }));

  test("anyone may bump Remixcount by one", async () => {
    await assertSucceeds(asUser("bob").doc("posts/p1")
      .update({ Remixcount: fieldValue().increment(1) }));
  });

  test("setting a counter to an arbitrary value is rejected", async () => {
    await assertFails(asUser("bob").doc("posts/p1").update({ Remixcount: 9999 }));
    await assertFails(asUser("bob").doc("posts/p1").update({ Sharecount: -5 }));
  });

  test("bumping a counter that was never set starts from zero", async () => {
    await seed("posts/p2", { authorID: "alice" });
    await assertSucceeds(asUser("bob").doc("posts/p2")
      .update({ Sharecount: fieldValue().increment(1) }));
  });
});

describeEmulator("polls", () => {
  const newPoll = (over = {}) => ({
    versus_id: "v1", voter_id: "alice", entity_type: "artist",
    entity1_id: "x1", entity2_id: "y1", pair_key: "x1_y1", track_details: [], ...over,
  });

  test("voting on an existing versus is allowed", async () => {
    await seed("versus/v1", { type: "artist", authorID: "bob" });
    await assertSucceeds(asUser("alice").doc("polls/v1_alice").set(newPoll()));
  });

  test("voting on a versus that doesn't exist is rejected", async () => {
    await assertFails(asUser("alice").doc("polls/v1_alice").set(newPoll()));
  });

  describe("after voting", () => {
    beforeEach(() => seed("polls/v1_alice", newPoll()));

    test("changing the ballot is allowed", async () => {
      await assertSucceeds(asUser("alice").doc("polls/v1_alice")
        .update({ track_details: [{ round_number: 0, winner: "entity1" }] }));
    });

    test("re-sending the same identity fields is allowed", async () => {
      await assertSucceeds(asUser("alice").doc("polls/v1_alice").update(
        { entity_type: "artist", entity1_id: "x1", entity2_id: "y1", pair_key: "x1_y1" }));
    });

    test("switching the poll to other entities is rejected", async () => {
      await assertFails(asUser("alice").doc("polls/v1_alice")
        .update({ entity2_id: "z9", pair_key: "x1_z9" }));
      await assertFails(asUser("alice").doc("polls/v1_alice").update({ entity_type: "album" }));
    });
  });

  test("an older poll may fill in a missing identity field", async () => {
    const { entity_type: _omit, ...legacy } = newPoll();
    await seed("polls/v1_alice", legacy);
    await assertSucceeds(asUser("alice").doc("polls/v1_alice").update({ entity_type: "artist" }));
  });
});
