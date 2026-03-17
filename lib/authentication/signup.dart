import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';

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

const _kBlue = Color(0xFF1E3DE1);
const _kPink = Color(0xFFf85187);

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _authService = AuthService();

  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController      = TextEditingController();

  String? _selectedAvatar;
  bool _isLoading    = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // ── Validation ─────────────────────────────────────────────────────────────
  /// Returns an error string if profile fields are incomplete, null otherwise.
  String? _validateProfile() {
    if (_selectedAvatar == null) return 'Please select a profile picture.';
    if (_usernameController.text.trim().isEmpty) return 'Username is required.';
    if (_bioController.text.trim().isEmpty) return 'Bio is required.';
    return null;
  }

  // ── Email register ──────────────────────────────────────────────────────────
  Future<void> _handleRegister() async {
    final profileError = _validateProfile();
    if (profileError != null) {
      setState(() => _errorMessage = profileError);
      return;
    }
    if (_emailController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Email is required.');
      return;
    }
    if (_passwordController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Password is required.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final cred = await _authService.registerWithEmail(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      if (cred?.user == null) throw 'Account creation failed.';

      await FirebaseService.createUserProfile(
        uid:        cred!.user!.uid,
        email:      _emailController.text.trim(),
        username:   _usernameController.text.trim(),
        bio:        _bioController.text.trim(),
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

  // ── Google sign-in ──────────────────────────────────────────────────────────
  Future<void> _handleGoogleSignIn() async {
    final profileError = _validateProfile();
    if (profileError != null) {
      setState(() => _errorMessage = profileError);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final cred = await _authService.signInWithGoogle();
      if (cred?.user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final user = cred!.user!;
      await FirebaseService.createUserProfile(
        uid:        user.uid,
        email:      user.email ?? '',
        username:   _usernameController.text.trim(),
        bio:        _bioController.text.trim(),
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

  // ── Helpers ─────────────────────────────────────────────────────────────────
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
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLines: maxLines,
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

  // ── Avatar row ──────────────────────────────────────────────────────────────
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
                      // Circle avatar — 60×60 matching the lockeroom artist chip
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
                      // Selected check badge
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
                                    blurRadius: 4),
                              ],
                            ),
                            child: Icon(Icons.check_rounded,
                                color: _kBlue, size: 12),
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
                color: Colors.white.withOpacity(0.4),
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
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
            icon: Icon(Icons.arrow_back_ios_new,
                color: Colors.white.withOpacity(0.9)),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Welcome to the Disco',
            style: TextStyle(
              fontSize: 25.0,
              fontFamily: 'Honk-Regular-VariableFont_MORF,SHLN',
              color: Color.fromARGB(255, 159, 181, 63),
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
                      const SizedBox(height: 24),

                      // ── Avatar picker ─────────────────────────────────────
                      _buildAvatarPicker(),
                      const SizedBox(height: 24),

                      // ── Profile fields ────────────────────────────────────
                      _glassTextField(
                        controller: _usernameController,
                        label: 'Username',
                        inputFormatters: [_LowercaseFormatter()],
                      ),
                      const SizedBox(height: 16),
                      _glassTextField(
                        controller: _bioController,
                        label: 'Bio',
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),

                      // ── Email / password ──────────────────────────────────
                      _glassTextField(
                        controller: _emailController,
                        label: 'Email',
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      _glassTextField(
                        controller: _passwordController,
                        label: 'Password',
                        obscure: true,
                      ),

                      // ── Error message ─────────────────────────────────────
                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 12),
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

                      // ── Register button ───────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        child: _isLoading
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: Color.fromARGB(255, 159, 181, 63),
                                ),
                              )
                            : Material(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(50),
                                child: InkWell(
                                  onTap: _handleRegister,
                                  borderRadius: BorderRadius.circular(50),
                                  child: const Padding(
                                    padding:
                                        EdgeInsets.symmetric(vertical: 14),
                                    child: Center(
                                      child: Text(
                                        'Register',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
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

                      // ── OR divider ────────────────────────────────────────
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child:
                                Divider(color: Colors.white.withOpacity(0.3)),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'or',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.6)),
                            ),
                          ),
                          Expanded(
                            child:
                                Divider(color: Colors.white.withOpacity(0.3)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Google button ─────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _handleGoogleSignIn,
                          icon: Icon(
                            Icons.g_mobiledata_rounded,
                            color: Colors.white.withOpacity(0.9),
                            size: 24,
                          ),
                          label: Text(
                            'Continue with Google',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.95)),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.4)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          'Fill in avatar, username & bio before using Google',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 10,
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
