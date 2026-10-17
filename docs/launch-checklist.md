# Launch checklist: what's left before Google Play / App Store / Spotify production

Consolidates [firebase.md](./firebase.md) and [spotify-api.md](./spotify-api.md)'s existing checklists
with the gaps found in notifications, legal/compliance, security, and testing. Grounded in what's
actually in this repo as of 2026-10-16 — re-verify anything store-policy-related against the live docs
before relying on it, policies move.

## 1. Push notifications (current focus)

**Working today:** FCM token save/refresh/clear wired to `users/{uid}.fcm_token`
(`lib/notification/notification_service.dart`), `sendFriendNotification` Cloud Function batches
`sendEachForMulticast` in chunks of 500, Android `POST_NOTIFICATIONS` permission is declared and
requested at runtime, APNs `aps.sound` / Android high-priority config is set in the function payload.

- [ ] **iOS push will not work at all yet.** No `GoogleService-Info.plist` anywhere in `ios/`, no
      `.entitlements` file (Push Notifications capability + `remote-notification` background mode never
      enabled in Xcode), and no APNs Auth Key uploaded under Firebase Console → Project Settings → Cloud
      Messaging. All three are required together — missing any one means FCM sends succeed server-side
      but nothing arrives on an iOS device.
- [ ] **Foreground notifications show nothing on Android.** `notification_service.dart`'s
      `FirebaseMessaging.onMessage` handler only `debugPrint`s (line ~47) — FCM auto-displays a
      notification when the app is backgrounded/terminated, but while the app is open in the foreground
      nothing is shown. `flutter_local_notifications` isn't in `pubspec.yaml` at all. Needs adding if you
      want a foreground banner.
- [ ] **Tapping a notification does nothing.** Both `onMessageOpenedApp` and the cold-start
      `getInitialMessage()` path are TODO stubs (notification_service.dart ~line 54 and ~63) — no
      navigation based on `message.data['type']`/`['id']`.
- [ ] **Security gap — any signed-in user can spam/phish any other user via push.**
      `firestore.rules`' `users/{userId}` rule allows `read` to any authenticated user (not just the
      owner or their friends), which exposes every user's `fcm_token` field. `sendFriendNotification`
      (functions/index.js) only checks `request.auth` exists — it never verifies the caller is actually
      friends with (or has any relation to) the token owners, or that the tokens passed in belong to
      friends at all. Today: any authenticated client can read arbitrary users' tokens off their profile
      docs, then call the function directly with those tokens plus any `title`/`body`/`data` it wants.
      Fix before shipping notifications broadly — either verify the friend relationship server-side
      before sending, or stop exposing raw tokens to arbitrary readers (move `fcm_token` to a
      Cloud-Function-only location, or gate with App Check / a server-side friends check).
- [ ] **Stale tokens never get cleaned up.** The function logs failed sends (`resp.error?.code`) but
      doesn't delete tokens that come back `messaging/registration-token-not-registered` — dead tokens
      accumulate in `users/{uid}.fcm_token` forever (not a correctness bug since it's one token per user,
      but worth wiring into the uninstall/token-rotation case eventually).
- [ ] No explicit Android notification channel ID is set in the FCM payload (`android.notification` in
      functions/index.js) — falls back to the default channel, fine for a single notification type but
      no per-category control (e.g. muting "new post" separately from "friend request").

## 2. Google Play Store

See [firebase.md §2](./firebase.md#2-go-live-checklist--concrete-issues-found-in-this-repo) for the full
list with context; summarized + a few additions here:

- [ ] Release signing: `android/app/build.gradle` still has `release { signingConfig =
      signingConfigs.debug }` — no real upload keystore / `key.properties` found in the repo.
- [ ] `applicationId` is still the Flutter template default, `com.example.welcometothedisco`
      (`android/app/build.gradle`) — rename before publishing, which also means regenerating
      `google-services.json`.
- [ ] Google Sign-In needs the **release** SHA-1/SHA-256 fingerprint registered in Firebase (debug
      fingerprint is presumably already there; production build will `DEVELOPER_ERROR` without it).
- [ ] **No in-app account deletion flow** (grepped `lib/` — nothing). Google Play policy requires apps
      that support account creation to also support in-app account + data deletion, plus a reachable
      web request path if the in-app path isn't available for some reason — this gates the **Data Safety
      form**, which gates the production listing.
- [ ] No privacy policy anywhere in the repo or linked in-app — required by the Data Safety section,
      the Google Sign-In OAuth consent screen, and Spotify's Developer Policy simultaneously.
- [ ] Google OAuth consent screen: confirm branding (app name/logo/support email/privacy link) is set
      and publishing status is "In production," not "Testing."
- [ ] **New personal Play Console accounts must run a closed test with ≥20 testers for 14 continuous
      days** before Google allows a production release — build this lead time into the plan now, it's
      not something you can skip by being ready early.
- [ ] Confirm the **Blaze plan** is active on the `jukebox-996de` Firebase project — Spark cannot deploy
      Cloud Functions at all, which would silently break `sendFriendNotification` in production.
- [ ] App Check isn't wired up (`firebase_core`/`cloud_firestore` in `pubspec.yaml` have no
      `firebase_app_check` alongside them) — not a store requirement, but it's the only thing standing
      between "valid Firebase auth token" and "actually our app," and it would also close part of the
      notification abuse gap above.
- [x] `compileSdkVersion`/`targetSdkVersion` already at 36 — satisfies Play's Android 16 target
      requirement, nothing to do unless a future Flutter upgrade regresses it.
- [ ] Adaptive icon isn't explicitly configured in `flutter_launcher_icons` (no
      `adaptive_icon_background`/`adaptive_icon_foreground` set in `pubspec.yaml`) — will still produce a
      usable icon, just not a true Android 8+ adaptive icon (no separate safe-zone layering).

## 3. iOS App Store (if shipping both platforms)

- [ ] No `GoogleService-Info.plist` — Firebase won't initialize correctly on iOS without it.
- [ ] No Push Notifications entitlement / `.entitlements` file (see §1).
- [ ] Bundle ID is still `com.example.welcometothedisco` in `ios/Runner.xcodeproj/project.pbxproj`.
- [ ] **Sign in with Apple is required** (App Store Guideline 4.8) because the app offers Google Sign-In
      as an account option — there's no Apple Sign-In code anywhere in `lib/authentication/` or
      `auth_service.dart` today. This is close to certain to be an App Review rejection reason without it.

## 4. Spotify

See [spotify-api.md](./spotify-api.md) for full detail; key open items:

- [ ] **Development Mode caps the app at 25 authorized users** (owner + 24 allowlisted by email in the
      Spotify Dashboard) — Extended Quota Mode's published bar (registered business, launched service,
      250K+ MAU) makes it very unlikely to qualify pre-launch. Plan the initial rollout as a small closed
      beta sized to this cap, not around requesting more quota.
- [ ] `spotify_api.dart` has no `429` / `Retry-After` handling — fine at current scale, worth adding
      before opening past the 25-user cap.
- [ ] `functions/index.js`'s `exchangeSpotifyCode` callable appears to be dead code — the app's actual
      auth flow (`spotify_auth.dart`) exchanges the PKCE code directly with Spotify, never calling this
      function. Confirm that and either delete it or document why it's still deployed (it's also
      unauthenticated and uninvolved-by-nobody-but-still-callable-by-anyone in its current form, which is
      an unnecessary surface if it's genuinely unused).
- [ ] **Premium-required messaging was removed, not fixed, by the recent free-tier work.** Commits
      `f4cb90c` ("free spotify users can banjo") and `100b1c8` ("free spotify users can tango") deleted
      `lib/services/playback_gate.dart` (133 lines) and the `PlaybackResult.premiumRequired` /
      `SpotifyUser.isPremium` distinction from `spotify_api.dart`, collapsing playback calls down to a
      plain `bool`. Spotify's API still rejects `/me/player/play` etc. with `403 PREMIUM_REQUIRED` for
      free-tier accounts (this app only does remote-control via Spotify Connect, not in-app streaming —
      see spotify-api.md §1) — the app just no longer distinguishes that from "no active device" or any
      other failure. Worth a product decision: either restore a clear "this needs Spotify Premium"
      message for free-tier users hitting playback, or confirm the intent was to silently no-op instead.
- [ ] Confirm attribution: Spotify's Developer Policy requires a link back to the Spotify entity
      wherever track/album/artist metadata or cover art is shown (`Ranking/`, `versus/` screens).

## 5. Legal / compliance

- [ ] No privacy policy document exists in the repo or is linked from any screen.
- [ ] No Terms of Service.
- [ ] No in-app account deletion (also a Play Store blocker, §2).

## 6. Testing

- [ ] `test/` has two files: the untouched Flutter-template `widget_test.dart` (smoke test only) and
      `pair_utils_test.dart`. No coverage of auth, versus/voting flows, notification logic, or Firestore
      rules (rules can be tested with the Firebase emulator + `@firebase/rules-unit-testing`, not set up
      here).
- [ ] No CI workflow found (`.github/workflows` doesn't exist) — `flutter analyze`/`flutter test` aren't
      gating anything on push today.
