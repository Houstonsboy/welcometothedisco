const { setGlobalOptions, onCall } = require("firebase-functions/v2/https");
const { HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const axios = require("axios");
const admin = require("firebase-admin");

if (admin.apps.length === 0) admin.initializeApp();

setGlobalOptions({ maxInstances: 10 });

exports.exchangeSpotifyCode = onCall(async (request) => {
  const code = request.data.code;

  if (!code) {
    throw new Error("Auth code is required");
  }

  // reads from functions/.env
  const clientId     = process.env.SPOTIFY_CLIENT_ID;
  const clientSecret = process.env.SPOTIFY_CLIENT_SECRET;
  const redirectUri  = process.env.SPOTIFY_REDIRECT_URI;

  logger.info("Exchanging Spotify auth code for tokens");

  const response = await axios.post(
    "https://accounts.spotify.com/api/token",
    new URLSearchParams({
      grant_type:    "authorization_code",
      code:           code,
      redirect_uri:   redirectUri,
      client_id:      clientId,
      client_secret:  clientSecret,
    }),
    { headers: { "Content-Type": "application/x-www-form-urlencoded" } }
  );

  return {
    accessToken:  response.data.access_token,
    refreshToken: response.data.refresh_token,
    expiresIn:    response.data.expires_in,
  };
});

// Sends an FCM multicast push to a list of device tokens.
// Called from NotificationService.notifyFriendsNew*() in the Flutter app.
// Requires the caller to be authenticated.
//
// request.data shape:
//   tokens  : string[]          — FCM registration tokens (max 500)
//   title   : string            — notification title
//   body    : string            — notification body
//   data    : Record<string,string>  — optional key/value pairs passed to the app
exports.sendFriendNotification = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const { tokens, title, body, data } = request.data;

  if (!Array.isArray(tokens) || tokens.length === 0) {
    throw new HttpsError("invalid-argument", "tokens must be a non-empty array.");
  }
  if (typeof title !== "string" || !title.trim()) {
    throw new HttpsError("invalid-argument", "title is required.");
  }
  if (typeof body !== "string" || !body.trim()) {
    throw new HttpsError("invalid-argument", "body is required.");
  }

  // FCM sendEachForMulticast accepts up to 500 tokens per call.
  // Chunk into batches of 500 if needed.
  const BATCH = 500;
  let successCount = 0;
  let failureCount = 0;

  for (let i = 0; i < tokens.length; i += BATCH) {
    const chunk = tokens.slice(i, i + BATCH);
    const message = {
      tokens: chunk,
      notification: { title, body },
      data: data && typeof data === "object" ? data : {},
      android: {
        priority: "high",
        notification: { sound: "default" },
      },
      apns: {
        payload: { aps: { sound: "default" } },
      },
    };

    const result = await admin.messaging().sendEachForMulticast(message);
    successCount += result.successCount;
    failureCount += result.failureCount;

    // Log any tokens that failed so stale ones can be cleaned up later.
    result.responses.forEach((resp, idx) => {
      if (!resp.success) {
        logger.warn("FCM send failed", {
          token: chunk[idx].slice(0, 12) + "…",
          error: resp.error?.code,
        });
      }
    });
  }

  logger.info("sendFriendNotification done", { successCount, failureCount });
  return { successCount, failureCount };
});