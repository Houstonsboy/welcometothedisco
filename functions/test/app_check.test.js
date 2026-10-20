// App Check guard on sendFriendNotification (see requireAppCheck in index.js).
// The rejection cases run offline; the "valid token passes" case needs the
// Firestore emulator because the function then goes on to read the sender.

"use strict";

const admin = require("firebase-admin");
if (admin.apps.length === 0) admin.initializeApp({ projectId: "demo-appcheck" });

const fft = require("firebase-functions-test")({ projectId: "demo-appcheck" });
const { sendFriendNotification } = require("../index");

const call = fft.wrap(sendFriendNotification);
const payload = { type: "follow", id: "alice", recipientUid: "bob" };
const signedIn = { uid: "alice", token: {} };

afterAll(() => fft.cleanup());
afterEach(() => { delete process.env.ENFORCE_APP_CHECK; });

describe("sendFriendNotification App Check guard", () => {
  test("enforced: a signed-in call without an App Check token is rejected", async () => {
    process.env.ENFORCE_APP_CHECK = "true";
    await expect(call({ data: payload, auth: signedIn }))
      .rejects.toMatchObject({ code: "failed-precondition", message: "Request must come from the app." });
  });

  test("enforced: signed-out calls still fail on auth first", async () => {
    // Keeps scripts/check_callables.js's unauthenticated probe meaningful.
    process.env.ENFORCE_APP_CHECK = "true";
    await expect(call({ data: payload })).rejects.toMatchObject({ code: "unauthenticated" });
  });

  const withEmulator = process.env.FIRESTORE_EMULATOR_HOST ? test : test.skip;

  withEmulator("enforced: a call with an App Check token gets past the guard", async () => {
    process.env.ENFORCE_APP_CHECK = "true";
    // No users/alice doc in the emulator, so the next check fails instead.
    await expect(call({ data: payload, auth: signedIn, app: { appId: "test-app" } }))
      .rejects.toMatchObject({ message: "Sender profile missing." });
  });

  withEmulator("not enforced: a call without a token gets past the guard", async () => {
    await expect(call({ data: payload, auth: signedIn }))
      .rejects.toMatchObject({ message: "Sender profile missing." });
  });
});
