// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:welcometothedisco/services/token_storage_service.dart';

class AuthService {
  final _auth        = FirebaseAuth.instance;
  final _googleSignIn = GoogleSignIn();

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

  // Google sign in
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken:     googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _handleError(e);
    }
  }

  // Sign out (Firebase only — Spotify tokens are intentionally kept so the
  // user doesn't have to re-authenticate with Spotify on every login).
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // Call this only when the user explicitly wants to disconnect Spotify.
  Future<void> disconnectSpotify() async {
    await TokenStorageService.clearTokens();
  }

  // Current user
  User? get currentUser => _auth.currentUser;

  // Error handler
  String _handleError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':    return 'No account found with this email';
      case 'wrong-password':    return 'Incorrect password';
      case 'email-already-in-use': return 'An account already exists with this email';
      case 'weak-password':     return 'Password is too weak';
      case 'invalid-email':     return 'Invalid email address';
      default:                  return 'Something went wrong. Please try again';
    }
  }
}