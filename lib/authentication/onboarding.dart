import 'package:flutter/material.dart';

import '../features/splash/app_initializer.dart';
import '../theme/app_theme.dart';

/// Placeholder onboarding screen — replace with real onboarding flows.
///
/// On completion, call [AppInitializer.markOnboardingComplete] then navigate
/// to '/' (the AuthGate), which will route to login or the app shell.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.splashBackground,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Welcome to\nthe Disco',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.fontHeader,
                    fontSize: 36,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 48),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.splashLogoYellow,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 52),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  onPressed: () => _complete(context),
                  child: const Text('Get Started'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _complete(BuildContext context) async {
    await AppInitializer.markOnboardingComplete();
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
  }
}
