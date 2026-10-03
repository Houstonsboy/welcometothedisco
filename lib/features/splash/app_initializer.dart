import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs lightweight app-level initialisation and reports progress in [0, 1].
///
/// Firebase and NotificationService are already initialised in main() before
/// runApp(), so this only needs to load persisted prefs and verify auth state.
class AppInitializer {
  static const String _onboardingKey = 'hasCompletedOnboarding';

  final _progressCtrl = StreamController<double>.broadcast();

  Stream<double> get progress => _progressCtrl.stream;

  bool _hasCompletedOnboarding = false;
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;

  Future<void> initialize() async {
    try {
      _emit(0.0);

      // Step 1: Load persisted flags (~fast but real async I/O).
      final prefs = await SharedPreferences.getInstance();
      _hasCompletedOnboarding = prefs.getBool(_onboardingKey) ?? false;
      _emit(0.45);

      // Step 2: Confirm auth state (synchronous singleton read).
      FirebaseAuth.instance.currentUser;
      _emit(0.80);

      // Step 3: Any future pre-load work goes here.
      _emit(1.0);
    } catch (_) {
      _emit(1.0);
    } finally {
      if (!_progressCtrl.isClosed) await _progressCtrl.close();
    }
  }

  void _emit(double value) {
    if (!_progressCtrl.isClosed) _progressCtrl.add(value);
  }

  /// Persist the onboarding-complete flag. Call from OnboardingScreen.
  static Future<void> markOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
  }

  void dispose() {
    if (!_progressCtrl.isClosed) _progressCtrl.close();
  }
}
