import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'signup.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();

  bool _isLoading = false;
  String _errorMessage = '';

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await _authService.signInWithGoogleFromLoginScreen();

      if (!mounted) return;

      switch (result.kind) {
        case GoogleLoginScreenResultKind.success:
          if (FirebaseAuth.instance.currentUser != null) {
            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          } else {
            setState(() => _isLoading = false);
          }
          return;
        case GoogleLoginScreenResultKind.needsRegistration:
          setState(() => _isLoading = false);
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SignupScreen(
                initialEmail: result.signupEmail,
                initialDisplayName: result.signupDisplayName,
              ),
            ),
          );
          return;
        case GoogleLoginScreenResultKind.usePasswordInstead:
          setState(() {
            _isLoading = false;
            _errorMessage =
                'This email is tied to an older sign-in method. Use the Google account you registered with, or try a different Google account.';
          });
          return;
        case GoogleLoginScreenResultKind.cancelled:
          setState(() => _isLoading = false);
          return;
      }
    } catch (e) {
      if (mounted && FirebaseAuth.instance.currentUser == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = e is String ? e : e.toString();
        });
      }
    }
  }

  Widget _glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: AppTheme.glassPanelGradient(),
            border: Border.all(
              color: Colors.white.withOpacity(0.18),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text(
            "Welcome to the Disco",
                style: TextStyle(
                  fontSize: 15.0,
                  fontFamily: AppTheme.fontHeader,
                  color: Color(0xFF17B5EE),
            ),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _glassCard(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Sign in',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.95),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        ' New users will set a username and avatar next.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Colors.white.withOpacity(0.65),
                        ),
                      ),
                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage,
                          style: TextStyle(
                            color: Colors.red.shade200,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: _isLoading
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: AppTheme.titleAccent,
                                ),
                              )
                            : OutlinedButton.icon(
                                onPressed: _handleGoogleSignIn,
                                icon: Icon(
                                  Icons.g_mobiledata_rounded,
                                  color: Colors.white.withOpacity(0.9),
                                  size: 28,
                                ),
                                label: Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.95),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: Colors.white.withOpacity(0.45),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.push<void>(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => const SignupScreen(),
                                  ),
                                );
                              },
                        child: Text(
                          'New here? Create an account',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
