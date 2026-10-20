import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../../theme/app_theme.dart';
import 'app_initializer.dart';
import 'widgets/quadrant_logo.dart';
import 'widgets/splash_progress_bar.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// Set to false to disable the continuous logo rotation.
  static const bool _enableRotation = true;

  late final AnimationController _enterCtrl;
  late final AnimationController _rotateCtrl;
  late final AnimationController _exitCtrl;

  late final Animation<double> _scaleIn;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scaleOut;
  late final Animation<double> _fadeOut;

  final _initializer = AppInitializer();
  StreamSubscription<double>? _progressSub;

  double _targetProgress = 0.0;
  bool _initDone = false;
  bool _minTimeDone = false;
  bool _isExiting = false;
  bool _disableAnimations = false;
  Timer? _maxTimer;

  @override
  void initState() {
    super.initState();

    // Dismiss the native splash; Flutter splash is now visible.
    FlutterNativeSplash.remove();

    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleIn = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic),
    );
    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic),
    );
    _scaleOut = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInCubic),
    );
    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInCubic),
    );

    _enterCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          _enableRotation &&
          !_disableAnimations &&
          mounted) {
        _rotateCtrl.repeat();
      }
    });

    _enterCtrl.forward();

    // Minimum display time — gives the user enough time to see the splash.
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        _minTimeDone = true;
        _checkDone();
      }
    });

    // Safety valve: always proceed after 8 s.
    _maxTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_isExiting) _triggerExit();
    });

    _runInit();
  }

  void _runInit() {
    _progressSub = _initializer.progress.listen(
      (v) {
        if (mounted) setState(() => _targetProgress = v);
      },
      onDone: () {
        if (mounted) {
          _initDone = true;
          _checkDone();
        }
      },
      onError: (_) {
        if (mounted) {
          _initDone = true;
          _checkDone();
        }
      },
    );
    _initializer.initialize();
  }

  void _checkDone() {
    if (_initDone && _minTimeDone && !_isExiting) _triggerExit();
  }

  Future<void> _triggerExit() async {
    if (_isExiting) return;
    _isExiting = true;
    _maxTimer?.cancel();

    setState(() => _targetProgress = 1.0);

    if (!_disableAnimations) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      await _exitCtrl.forward();
    }

    if (mounted) _navigate();
  }

  void _navigate() {
    final route =
        _initializer.hasCompletedOnboarding ? '/' : '/onboarding';
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _enterCtrl.dispose();
    _rotateCtrl.dispose();
    _exitCtrl.dispose();
    _initializer.dispose();
    _maxTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disableAnimations = MediaQuery.of(context).disableAnimations;

    final size = MediaQuery.of(context).size;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final logoSize = (size.width * 0.34).clamp(110.0, 160.0);

    return Semantics(
      label: 'Loading',
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: AppTheme.splashBackground,
          body: AnimatedBuilder(
            animation:
                Listenable.merge([_enterCtrl, _rotateCtrl, _exitCtrl]),
            builder: (context, child) {
              final double scale;
              final double opacity;
              final double rotation;

              if (_disableAnimations) {
                scale = 1.0;
                opacity = 1.0;
                rotation = 0.0;
              } else if (_isExiting) {
                scale = _scaleOut.value;
                opacity = _fadeOut.value;
                rotation = _enableRotation
                    ? _rotateCtrl.value * 2 * math.pi
                    : 0.0;
              } else {
                scale = _scaleIn.value;
                opacity = _fadeIn.value;
                rotation = _enableRotation
                    ? _rotateCtrl.value * 2 * math.pi
                    : 0.0;
              }

              return Stack(
                children: [
                  // Logo — slightly above true centre (≈ 48 % from top).
                  Align(
                    alignment: const Alignment(0, -0.08),
                    child: Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: opacity,
                        child: Transform.rotate(
                          angle: rotation,
                          child: QuadrantLogo(size: logoSize),
                        ),
                      ),
                    ),
                  ),
                  // Progress bar — 56 px above safe-area bottom.
                  Positioned(
                    bottom: safeBottom + 56.0,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: 0.0,
                          end: _targetProgress,
                        ),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        builder: (_, value, __) =>
                            SplashProgressBar(progress: value),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
