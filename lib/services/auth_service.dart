// lib/services/auth_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:welcometothedisco/notification/notification_service.dart';
import 'package:welcometothedisco/services/token_storage_service.dart';
import 'package:welcometothedisco/services/user_profile_cache_service.dart';

/// Result of Google sign-in from the **login** screen only (never creates a new
/// Firebase Auth user — unregistered Google accounts are reported for signup).
enum GoogleLoginScreenResultKind {
  /// Signed in; caller may navigate home.
  success,
  /// No Firebase user for this email — open signup (prefill email / name).
  needsRegistration,
  /// Email exists but linked to password, not Google.
  usePasswordInstead,
  /// User closed the Google picker.
  cancelled,
}

class GoogleLoginScreenResult {
  GoogleLoginScreenResult.success({required UserCredential this.credential})
      : kind = GoogleLoginScreenResultKind.success,
        signupEmail = null,
        signupDisplayName = null;

  const GoogleLoginScreenResult.needsRegistration({
    required String email,
    String? displayName,
  })  : kind = GoogleLoginScreenResultKind.needsRegistration,
        credential = null,
        signupEmail = email,
        signupDisplayName = displayName;

  const GoogleLoginScreenResult.usePasswordInstead()
      : kind = GoogleLoginScreenResultKind.usePasswordInstead,
        credential = null,
        signupEmail = null,
        signupDisplayName = null;

  const GoogleLoginScreenResult.cancelled()
      : kind = GoogleLoginScreenResultKind.cancelled,
        credential = null,
        signupEmail = null,
        signupDisplayName = null;

  final GoogleLoginScreenResultKind kind;
  final UserCredential? credential;
  final String? signupEmail;
  final String? signupDisplayName;
}

class AuthService {
  final _auth        = FirebaseAuth.instance;
  final _googleSignIn = GoogleSignIn();
  final _firestore   = FirebaseFirestore.instance;

  // Email login
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleError(e);
    }
  }

  // Email register
  Future<UserCredential?> registerWithEmail(String email, String password) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleError(e);
    }
  }

  /// Google sign-in for **signup** (and any flow that may create a new Auth user).
  /// When [requireExistingUserProfile] is true (default), requires `users/{uid}`.
  /// Signup passes `false` then creates the profile in Firestore.
  Future<UserCredential?> signInWithGoogle({
    bool requireExistingUserProfile = true,
  }) async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final result = await _auth.signInWithCredential(credential);

      if (requireExistingUserProfile) {
        final uid = result.user?.uid;
        if (uid != null) {
          final doc = await _firestore.collection('users').doc(uid).get();
          if (!doc.exists) {
            await _auth.signOut();
            await _googleSignIn.signOut();
            await UserProfileCacheService.clear();
            throw 'No account found for this Google email. Please sign up first.';
          }
        }
      }

      return result;
    } on FirebaseAuthException catch (e) {
      throw _handleError(e);
    }
  }

  /// **Login screen only:** Google sign-in for existing app users only.
  ///
  /// Uses [UserCredential.additionalUserInfo.isNewUser] (Firebase Auth 6+ no longer
  /// exposes [fetchSignInMethodsForEmail]). If the Google account is new to Firebase,
  /// the just-created Auth user is deleted so no account remains, then the UI should
  /// open signup. If the email already uses password auth, returns [usePasswordInstead].
  Future<GoogleLoginScreenResult> signInWithGoogleFromLoginScreen() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return const GoogleLoginScreenResult.cancelled();
      }

      final email = googleUser.email.trim();
      if (email.isEmpty) {
        await _googleSignIn.signOut();
        return const GoogleLoginScreenResult.cancelled();
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      late final UserCredential result;
      try {
        result = await _auth.signInWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        await _googleSignIn.signOut();
        if (e.code == 'account-exists-with-different-credential') {
          return const GoogleLoginScreenResult.usePasswordInstead();
        }
        throw _handleError(e);
      }

      final user = result.user;
      if (user == null) {
        await _googleSignIn.signOut();
        return const GoogleLoginScreenResult.cancelled();
      }

      final isNew = result.additionalUserInfo?.isNewUser ?? false;
      if (isNew) {
        try {
          await user.delete();
        } catch (_) {
          await _auth.signOut();
        }
        await _googleSignIn.signOut();
        await UserProfileCacheService.clear();
        return GoogleLoginScreenResult.needsRegistration(
          email: email,
          displayName: _trimmedDisplayName(googleUser.displayName),
        );
      }

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        await _auth.signOut();
        await _googleSignIn.signOut();
        await UserProfileCacheService.clear();
        return GoogleLoginScreenResult.needsRegistration(
          email: email,
          displayName: _trimmedDisplayName(googleUser.displayName),
        );
      }

      return GoogleLoginScreenResult.success(credential: result);
    } on FirebaseAuthException catch (e) {
      await _googleSignIn.signOut();
      throw _handleError(e);
    }
  }

  // Sign out (Firebase only — Spotify tokens are intentionally kept so the
  // user doesn't have to re-authenticate with Spotify on every login).
  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid ?? '';
    if (uid.isNotEmpty) await NotificationService.clearTokenForUser(uid);
    await _googleSignIn.signOut();
    await _auth.signOut();
    await UserProfileCacheService.clear();
  }

  // Call this only when the user explicitly wants to disconnect Spotify.
  Future<void> disconnectSpotify() async {
    await TokenStorageService.clearTokens();
  }

  // Current user
  User? get currentUser => _auth.currentUser;

  static String? _trimmedDisplayName(String? raw) {
    final s = raw?.trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  // Error handler
  String _handleError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':    return 'No account found with this email';
      case 'wrong-password':    return 'Incorrect password';
      case 'email-already-in-use': return 'An account already exists with this email';
      case 'account-exists-with-different-credential':
        return 'This email exists already. Sign in with your existing method first.';
      case 'weak-password':     return 'Password is too weak';
      case 'invalid-email':     return 'Invalid email address';
      default:                  return 'Something went wrong. Please try again';
    }
  }
}