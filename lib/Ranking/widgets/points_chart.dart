import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

// ── Chart range ───────────────────────────────────────────────────────────────

enum _ChartRange { h24, d7, d30, d90, y1 }

extension _ChartRangeLabel on _ChartRange {
  String get label {
    switch (this) {
      case _ChartRange.h24: return '24H';
      case _ChartRange.d7:  return '7D';
      case _ChartRange.d30: return '30D';
      case _ChartRange.d90: return '90D';
      case _ChartRange.y1:  return '1Y';
    }
  }

  int get days {
    switch (this) {
      case _ChartRange.h24: return 1;
      case _ChartRange.d7:  return 7;
      case _ChartRange.d30: return 30;
      case _ChartRange.d90: return 90;
      case _ChartRange.y1:  return 365;
    }
  }
}

// ── PointsChart ───────────────────────────────────────────────────────────────

class PointsChart extends StatefulWidget {
  final String entityId;

  const PointsChart({super.key, required this.entityId});

  @override
  State<PointsChart> createState() => _PointsChartState();
}

class _PointsChartState extends State<PointsChart> {
  _ChartRange _range  = _ChartRange.d30;
  int? _touchedIndex;

  // Fetches and returns [(dayKey, closePoints)] sorted ascending.
  Future<List<(String, double)>> _fetchPoints(_ChartRange range) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: range.days))
        .toIso8601String()
        .substring(0, 10); // "YYYY-MM-DD"

    final snap = await FirebaseFirestore.instance
        .collection('rankings')
        .doc(widget.entityId)
        .collection('history')
        .orderBy('date', descending: true)
        .limit(range == _ChartRange.y1 ? 400 : range.days + 5)
        .get();

    final docs = snap.docs
        .where((d) => (d.data()['date'] as String?) != null &&
            (d.data()['date'] as String).compareTo(cutoff) >= 0)
        .map((d) => (
              d.data()['date'] as String,
              ((d.data()['close_points'] as num?) ?? 0).toDouble(),
            ))
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1)); // ascending

    if (range == _ChartRange.y1) {
      return _monthlyAggregate(docs);
    }
    return docs;
  }

  // For 1Y: collapse to one point per month (last close in that month).
  // Forward-fills missing months.
  List<(String, double)> _monthlyAggregate(List<(String, double)> days) {
    if (days.isEmpty) return [];
    final byMonth = <String, double>{};
    for (final (day, pts) in days) {
      byMonth[day.substring(0, 7)] = pts; // keep latest (list is sorted asc)
    }
    final keys = byMonth.keys.toList()..sort();
    final result = <(String, double)>[];
    double last = byMonth[keys.first]!;
    for (final k in keys) {
      last = byMonth[k] ?? last;
      result.add((k, last));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRangeSelector(),
        const SizedBox(height: 8),
        FutureBuilder<List<(String, double)>>(
          key: ValueKey('${widget.entityId}_${_range.name}'),
          future: _fetchPoints(_range),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 160,
                child: Center(
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 1.5),
                ),
              );
            }
            final data = snap.data ?? [];
            if (data.length < 2) {
              return SizedBox(
                height: 160,
                child: Center(
                  child: Text(
                    'Not enough history yet.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.40),
                        fontSize: 12),
                  ),
                ),
              );
            }
            return _buildChart(data);
          },
        ),
      ],
    );
  }

  // ── Range selector ────────────────────────────────────────────────────────────

  Widget _buildRangeSelector() {
    return Row(
      children: _ChartRange.values.map((r) {
        final sel = r == _range;
        return GestureDetector(
          onTap: () {
            if (_range != r) setState(() { _range = r; _touchedIndex = null; });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: sel
                  ? AppTheme.navSelectedIcon.withValues(alpha: 0.20)
                  : Colors.white.withValues(alpha: 0.06),
              border: Border.all(
                color: sel
                    ? AppTheme.navSelectedIcon.withValues(alpha: 0.55)
                    : Colors.transparent,
                width: 0.8,
              ),
            ),
            child: Text(
              r.label,
              style: TextStyle(
                color: sel
                    ? AppTheme.navSelectedIcon
                    : Colors.white.withValues(alpha: 0.50),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Line chart ────────────────────────────────────────────────────────────────

  Widget _buildChart(List<(String, double)> data) {
    final spots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i].$2));
    }

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.12;

    final gradientColors = [
      AppTheme.navSelectedIcon.withValues(alpha: 0.60),
      AppTheme.navSelectedIcon.withValues(alpha: 0.05),
    ];

    return SizedBox(
      height: 160,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: minY - padding,
          maxY: maxY + padding,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY).clamp(1, double.infinity) / 3,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.white.withValues(alpha: 0.07),
              strokeWidth: 0.8,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: _bottomInterval(spots.length),
                getTitlesWidget: (value, meta) {
                  final idx = value.round();
                  if (idx < 0 || idx >= data.length) return const SizedBox();
                  final label = _formatLabel(data[idx].$1);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.40),
                        fontSize: 9,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchCallback: (evt, res) {
              setState(() {
                _touchedIndex = res?.lineBarSpots?.firstOrNull?.x.round();
              });
            },
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1A1A2E),
              tooltipBorder:
                  BorderSide(color: AppTheme.navSelectedIcon.withValues(alpha: 0.40)),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((s) {
                  final idx = s.x.round();
                  final label = idx < data.length ? data[idx].$1 : '';
                  return LineTooltipItem(
                    '${s.y.round()} pts\n',
                    TextStyle(
                        color: AppTheme.navSelectedIcon,
                        fontWeight: FontWeight.w700,
                        fontSize: 12),
                    children: [
                      TextSpan(
                        text: label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w400,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: AppTheme.navSelectedIcon,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: _touchedIndex != null,
                checkToShowDot: (spot, _) => spot.x.round() == _touchedIndex,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 4,
                  color: AppTheme.navSelectedIcon,
                  strokeColor: Colors.white,
                  strokeWidth: 1.5,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: gradientColors,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 250),
      ),
    );
  }

  double _bottomInterval(int count) {
    if (count <= 8)  return 1;
    if (count <= 15) return 2;
    if (count <= 35) return 7;
    return (count / 4).roundToDouble();
  }

  String _formatLabel(String dayKey) {
    // dayKey is "YYYY-MM-DD" or "YYYY-MM" for 1Y monthly
    final parts = dayKey.split('-');
    if (parts.length == 2) {
      // monthly: "YYYY-MM" → "MMM"
      const months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      final m = int.tryParse(parts[1]) ?? 1;
      return months[(m - 1).clamp(0, 11)];
    }
    // daily: "MM/DD"
    return '${parts[1]}/${parts[2]}';
  }
}
