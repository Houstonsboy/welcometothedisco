import 'package:flutter/foundation.dart';

/// Minimal Stopwatch-based timing helper for diagnosing where screen-load
/// time goes. Debug-only: [mark]/[end] go through [debugPrint], which is a
/// no-op in release builds.
///
/// Usage:
///   final trace = PerfTrace('posts_feed')..mark('query_start');
///   final data = await someQuery();
///   trace..mark('first_snapshot');
///   WidgetsBinding.instance.addPostFrameCallback((_) {
///     trace..mark('first_frame')..end();
///   });
class PerfTrace {
  PerfTrace(this.label) : _sw = Stopwatch()..start();

  final String label;
  final Stopwatch _sw;
  final List<String> _marks = [];

  void mark(String phase) {
    _marks.add('$phase=${_sw.elapsedMilliseconds}ms');
  }

  void end() {
    debugPrint('[perf:$label] ${_marks.join(', ')}, total=${_sw.elapsedMilliseconds}ms');
  }
}
