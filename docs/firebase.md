# Firebase: what it does here, and what's needed to ship to the App Store / Play Store

Companion to [spotify-api.md](./spotify-api.md). First half is "what Firebase is doing in this app
today"; second half is a concrete go-live checklist for iOS/Android store submission, based on what's
actually in this repo right now (not a generic launch checklist).

## 1. What Firebase does in this app

Project: `jukebox-996de` (see `.firebaserc` / `firebase.json`).

| Firebase product | Used for | Where |
|---|---|---|
| **Firebase Auth** | Email/password + Google Sign-In; the `_AuthGate` in `lib/main.dart` gates the whole app on `FirebaseAuth.instance.currentUser` | `lib/services/auth_service.dart`, `lib/authentication/` |
| **Cloud Firestore** | All app data: `users`, `versus` (battles), `rankings`, `polls`, plus `users/{uid}/notifications` | `lib/services/firebase_service.dart`, `firestore.rules`, `firestore.indexes.json` |
| **Cloud Functions (v2)** | `exchangeSpotifyCode` (Spotify token exchange — appears unused, see spotify-api.md §1) and `sendFriendNotification` (server-side FCM fan-out, called via `httpsCallable`) | `functions/index.js` |
| **Firebase Cloud Messaging** | Push notifications for follows/invites; device tokens saved per-user on sign-in | `lib/notification/notification_service.dart` |

There's no Crashlytics, Analytics, Performance Monitoring, Remote Config, or App Check in `pubspec.yaml`
today — not required to ship, but see §3 for why App Check in particular is worth adding before a
public launch (Firestore rules currently only check `request.auth`, i.e. "is this a real Firebase user
token," not "is this request coming from our actual app").

### Firestore access model
`firestore.rules` is already reasonably tight: users can only write their own profile doc, `versus`
updates are restricted per-field based on role (author / invited collaborator / open-join claimant —
see the rule file's helper functions), `rankings` docs can only be created with a matching
`entity_id`/`entity_type`, and `polls` doc IDs are derived (`{versus_id}_{voter_id}`) and enforced
immutable after creation. This is the right foundation; the gap for production is less "are the rules
correct" and more "is anything other than the real app able to call these at all" (App Check, §3).

### Billing: Spark (free) won't deploy the Cloud Functions
Firebase's free **Spark** plan can *run* Cloud Functions locally in the emulator, but **cannot deploy
them to production at all** — deploying any Cloud Function (1st or 2nd gen) requires the **Blaze**
(pay-as-you-go) plan, because Functions need billing enabled to make any outbound network call (the
`exchangeSpotifyCode`/`sendFriendNotification` functions both do: Spotify's token endpoint, FCM). If
`npm run deploy` has ever succeeded against this project, Blaze is already active — if not, enabling it
is step zero, before anything else here.
(<https://firebase.google.com/docs/functions/version-comparison>,
<https://firebase.google.com/pricing>)

Blaze still has a generous free tier on top of pay-as-you-go — for an app this size you're very unlikely
to be billed meaningfully, but it does mean a payment method is on file. Current Spark/free-tier
ballpark for reference (confirm current numbers on the pricing page before relying on them):
Firestore ~50K reads/20K writes/20K deletes per day and 1 GiB storage; Cloud Functions 2M
invocations/month + 5 GB outbound/month; Firebase Auth 50K MAU. The `versus`/`rankings`/`polls` write
pattern (one doc per vote, batched ranking reconciliation) is cheap per-user, so the thing to actually
watch as users grow is Firestore read volume from live `snapshots()` listeners
(`getCurrentUserStream()`, notification streams, etc.), not writes.

## 2. Go-live checklist — concrete issues found in this repo

These are specific to what's currently checked in, not generic advice:

- [ ] **Release builds are signed with the debug key.** `android/app/build.gradle` has
      `release { signingConfig = signingConfigs.debug }`. Play Store will accept this for an internal
      test track, but it's wrong for anything meant to go out broadly — set up a real upload keystore
      (or enroll in Play App Signing, which Google now does by default for new apps) before a
      production release. This also matters for Google Sign-In (next point).
- [ ] **`applicationId` / iOS bundle ID are both still the Flutter template default**
      (`com.example.welcometothedisco` in `android/app/build.gradle` *and*
      `ios/Runner.xcodeproj/project.pbxproj`). Neither store will let you publish under `com.example.*`
      long-term, and changing it means regenerating `google-services.json` (Android) and adding a
      `GoogleService-Info.plist` (iOS, see next point) for the *new* ID — do this rename early, it
      touches both platforms and Firebase config together.
- [ ] **No `GoogleService-Info.plist` for iOS.** `android/app/google-services.json` exists and is
      committed, but there's no iOS equivalent anywhere in `ios/`. Without it, `Firebase.initializeApp()`
      won't have valid iOS config and auth/Firestore/FCM won't work on a release iOS build. Generate it
      from the Firebase console (or `flutterfire configure`) for the *final* bundle ID once that's
      decided.
- [ ] **Android Google Sign-In needs the release SHA-1/SHA-256 fingerprint registered in Firebase.**
      Google Sign-In matches the calling app's signing certificate against what's registered on the
      Firebase Android app config. The debug keystore's fingerprint is presumably already there (sign-in
      works in dev); the **release/Play-App-Signing certificate's fingerprint also has to be added**, or
      Google Sign-In will fail silently (or with a cryptic `DEVELOPER_ERROR`) for anyone using the
      production build. Easy to miss because dev testing won't catch it.
- [ ] **No push notification entitlement configured for iOS** — no `.entitlements` file found under
      `ios/`. `firebase_messaging` needs the "Push Notifications" capability + `remote-notification`
      background mode enabled in Xcode, **and** an APNs Auth Key (or certificate) uploaded under
      Project Settings → Cloud Messaging in the Firebase console, or FCM pushes to iOS devices will
      never arrive even though the code is otherwise correct.
- [ ] **No privacy policy in the repo.** Required by both stores regardless of Firebase, and
      specifically required by: Apple's App Privacy "nutrition label" questionnaire, Google Play's Data
      Safety section, Firebase Auth's Google Sign-In OAuth consent screen, and Spotify's Developer
      Policy (see spotify-api.md §3) — one document, several consumers. At minimum it needs to disclose:
      Firebase Auth identifiers (email, Google account), Firestore-stored profile/social data (friends,
      posts), FCM device tokens, and whatever Spotify account data is cached (see spotify-api.md's note
      on the Spotify disconnect/delete requirement).
- [ ] **Google OAuth consent screen branding.** `google_sign_in` goes through a Google Cloud OAuth
      consent screen tied to this Firebase project; if it's still in "Testing" publishing status or has
      default/no branding, users seeing a consent screen that says something other than this app's real
      name (or an "unverified app" warning) is a bad first impression at best and a store-review
      friction point at worst. Set the app name, logo, support email, and privacy-policy link, and move
      it to "In production" in Google Cloud Console → APIs & Services → OAuth consent screen.
- [ ] **Apple Sign-In requirement (App Store Guideline 4.8).** Because this app offers Google Sign-In as
      a way to create/authenticate the primary account, Apple requires an equivalent privacy-preserving
      option — in practice, **Sign in with Apple** — or App Review will reject the submission. There's
      no Apple sign-in code in `lib/authentication/` or `auth_service.dart` today; this is almost
      certainly needed before the iOS build can pass review, not just a nice-to-have.
      (<https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple>)
- [ ] **Target API level** is already fine: `compileSdkVersion 36` / `targetSdkVersion 36` in
      `android/app/build.gradle` already satisfies Google Play's upcoming Android 16 (API 36) target
      requirement (new apps/updates after Aug 31, 2026) — nothing to do here, just don't let it drift
      down on a Flutter upgrade.
- [ ] **Play Console account specifics for a first app**: Google now requires new personal developer
      accounts to run a **closed testing track with at least 20 testers for 14 continuous days** before
      being allowed to publish to production — factor that lead time into a launch plan, it's not
      optional paperwork, it gates the production listing from appearing at all.
- [ ] **App Check** isn't wired up. Not a store requirement, but worth doing alongside the above: it's
      the mechanism that would stop something other than this exact app build from calling Firestore
      directly with a stolen/valid-looking auth token — currently the rules only ask "is this a real
      signed-in user," not "is this request from our app."
      (<https://firebase.google.com/docs/app-check>)
- [ ] Confirm the **Blaze plan** is actually active (§1) — functions silently fail to deploy without it,
      which would currently break `sendFriendNotification` (follow/invite push notifications) in
      production.

## References

- Cloud Functions plan requirements: <https://firebase.google.com/docs/functions/version-comparison>
- Firebase pricing/quotas: <https://firebase.google.com/pricing>
- Firebase App Check: <https://firebase.google.com/docs/app-check>
- Google Play target API level policy: <https://support.google.com/googleplay/android-developer/answer/11926878>
- Google Play Data Safety: <https://support.google.com/googleplay/android-developer/answer/10787469>
- Google Play closed testing requirement for new accounts: <https://support.google.com/googleplay/android-developer/answer/14151465>
- Apple Sign in with Apple / Guideline 4.8: <https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple>
- Apple App Store Review Guidelines: <https://developer.apple.com/app-store/review/guidelines/>
- FlutterFire / Google Sign-In Android setup (SHA fingerprints): <https://firebase.google.com/docs/auth/android/google-signin>
