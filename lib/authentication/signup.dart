import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

// Forces all typed characters to lowercase in real-time.
class _LowercaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toLowerCase());
  }
}

// All avatar filenames that live in assets/images/
const _kAvatars = [
  'avatar1.jpeg',
  'avatar2.jpeg',
  'avatar3.jpg',
  'avatar4.jpeg',
  'avatar5.jpeg',
  'avatar6.jpeg',
];

const _kBlue = AppTheme.gradientStart;
const _kPink = AppTheme.gradientEnd;

class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
    this.initialEmail,
    this.initialDisplayName,
  });

  /// Hint when arriving from login (Google account email not yet registered).
  final String? initialEmail;
  final String? initialDisplayName;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _authService = AuthService();

  final _usernameController = TextEditingController();

  String? _selectedAvatar;
  bool _isLoading = false;
  String _errorMessage = '';

  bool get _hasAvatar => _selectedAvatar != null;
  bool get _hasUsername => _usernameController.text.trim().isNotEmpty;
  /// Google sign-in is enabled only when both avatar and username are set.
  bool get _canCreateAccount => _hasAvatar && _hasUsername;

  @override
  void initState() {
    super.initState();
    final preName = widget.initialDisplayName?.trim();
    if (preName != null && preName.isNotEmpty) {
      final space = preName.indexOf(' ');
      _usernameController.text = space > 0
          ? preName.substring(0, space).toLowerCase()
          : preName.toLowerCase();
    }
    _usernameController.addListener(_onProfileFieldChanged);
  }

  void _onProfileFieldChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _usernameController.removeListener(_onProfileFieldChanged);
    _usernameController.dispose();
    super.dispose();
  }

  /// Returns an error string if avatar or username is missing.
  String? _validateForGoogleSignUp() {
    if (_selectedAvatar == null) return 'Please select a profile picture.';
    if (_usernameController.text.trim().isEmpty) {
      return 'Please enter a username.';
    }
    return null;
  }

  Future<void> _handleGoogleSignUp() async {
    final profileError = _validateForGoogleSignUp();
    if (profileError != null) {
      setState(() => _errorMessage = profileError);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final cred = await _authService.signInWithGoogle(
        requireExistingUserProfile: false,
      );
      if (cred?.user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final user = cred!.user!;
      await FirebaseService.createUserProfile(
        uid: user.uid,
        email: user.email ?? '',
        username: _usernameController.text.trim(),
        avatarPath: _selectedAvatar!,
      );

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      setState(() => _errorMessage = e is String ? e : e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _kBlue.withOpacity(0.45),
                _kPink.withOpacity(0.45),
              ],
            ),
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

  Widget _glassTextField({
    required TextEditingController controller,
    required String label,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.text,
      inputFormatters: inputFormatters,
      style: TextStyle(color: Colors.white.withOpacity(0.95)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withOpacity(0.8)),
        ),
      ),
    );
  }

  Widget _buildAvatarPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CHOOSE AVATAR',
          style: TextStyle(
            color: Colors.white.withOpacity(0.55),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _kAvatars.map((filename) {
              final isSelected = _selectedAvatar == filename;
              return GestureDetector(
                onTap: () => setState(() => _selectedAvatar = filename),
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipOval(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.2),
                              width: isSelected ? 2.5 : 1,
                            ),
                          ),
                          child: Image.asset(
                            'assets/images/$filename',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              color: _kBlue,
                              size: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        if (_selectedAvatar == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Select a picture above',
              style: TextStyle(
                color: _errorMessage.isNotEmpty
                    ? Colors.red.shade200
                    : Colors.white.withOpacity(0.4),
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  Widget _requirementRow({
    required String label,
    required bool done,
  }) {
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          size: 14,
          color: done
              ? AppTheme.titleAccent
              : Colors.white.withOpacity(0.35),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: done
                ? Colors.white.withOpacity(0.85)
                : Colors.white.withOpacity(0.45),
            fontSize: 11,
            fontWeight: done ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hintEmail = widget.initialEmail?.trim();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBlue, _kPink],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new,
              color: Colors.white.withOpacity(0.9),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Welcome to the Disco',
            style: TextStyle(
              fontSize: 25.0,
              fontFamily: AppTheme.fontHeader,
              color: AppTheme.titleAccent,
            ),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: _glassCard(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          'Create account',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.95),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Pick an avatar and username, then continue with Google.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ),
                      if (hintEmail != null && hintEmail.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            'Google: $hintEmail',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.75),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _buildAvatarPicker(),
                      const SizedBox(height: 20),
                      _glassTextField(
                        controller: _usernameController,
                        label: 'Username',
                        inputFormatters: [_LowercaseFormatter()],
                      ),
                      const SizedBox(height: 12),
                      _requirementRow(
                        label: 'Avatar selected',
                        done: _hasAvatar,
                      ),
                      const SizedBox(height: 4),
                      _requirementRow(
                        label: 'Username entered',
                        done: _hasUsername,
                      ),
                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          _errorMessage,
                          style: TextStyle(
                            color: Colors.red.shade200,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: _isLoading
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: AppTheme.titleAccent,
                                ),
                              )
                            : OutlinedButton.icon(
                                onPressed: (_canCreateAccount)
                                    ? _handleGoogleSignUp
                                    : null,
                                icon: Icon(
                                  Icons.g_mobiledata_rounded,
                                  color: Colors.white.withOpacity(0.9),
                                  size: 26,
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
                                    color: Colors.white.withOpacity(
                                      _canCreateAccount ? 0.45 : 0.2,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          _canCreateAccount
                              ? 'Your Google account will be linked to this profile.'
                              : 'Select an avatar and username to enable Google sign-up.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _canCreateAccount
                                ? Colors.white.withOpacity(0.35)
                                : Colors.red.shade200.withOpacity(0.85),
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Already have an account? Sign in',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              decoration: TextDecoration.underline,
                            ),
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
