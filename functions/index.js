const { setGlobalOptions, onCall } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const axios = require("axios");

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