/**
 * Manual push test — sends one FCM message straight to a stored device
 * token, bypassing the sendFriendNotification callable and its auth check.
 * Use this to test foreground banners / tap-to-navigate on a single device
 * (no second phone or Firebase Console campaign needed).
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     node functions/scripts/send_test_push.js <uid> [type] [id]
 *
 *   uid  — the Firebase Auth uid whose users/{uid}.fcm_token to send to
 *          (sign into the app on your device first so a token is stored)
 *   type — follow | invite | post | versus (default: follow)
 *   id   — the id to put in data.id, e.g. a follower uid or versus id
 *          (default: "test-id" — fine for checking the banner shows up,
 *          but tap-to-navigate needs a real id that exists in Firestore)
 */
"use strict";

const admin = require("firebase-admin");

const PROJECT_ID = "jukebox-996de";

const [, , uid, type = "follow", id = "test-id"] = process.argv;

if (!uid) {
  console.error("Usage: node send_test_push.js <uid> [type] [id]");
  console.error("  type: follow | invite | post | versus (default: follow)");
  process.exit(1);
}

try {
  if (admin.apps.length === 0) {
    if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      console.error(
        "ERROR: GOOGLE_APPLICATION_CREDENTIALS env var not set.\n" +
        "Usage: GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node send_test_push.js <uid> [type] [id]"
      );
      process.exit(1);
    }
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: PROJECT_ID,
    });
  }
} catch (err) {
  console.error("[init] admin.initializeApp FAILED:", err.message);
  process.exit(1);
}

const TITLES = {
  follow: "Someone followed you",
  invite: "You were invited to a versus",
  post: "A friend posted",
  versus: "A friend started a versus",
};

async function main() {
  const doc = await admin.firestore().collection("users").doc(uid).get();
  const token = doc.data()?.fcm_token;
  if (!token) {
    console.error(
      `No fcm_token stored on users/${uid} — open the app on your device ` +
      "(signed in as this user) first so NotificationService saves one."
    );
    process.exit(1);
  }

  const data = { type, id };
  if (type === "versus") data.versusType = "artist";

  const result = await admin.messaging().send({
    token,
    notification: {
      title: TITLES[type] || "Test notification",
      body: "Tap to test navigation",
    },
    data,
    android: { priority: "high", notification: { sound: "default" } },
    apns: { payload: { aps: { sound: "default" } } },
  });

  console.log("Sent:", result);
}

main().catch((err) => {
  console.error("Send failed:", err);
  process.exit(1);
});
