import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

const _kBlue = AppTheme.gradientStart;
const _kPink = AppTheme.gradientEnd;

class DevPage extends StatefulWidget {
  const DevPage({super.key});

  @override
  State<DevPage> createState() => _DevPageState();
}

class _DevPageState extends State<DevPage> {
  // ── Admin gate ──────────────────────────────────────────────────────────────
  bool _adminChecking = true;
  bool _isAdmin = false;

  // ── Backfill state ──────────────────────────────────────────────────────────
  bool _backfillRunning = false;
  _BackfillResult? _backfillResult;
  String? _backfillError;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    final result = await FirebaseService.isCurrentUserAdmin();
    if (mounted) {
      setState(() {
        _isAdmin = result;
        _adminChecking = false;
      });
    }
  }

  Future<void> _runBackfill() async {
    if (_backfillRunning) return;
    setState(() {
      _backfillRunning = true;
      _backfillResult = null;
      _backfillError = null;
    });
    try {
      final result = await FirebaseService.backfillAdminField();
      if (mounted) {
        setState(() {
          _backfillResult = _BackfillResult(
            scanned: result['scanned'] ?? 0,
            updated: result['updated'] ?? 0,
          );
        });
      }
    } catch (e) {
      if (mounted) setState(() => _backfillError = e.toString());
    } finally {
      if (mounted) setState(() => _backfillRunning = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_adminChecking) return _buildChecking();
    if (!_isAdmin) return _buildNotAdmin();
    return _buildDevTools();
  }

  // ── Loading state ───────────────────────────────────────────────────────────
  Widget _buildChecking() {
    return Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white.withOpacity(0.45),
        ),
      ),
    );
  }

  // ── Not-admin gate ──────────────────────────────────────────────────────────
  Widget _buildNotAdmin() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
                border: Border.all(
                  color: Colors.white.withOpacity(0.12),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 32,
                color: Colors.white.withOpacity(0.28),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "you aren't admin.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "i'm sorry, i can't show you this page.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.35),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dev tools (admin only) ──────────────────────────────────────────────────
  Widget _buildDevTools() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionLabel('ONE-TIME MIGRATIONS'),
                const SizedBox(height: 10),
                _buildBackfillCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Page header ─────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DEV TOOLS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 3.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'internal utilities — handle with care',
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withOpacity(0.38),
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.2,
      ),
    );
  }

  // ── Backfill card ───────────────────────────────────────────────────────────
  Widget _buildBackfillCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _kBlue.withOpacity(0.40),
                _kPink.withOpacity(0.40),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.16),
              width: 0.8,
            ),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.10),
                    ),
                    child: Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 16,
                      color: Colors.white.withOpacity(0.75),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Backfill Admin Field',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Adds admin: false to every user doc that is missing the field',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.48),
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Progress / result area
              if (_backfillRunning) _buildProgress(),
              if (_backfillResult != null && !_backfillRunning)
                _buildResult(_backfillResult!),
              if (_backfillError != null && !_backfillRunning)
                _buildError(_backfillError!),

              const SizedBox(height: 14),

              // Run button
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: _backfillRunning ? null : _runBackfill,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: _backfillRunning
                          ? null
                          : const LinearGradient(
                              colors: [_kBlue, _kPink],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      color: _backfillRunning
                          ? Colors.white.withOpacity(0.07)
                          : null,
                      border: Border.all(
                        color: Colors.white.withOpacity(
                            _backfillRunning ? 0.10 : 0.0),
                        width: 0.8,
                      ),
                    ),
                    child: Center(
                      child: _backfillRunning
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white.withOpacity(0.55),
                              ),
                            )
                          : Text(
                              _backfillResult != null
                                  ? 'Run Again'
                                  : 'Run Backfill',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                    ),
                  ),
                ),
              ),

              if (_backfillResult == null && !_backfillRunning) ...[
                const SizedBox(height: 8),
                Text(
                  'Safe to re-run — skips docs that already have the admin field.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.28),
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withOpacity(0.07),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: Colors.white.withOpacity(0.55),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Scanning users collection…',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(_BackfillResult r) {
    final allGood = r.updated == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: allGood
            ? Colors.greenAccent.withOpacity(0.08)
            : Colors.white.withOpacity(0.07),
        border: Border.all(
          color: allGood
              ? Colors.greenAccent.withOpacity(0.25)
              : Colors.white.withOpacity(0.10),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allGood
                    ? Icons.check_circle_outline_rounded
                    : Icons.task_alt_rounded,
                size: 15,
                color: allGood
                    ? Colors.greenAccent.withOpacity(0.75)
                    : Colors.white.withOpacity(0.65),
              ),
              const SizedBox(width: 8),
              Text(
                allGood ? 'Already up-to-date' : 'Backfill complete',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _statRow('Docs scanned', '${r.scanned}'),
          const SizedBox(height: 4),
          _statRow('Docs updated', '${r.updated}', highlight: r.updated > 0),
          const SizedBox(height: 4),
          _statRow(
            'Docs skipped',
            '${r.scanned - r.updated} (field already present)',
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: highlight
                ? Colors.white.withOpacity(0.9)
                : Colors.white.withOpacity(0.6),
            fontSize: 11,
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildError(String error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.redAccent.withOpacity(0.10),
        border: Border.all(
          color: Colors.redAccent.withOpacity(0.25),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 14, color: Colors.redAccent.withOpacity(0.7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                color: Colors.redAccent.withOpacity(0.8),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackfillResult {
  final int scanned;
  final int updated;
  const _BackfillResult({required this.scanned, required this.updated});
}
