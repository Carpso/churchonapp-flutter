import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

/// Professional chart kit — single source for all app graphs.
/// Replaces the basic fl_chart usages that had flat colors, no grid,
/// no tooltips and weak legends. Every chart here uses the same
/// surface, typography (Plus Jakarta / Inter) and ChurchOnApp palette
/// (gold #FFD700 primary, slate, green/orange) so analytics feels
/// premium and consistent.

class ProChartCard extends StatelessWidget {
  const ProChartCard({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    required this.child,
    this.height = 220,
    this.padding = const EdgeInsets.all(20),
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget child;
  final double height;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: theme.primaryColor,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.4,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

String _compactCurrency(double v) =>
    NumberFormat.compactCurrency(symbol: 'K ', decimalDigits: v >= 10000 ? 1 : 0).format(v);

LinearGradient _barGradient(BuildContext context, {bool muted = false}) {
  final c = Theme.of(context).primaryColor;
  if (muted) return LinearGradient(colors: [c.withValues(alpha: 0.12), c.withValues(alpha: 0.08)]);
  return LinearGradient(
    colors: [c, const Color(0xFFFFC247)],
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
  );
}

LinearGradient _lineGradient(BuildContext context) => LinearGradient(
      colors: [Theme.of(context).primaryColor, const Color(0xFFFFB800)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );

// ── Pro Bar Chart ────────────────────────────────────────────────────────

class ProBarChart extends StatelessWidget {
  const ProBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.barWidth = 18,
    this.showGrid = true,
    this.compactCurrencyLeftTitles = true,
  });

  /// values in same order as labels (e.g. 6 months). Zero values render as muted ghost bars.
  final List<double> values;
  final List<String> labels;
  final double barWidth;
  final bool showGrid;
  final bool compactCurrencyLeftTitles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (values.isEmpty) {
      return Center(
        child: Text(
          'No data yet',
          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );
    }
    // Guard: NaN/Infinite/extreme inputs collapse to a safe range; negative
    // values clamp to 0 (this chart is magnitude-only — use a line chart for
    // signed series).
    final safeValues = values
        .map((v) => v.isFinite ? (v < 0 ? 0.0 : v) : 0.0)
        .toList(growable: false);
    final maxY = safeValues.fold<double>(0, (m, v) => v > m ? v : m);
    final topY = maxY == 0 ? 1.0 : maxY * 1.18;
    final step = _niceStep(topY);

    return BarChart(
      BarChartData(
        maxY: topY,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: showGrid,
          drawVerticalLine: false,
          horizontalInterval: step,
          getDrawingHorizontalLine: (v) => FlLine(
            color: theme.colorScheme.outline.withValues(alpha: 0.08),
            strokeWidth: 1,
            dashArray: [6, 6],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: step,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                // Only label at step intervals to avoid clutter
                if (value % step != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    compactCurrencyLeftTitles ? _compactCurrency(value) : value.toStringAsFixed(0),
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.w600),
                    textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    labels[i],
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.w700, letterSpacing: 0.2),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            getTooltipColor: (g) => const Color(0xFF0F172A),
            getTooltipItem: (group, gi, rod, ri) {
              final label = (group.x < labels.length) ? labels[group.x] : '';
              return BarTooltipItem(
                '$label\n${_compactCurrency(rod.toY)}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
              );
            },
          ),
        ),
        barGroups: List.generate(safeValues.length, (i) {
          final v = safeValues[i];
          final isZero = v == 0;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                // Zero weeks render as a visible ghost stub so "no giving"
                // is distinguishable from a missing data point.
                toY: isZero ? topY * 0.04 : v,
                width: barWidth,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                gradient: isZero ? null : _barGradient(context),
                color: isZero ? theme.colorScheme.outline.withValues(alpha: 0.14) : null,
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: topY,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                ),
              ),
            ],
          );
        }),
      ),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
    );
  }

  double _niceStep(double max) {
    if (max <= 50) return 10;
    if (max <= 200) return 50;
    if (max <= 1000) return 200;
    if (max <= 5000) return 1000;
    if (max <= 20000) return 5000;
    return (max / 4).ceilToDouble();
  }
}

// ── Pro Line Chart ───────────────────────────────────────────────────────

class ProLineChart extends StatelessWidget {
  const ProLineChart({
    super.key,
    required this.spots,
    required this.bottomLabels,
    this.showDots = true,
    this.curved = true,
  });

  /// spots ordered by x (time). bottomLabels[i] is the x label for spots[i].x
  final List<FlSpot> spots;
  final List<String> bottomLabels;
  final bool showDots;
  final bool curved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (spots.isEmpty) {
      return Center(
        child: Text('Not enough trend data', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.w600)),
      );
    }
    if (spots.length == 1) {
      // Single point can't draw a line — render as a labelled dot card.
      final y = spots.first.y;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart, size: 26, color: theme.primaryColor.withValues(alpha: 0.35)),
            const SizedBox(height: 6),
            Text(_compactCurrency(y.isFinite ? y : 0), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
            Text(bottomLabels.isNotEmpty ? bottomLabels.first : '', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    // Guard NaN/Infinity → 0; negatives clamp to the axis floor.
    final safeSpots = spots
        .map((s) => FlSpot(s.x.isFinite ? s.x : 0, s.y.isFinite ? (s.y < 0 ? 0 : s.y) : 0))
        .toList(growable: false);
    final maxY = safeSpots.map((s) => s.y).fold<double>(0, (m, v) => v > m ? v : m);
    final topY = maxY == 0 ? 1.0 : maxY * 1.22;
    final step = _niceStep(topY);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: topY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: step,
          getDrawingHorizontalLine: (v) => FlLine(
            color: theme.colorScheme.outline.withValues(alpha: 0.07),
            strokeWidth: 1,
            dashArray: [5, 7],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: step,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value % step != 0) return const SizedBox.shrink();
                return Text(
                  _compactCurrency(value),
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.38), fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= bottomLabels.length) return const SizedBox.shrink();
                // Thin labels — show every other if crowded
                final dense = bottomLabels.length > 8;
                if (dense && i % 2 == 1) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    bottomLabels[i],
                    style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withValues(alpha: 0.45), fontWeight: FontWeight.w700),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            getTooltipColor: (t) => const Color(0xFF0F172A),
            getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
              final idx = s.x.toInt();
              final label = (idx >= 0 && idx < bottomLabels.length) ? bottomLabels[idx] : '';
              return LineTooltipItem(
                '$label  •  ${_compactCurrency(s.y.isFinite ? s.y : 0)}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: safeSpots,
            isCurved: curved,
            curveSmoothness: 0.22,
            gradient: _lineGradient(context),
            barWidth: 3.2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: showDots,
              getDotPainter: (spot, percent, bar, idx) => FlDotCirclePainter(
                radius: 3.5,
                color: Colors.white,
                strokeWidth: 2.2,
                strokeColor: theme.primaryColor,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [theme.primaryColor.withValues(alpha: 0.14), theme.primaryColor.withValues(alpha: 0.0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
    );
  }

  double _niceStep(double max) {
    if (max <= 100) return 25;
    if (max <= 500) return 100;
    if (max <= 2000) return 500;
    if (max <= 8000) return 2000;
    return (max / 4).ceilToDouble();
  }
}

// ── Pro Pie / Donut ──────────────────────────────────────────────────────

class ProPieChart extends StatefulWidget {
  const ProPieChart({
    super.key,
    required this.sections,
    this.centerLabel,
    this.centerValue,
  });

  /// Each section: value >0. Colors/legends derived here. Provide at least 1.
  final List<ProPieSection> sections;
  final String? centerLabel;
  final String? centerValue;

  @override
  State<ProPieChart> createState() => _ProPieChartState();
}

class ProPieSection {
  const ProPieSection({required this.label, required this.value, required this.color, this.icon});
  final String label;
  final double value;
  final Color color;
  final IconData? icon;
}

class _ProPieChartState extends State<ProPieChart> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.sections.fold<double>(0, (s, e) => s + e.value);
    if (total == 0) {
      return Center(
        child: Text('No contributions to classify', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.45), fontSize: 11, fontWeight: FontWeight.w600)),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  pieTouchData: PieTouchData(
                    touchCallback: (e, r) {
                      if (r != null && r.touchedSection != null) {
                        setState(() => _touched = r.touchedSection!.touchedSectionIndex);
                      } else {
                        setState(() => _touched = -1);
                      }
                    },
                  ),
                  sectionsSpace: 3,
                  centerSpaceRadius: 52,
                  // Guard: negative values are clamped out of the pie (they
                  // would corrupt the sweep-angle math and render NaN arcs).
                  sections: List.generate(widget.sections.length, (i) {
                    final s = widget.sections[i];
                    final safeValue = s.value <= 0 ? 0.0 : s.value;
                    final pct = total > 0 ? (safeValue / total) : 0.0;
                    if (safeValue == 0) {
                      return PieChartSectionData(value: 0, color: Colors.transparent, radius: 0);
                    }
                    final isTouched = i == _touched;
                    return PieChartSectionData(
                      value: safeValue,
                      color: s.color,
                      radius: isTouched ? 58 : 50,
                      title: '${(pct * 100).toStringAsFixed(0)}%',
                      titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                      titlePositionPercentageOffset: 0.62,
                      borderSide: isTouched ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                    );
                  }),
                ),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
              ),
              // Center metric
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.centerValue != null)
                    Text(
                      widget.centerValue!,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface, letterSpacing: -0.5),
                    ),
                  if (widget.centerLabel != null)
                    Text(
                      widget.centerLabel!,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: widget.sections.where((s) => s.value > 0).map((s) {
            final pct = ((s.value / total) * 100).clamp(0, 100).toStringAsFixed(0);
            final idx = widget.sections.indexOf(s);
            final isTouched = idx == _touched;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: isTouched ? s.color.withValues(alpha: 0.12) : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: isTouched ? s.color.withValues(alpha: 0.22) : theme.colorScheme.outline.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(s.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface)),
                  const SizedBox(width: 4),
                  Text('$pct%', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.w700)),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
