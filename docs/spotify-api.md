# Spotify API integration

How this app talks to Spotify, what quota tier it's in, and what's required before it can go out to
real users at scale. Grounded in the code in this repo plus Spotify's own developer documentation
(linked throughout — re-check these pages before acting, Spotify updates its policy periodically).

## 1. How it works in this codebase

### Auth: Authorization Code with PKCE
`lib/services/spotify_auth.dart` implements the [Authorization Code with PKCE
flow](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow), which is what
Spotify recommends for mobile/native apps because there's nowhere safe to store a client secret on
device:

1. Generates a random `code_verifier` and derives a `code_challenge` (SHA-256, base64url).
2. Opens `https://accounts.spotify.com/authorize` in the system browser (`url_launcher`,
   `LaunchMode.externalApplication`) with `client_id`, `redirect_uri`, `scope`, and the challenge.
3. Spotify redirects back to the app's custom redirect URI; `app_links` is the **only** deep-link
   listener in the app and delivers that URI back to `SpotifyAuth`.
4. The auth `code` is exchanged **directly with Spotify** (`POST
   https://accounts.spotify.com/api/token`) using the `code_verifier` — no client secret involved,
   per the PKCE spec.
5. Tokens are persisted via `lib/services/token_storage_service.dart` (Flutter Secure Storage) and
   refreshed there using the `refresh_token` grant when expired.

**⚠️ Discrepancy found while writing this doc:** `functions/index.js` exports an `exchangeSpotifyCode`
callable Cloud Function that does a *client-secret* based token exchange
(`grant_type=authorization_code` + `client_secret`), and `CLAUDE.md` currently describes this as the
path the app uses. It isn't — grepping `lib/` for `exchangeSpotifyCode` / `httpsCallable` shows the
Flutter app never calls it; `spotify_auth.dart` talks to Spotify directly with PKCE instead (step 4
above). The Cloud Function appears to be dead code from an earlier (non-PKCE) implementation. Worth
either deleting it or confirming there's a reason it's still deployed before relying on either
description.

The exact scopes requested live in `AppConfig.spotifyScopes` (`lib/config/app_config.dart` — gitignored
and not present in this checkout, see `CLAUDE.md`). Based on the endpoints actually called in
`lib/services/spotify_api.dart`, the app needs at least:

| Endpoint(s) called in `spotify_api.dart` | Scope required |
|---|---|
| `GET /me` (profile, email) | `user-read-email`, `user-read-private` |
| `GET /me/player/currently-playing` | `user-read-currently-playing` (or `user-read-playback-state`) |
| `GET /me/player/devices` | `user-read-playback-state` |
| `PUT /me/player/play`, `/pause`, `POST /next`, `/previous`, `/queue` | `user-modify-playback-state` |
| `GET /me/playlists` | `playlist-read-private` (+ `playlist-read-collaborative` for shared ones) |
| `POST /users/{user_id}/playlists`, `POST /playlists/{id}/tracks` | `playlist-modify-public` and/or `playlist-modify-private` |
| `GET /search`, `/albums`, `/artists`, `/tracks` | none (public catalog data) |

Full scope list/descriptions: <https://developer.spotify.com/documentation/web-api/concepts/scopes>.

### Playback is remote control, not streaming
The app never plays audio itself (no Web Playback SDK, no `streaming` scope). `/me/player/*` calls are
[Spotify Connect](https://developer.spotify.com/documentation/web-api/concepts/track-relinking)-style
remote control of whatever device already has the official Spotify app open and an active session. Two
consequences that are easy to forget:
- **The signed-in Spotify account must have Premium**, and the Spotify app must be open on some device,
  or `/me/player/play` etc. return errors (no active device / restricted for free tier).
- Because this is "control an existing client," not "stream audio in our own UI," the app sidesteps a
  chunk of Spotify's Design Guidelines that apply to apps that render playback UI themselves — but see
  §3 before assuming nothing applies.

### Services layering
- `spotify_auth.dart` — login/refresh/logout only.
- `token_storage_service.dart` — the single source of truth for the current access token; both
  `spotify_auth.dart` and `spotify_api.dart` route through it instead of holding tokens themselves.
- `spotify_api.dart` (~900 lines) — every authenticated Web API call.
- `spotify_service.dart` — a thin static wrapper (`SpotifyService.api`) so the `versus/` battle screens
  (lockeroom, backroom, playground) share one `SpotifyApi` instance rather than each creating their own.

## 2. Quota mode: where this app sits today

Every Spotify app starts in **Development Mode**
(<https://developer.spotify.com/documentation/web-api/concepts/quota-modes>):

- Caps out at **25 authenticated users** — the app owner plus up to 24 users added by email to an
  allowlist in the Spotify Dashboard. Anyone else gets an authorization error, not a vague failure —
  this is almost certainly the wall you hit first, not the rate limit.
- Development Mode apps require the **app owner's Spotify account to be Premium** or playback control
  silently stops working.
- Subject to Spotify's standard **rate limit**: a rolling 30-second window of request counts per app
  (not a fixed "N requests/second" number — Spotify doesn't publish the exact threshold).
  (<https://developer.spotify.com/documentation/web-api/concepts/rate-limits>)
  - Exceeding it returns `429` with a `Retry-After` header (seconds to wait). `spotify_api.dart` doesn't
    currently appear to special-case `429` — worth adding backoff/retry using `Retry-After` before this
    app has enough concurrent users to realistically hit the limit.
  - Spotify's own advice: batch where possible (e.g. `/albums?ids=...` instead of N calls to
    `/albums/{id}`), avoid polling/pre-fetching data the user hasn't asked to see yet, and watch the
    request-volume graph in the Dashboard for anomalies (a bug that loops a call looks identical to
    real traffic until you check that graph).

**Extended Quota Mode** removes the 25-user cap and raises the rate limit. As of Spotify's May 2025
policy update, applying for it is aimed at **organizations, not individual/hobby developers** — the
published bar is roughly:
- An established, legally registered business entity (not a personal project).
- An active, already-launched service.
- At least **250,000 monthly active users**.
- Availability in Spotify's key markets, and general compliance with the Developer Policy (§3).

Applications go through a company email + a dashboard request form, and Spotify says to expect **up to
six weeks** for review, including functional testing of the app against the Developer Policy. Given
that bar, this app is very unlikely to qualify for Extended Quota Mode pre-launch — plan the Spotify
side of the product around **Development Mode's 25-user cap** for anything before meaningful scale
(private beta, friends-and-family, waitlist), not around "we'll just request more quota."
(<https://developer.spotify.com/documentation/web-api/concepts/apps>)

## 3. Spotify's Developer Policy — what it rules out for this app

<https://developer.spotify.com/policy> — read the actual current text before launch, this is a
summary, not a substitute. Relevant points given what this app does (versus battles, playlists,
playback control, friends/social):

- **Attribution**: wherever track/album/artist metadata or cover art is shown, Spotify requires a link
  back to that content on Spotify. The `versus`/`Ranking` screens that show album art and track info
  should link out to the Spotify entity, not just display the data standalone.
- **No non-interactive/"radio" playback, no mixing/remixing Spotify audio with other audio, no
  synchronizing Spotify content with video** — not concerns for this app's feature set as built, but a
  constraint on future features (e.g. don't build an auto-DJ or video-sync feature on top of this
  integration without re-reading the policy).
- **Premium-only streaming**: this app doesn't stream audio itself (see §1), so this mostly falls on
  Spotify's own client, but don't build a feature that tries to let a free-tier user hear full tracks
  through this app's own UI.
- **No commercial monetization of the Spotify-powered parts** — no ads, IAPs, or paywalls gating
  Spotify-derived functionality specifically. If this app ever adds monetization, keep it clearly
  separate from "the Spotify features."
- **Data handling**: collect only what the feature needs, disclose it in a privacy policy (there isn't
  one in this repo yet — needed for app-store submission regardless of Spotify, see the Firebase doc),
  let a user fully disconnect their Spotify account, and delete their Spotify-derived data on
  disconnect/request. `token_storage_service.dart`'s `clearTokens()` on logout is a start, but "delete
  all user data" likely also means scrubbing cached Spotify metadata this app stores (album/track lists
  embedded in `versus` docs, cached images, etc.) — worth an explicit audit, not an assumption.
- **No training AI/ML models on Spotify content**, no voice-control of Spotify, no scraping beyond the
  API.

None of this blocks the current feature set, but attribution + the privacy/disconnect story are the two
most likely to need actual implementation work before a Developer Policy review would pass.

## 4. Checklist: what's needed to go live (beyond app-store rules, see the Firebase doc for those)

- [ ] Resolve the `exchangeSpotifyCode` dead-code discrepancy (§1) — delete it or document why it's
      kept.
- [ ] Add `429` handling (respect `Retry-After`) in `spotify_api.dart` — cheap insurance, not just a
      scale concern.
- [ ] Decide the Development Mode user cap is acceptable for however this launches (private
      beta/TestFlight/closed Play testing track all fit under 25 users; a public store listing does
      not, unless Extended Quota Mode is approved first).
- [ ] If genuinely planning to exceed 25 users publicly: either keep the launch invite-gated under that
      cap, or start the Extended Quota Mode application early — budget for the stated ~6 week review
      and the "registered business + 250k MAU" bar, which this app won't meet pre-launch.
- [ ] Add Spotify attribution (link-outs) wherever track/album/artist data is rendered, if not already
      present everywhere.
- [ ] Write the account-disconnect + data-deletion flow for Spotify data specifically (not just
      Firebase account deletion), and reflect it in a privacy policy.
- [ ] Register the production redirect URI(s) in the Spotify Dashboard app settings — distinct from
      whatever's used for local/dev builds (`app_links` + custom scheme needs to match exactly what's
      registered, including the iOS/Android platform-specific URI formatting rules Spotify documents).

## References

- Quota modes: <https://developer.spotify.com/documentation/web-api/concepts/quota-modes>
- Rate limits: <https://developer.spotify.com/documentation/web-api/concepts/rate-limits>
- App settings / requesting extended quota: <https://developer.spotify.com/documentation/web-api/concepts/apps>
- Scopes reference: <https://developer.spotify.com/documentation/web-api/concepts/scopes>
- Authorization Code with PKCE flow: <https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow>
- Developer Policy (full text — summarized above, don't rely on the summary alone): <https://developer.spotify.com/policy>
- Design guidelines (branding/logos if adding a "Login with Spotify" button, "Now Playing" UI, etc.): <https://developer.spotify.com/documentation/design>
