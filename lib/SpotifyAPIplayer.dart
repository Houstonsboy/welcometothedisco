import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/BottomNavBar.dart';
import 'package:welcometothedisco/config/app_config.dart';
import 'package:welcometothedisco/services/spotify_auth.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/services/token_storage_service.dart';

class SpotifyAPIplayer extends StatefulWidget {
  const SpotifyAPIplayer({super.key, this.embedded = false});

  /// When true, only the body content is shown (no scaffold, app bar, or bottom nav).
  /// Used when embedded in the app shell in main.dart.
  final bool embedded;

  @override
  State<SpotifyAPIplayer> createState() => _SpotifyAPIplayerState();
}

enum _StepStatus { idle, loading, success, error }

class _AuthStep {
  final String label;
  _StepStatus status;
  String detail;
  _AuthStep(this.label, {this.status = _StepStatus.idle, this.detail = ''});
}

class _SpotifyAPIplayerState extends State<SpotifyAPIplayer> {
  final SpotifyAuth _auth = SpotifyAuth();
  late final SpotifyApi _api = SpotifyApi();

  bool _connected = false;
  bool _connecting = false;
  String _statusMessage = '';

  /// Final authentication result from last login attempt. Used to show status in UI.
  SpotifyAuthResult? _lastAuthResult;

  NowPlaying? _nowPlaying;
  StreamSubscription<NowPlaying?>? _nowPlayingSub;

  List<SpotifyTrack> _searchResults = [];
  bool _searching = false;

  final TextEditingController _uriController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  final List<_AuthStep> _steps = [
    _AuthStep('1. Opening Spotify login'),
    _AuthStep('2. Waiting for user authorization'),
    _AuthStep('3. Exchanging code for token (PKCE)'),
    _AuthStep('4. Verifying active device'),
  ];

  void _resetSteps() {
    for (final s in _steps) {
      s.status = _StepStatus.idle;
      s.detail = '';
    }
  }

  void _setStep(int i, _StepStatus status, {String detail = ''}) {
    if (!mounted) return;
    setState(() {
      _steps[i].status = status;
      _steps[i].detail = detail;
    });
  }

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  @override
  void dispose() {
    _nowPlayingSub?.cancel();
    _uriController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _tryAutoLogin() async {
    final token = await TokenStorageService.getAccessToken();
    if (token != null && mounted) {
      setState(() => _connected = true);
      _startPolling();
    }
  }

  void _startPolling() {
    _nowPlayingSub?.cancel();
    _nowPlayingSub = _api.pollNowPlaying().listen((np) {
      if (mounted) setState(() => _nowPlaying = np);
    });
  }

  // ── Connect flow ──────────────────────────────────────────────────────────

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _statusMessage = '';
      _lastAuthResult = null;
      _resetSteps();
    });

    _setStep(0, _StepStatus.loading, detail: 'clientId: ${AppConfig.spotifyClientId.length >= 8 ? AppConfig.spotifyClientId.substring(0, 8) : AppConfig.spotifyClientId}…');
    _setStep(1, _StepStatus.loading);

    SpotifyAuthResult result;
    try {
      result = await _auth.login();
    } catch (e) {
      result = SpotifyAuthResult.error(message: e.toString());
    }

    _lastAuthResult = result;

    if (result.isError) {
      _setStep(0, _StepStatus.error);
      _setStep(1, _StepStatus.error, detail: result.message ?? '');
      _setStep(2, _StepStatus.error, detail: result.statusLabel);
      setState(() {
        _connecting = false;
        _statusMessage = result.statusLabel;
      });
      return;
    }

    if (result.isCancelled) {
      _setStep(0, _StepStatus.error, detail: 'Cancelled or no code returned');
      _setStep(1, _StepStatus.error);
      _setStep(2, _StepStatus.error);
      setState(() {
        _connecting = false;
        _statusMessage = result.statusLabel;
      });
      return;
    }

    // success
    final token = result.accessToken;
    _setStep(0, _StepStatus.success, detail: 'Browser opened');
    _setStep(1, _StepStatus.success, detail: 'User authorized');
    _setStep(2, _StepStatus.success, detail: 'Token length: ${token?.length ?? 0}');

    _setStep(3, _StepStatus.loading, detail: 'Checking for active Spotify device…');
    final deviceId = await _api.getActiveDeviceId();
    _setStep(
      3,
      deviceId != null ? _StepStatus.success : _StepStatus.error,
      detail: deviceId != null
          ? 'Device found: ${deviceId.substring(0, 8)}…'
          : 'No active device — open Spotify and play something first',
    );

    setState(() {
      _connected = true;
      _connecting = false;
      _statusMessage = result.statusLabel;
      if (deviceId != null) {
        _statusMessage = '${result.statusLabel} — Connected to Spotify';
      } else {
        _statusMessage = '${result.statusLabel} — Open Spotify app to control playback';
      }
    });

    _startPolling();
  }

  // ── Playback actions ──────────────────────────────────────────────────────

  Future<void> _doPlay() async {
    if (!await _ensureDevice()) return;
    await _api.resume();
  }

  Future<void> _doPause() async {
    await _api.pause();
  }

  Future<void> _doSkipNext() async {
    await _api.skipNext();
  }

  Future<void> _doSkipPrev() async {
    await _api.skipPrevious();
  }

  Future<void> _queueTrack() async {
    final uri = _uriController.text.trim();
    if (uri.isEmpty) return;
    if (!await _ensureDevice()) return;

    setState(() => _statusMessage = 'Queuing…');
    final ok = await _api.queueTrack(uri);
    setState(() => _statusMessage = ok ? 'Track queued!' : 'Queue failed — check URI');
  }

  Future<void> _playTrack(String uri) async {
    if (!await _ensureDevice()) return;
    setState(() => _statusMessage = 'Playing…');
    final ok = await _api.play(uri);
    setState(() => _statusMessage = ok ? 'Playing!' : 'Play failed');
  }

  Future<bool> _ensureDevice() async {
    final id = await _api.getActiveDeviceId();
    if (id == null) {
      setState(() => _statusMessage = 'No active device — open Spotify and play something first');
      return false;
    }
    return true;
  }

  // ── Search ────────────────────────────────────────────────────────────────

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _searching = true);
    final results = await _api.searchTracks(query, limit: 10);
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  Future<void> _disconnect() async {
    _nowPlayingSub?.cancel();
    await _auth.logout();
    setState(() {
      _connected = false;
      _nowPlaying = null;
      _searchResults = [];
      _statusMessage = '';
      _lastAuthResult = null;
      _resetSteps();
    });
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _onTabTapped(int index) {
    if (index == 1) return;
    if (index == 0) Navigator.pushReplacementNamed(context, '/');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final content = _connected ? _playerView() : _connectView();
    if (widget.embedded) {
      return content;
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3DE1), Color(0xFFf85187)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'SPOTIFY PLAYGROUND',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          actions: _connected
              ? [
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: Colors.white70),
                    onPressed: _disconnect,
                    tooltip: 'Disconnect',
                  ),
                ]
              : null,
        ),
        body: content,
        bottomNavigationBar: BottomNavBar(
          selectedIndex: 1,
          onTap: _onTabTapped,
        ),
      ),
    );
  }

  // ── Connect view ──────────────────────────────────────────────────────────

  Widget _connectView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music_rounded,
                size: 72, color: Colors.white.withOpacity(0.4)),
            const SizedBox(height: 24),
            Text(
              'Connect to Spotify to control playback\nand queue tracks',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            _glassButton(
              label: _connecting ? 'Connecting…' : 'Connect to Spotify',
              icon: Icons.login_rounded,
              onTap: _connecting ? null : _connect,
              highlight: true,
            ),
            if (_lastAuthResult != null) ...[
              const SizedBox(height: 20),
              _authenticationStatusCard(_lastAuthResult!),
            ],
            if (_connecting || _steps.any((s) => s.status != _StepStatus.idle)) ...[
              const SizedBox(height: 24),
              _authStepsList(),
            ],
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _connected
                      ? const Color(0xFF1DB954)
                      : Colors.redAccent.withOpacity(0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _authStepsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _steps.map((step) {
        Color color;
        IconData icon;
        switch (step.status) {
          case _StepStatus.loading:
            color = const Color(0xFFFFD700);
            icon = Icons.hourglass_top_rounded;
          case _StepStatus.success:
            color = const Color(0xFF1DB954);
            icon = Icons.check_circle_rounded;
          case _StepStatus.error:
            color = Colors.redAccent;
            icon = Icons.cancel_rounded;
          case _StepStatus.idle:
            color = Colors.white.withOpacity(0.3);
            icon = Icons.radio_button_unchecked_rounded;
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.label,
                        style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    if (step.detail.isNotEmpty)
                      Text(step.detail,
                          style: TextStyle(
                              color: color.withOpacity(0.75),
                              fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Shows the final authentication/authorization result (success, cancelled, or error).
  Widget _authenticationStatusCard(SpotifyAuthResult result) {
    Color color;
    IconData icon;
    if (result.isSuccess) {
      color = const Color(0xFF1DB954);
      icon = Icons.check_circle_rounded;
    } else if (result.isCancelled) {
      color = Colors.amber;
      icon = Icons.cancel_rounded;
    } else {
      color = Colors.redAccent;
      icon = Icons.error_rounded;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.5), width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Authentication status',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.statusLabel,
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// When connected, shows a short banner that auth was successful.
  Widget _authStatusBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: const Color(0xFF1DB954), size: 18),
          const SizedBox(width: 8),
          Text(
            'Authentication: Successful',
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Player view ───────────────────────────────────────────────────────────

  Widget _playerView() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _authStatusBanner(),
          _nowPlayingCard(),
          const SizedBox(height: 20),
          _controlsCard(),
          const SizedBox(height: 20),
          _searchCard(),
          const SizedBox(height: 20),
          _queueCard(),
          if (_statusMessage.isNotEmpty) ...[
            const SizedBox(height: 16),
            Center(
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Now playing card ──────────────────────────────────────────────────────

  Widget _nowPlayingCard() {
    final np = _nowPlaying;
    return _glassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: np == null
            ? Text(
                'Nothing playing',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15),
              )
            : Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: np.albumArtUrl != null
                        ? Image.network(np.albumArtUrl!, width: 56, height: 56, fit: BoxFit.cover)
                        : Container(
                            width: 56,
                            height: 56,
                            color: Colors.white.withOpacity(0.1),
                            child: Icon(Icons.music_note_rounded,
                                color: Colors.white.withOpacity(0.6), size: 28),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          np.trackName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          np.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    np.isPlaying
                        ? Icons.play_circle_outline_rounded
                        : Icons.pause_circle_outline_rounded,
                    color: Colors.white.withOpacity(0.5),
                    size: 24,
                  ),
                ],
              ),
      ),
    );
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Widget _controlsCard() {
    return _glassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _iconButton(Icons.skip_previous_rounded, _doSkipPrev),
            _iconButton(Icons.pause_rounded, _doPause),
            _iconButton(Icons.play_arrow_rounded, _doPlay, large: true),
            _iconButton(Icons.skip_next_rounded, _doSkipNext),
          ],
        ),
      ),
    );
  }

  // ── Search card ───────────────────────────────────────────────────────────

  Widget _searchCard() {
    return _glassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Search tracks',
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        onSubmitted: (_) => _search(),
                        decoration: InputDecoration(
                          hintText: 'Song name, artist…',
                          hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.4), fontSize: 13),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _searching ? null : _search,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFf85187).withOpacity(0.7),
                    ),
                    child: _searching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...List.generate(
                _searchResults.length,
                (i) {
                  final t = _searchResults[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: GestureDetector(
                      onTap: () => _playTrack(t.uri),
                      onLongPress: () async {
                        final ok = await _api.queueTrack(t.uri);
                        if (mounted) {
                          setState(() => _statusMessage =
                              ok ? '"${t.name}" added to queue' : 'Queue failed');
                        }
                      },
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: t.albumArtUrl != null
                                ? Image.network(t.albumArtUrl!,
                                    width: 40, height: 40, fit: BoxFit.cover)
                                : Container(
                                    width: 40,
                                    height: 40,
                                    color: Colors.white.withOpacity(0.1),
                                    child: Icon(Icons.music_note,
                                        color: Colors.white38, size: 18),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500)),
                                Text(t.artistName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.5),
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          Icon(Icons.play_arrow_rounded,
                              color: Colors.white.withOpacity(0.4), size: 22),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Tap to play • Long press to queue',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Queue card ────────────────────────────────────────────────────────────

  Widget _queueCard() {
    return _glassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Queue by URI',
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: TextField(
                  controller: _uriController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'spotify:track:xxxxxxxxxxxxxxxx',
                    hintStyle:
                        TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _glassButton(
              label: 'Add to Queue',
              icon: Icons.add_rounded,
              onTap: _queueTrack,
              highlight: true,
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared glass widgets ──────────────────────────────────────────────────

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
                const Color(0xFF1E3DE1).withOpacity(0.40),
                const Color(0xFFf85187).withOpacity(0.40),
              ],
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

  Widget _glassButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    bool highlight = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          color: highlight
              ? const Color(0xFFf85187).withOpacity(onTap != null ? 0.75 : 0.35)
              : Colors.white.withOpacity(0.12),
          boxShadow: highlight && onTap != null
              ? [
                  BoxShadow(
                    color: const Color(0xFFf85187).withOpacity(0.45),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, Future<void> Function() onTap,
      {bool large = false}) {
    return GestureDetector(
      onTap: () async {
        try {
          await onTap();
        } catch (e) {
          if (mounted) setState(() => _statusMessage = 'Error: $e');
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.all(large ? 14 : 10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(large ? 0.15 : 0.08),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: large ? 36 : 28,
        ),
      ),
    );
  }
}
