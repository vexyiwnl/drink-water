import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/session_logic.dart';
import '../theme.dart';

/// Daily totals for the last 7/30 days against a dashed goal line.
class IntakeChart extends StatelessWidget {
  const IntakeChart({
    super.key,
    required this.days,
    required this.today,
    required this.goal,
    required this.span,
    required this.onSpan,
  });

  final Map<DateTime, DayStat> days;
  final DateTime today;
  final int goal;
  final int span;
  final ValueChanged<int> onSpan;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall!.copyWith(color: textMuted);
    final dates = [for (var i = span - 1; i >= 0; i--) addDays(today, -i)];
    final totals = [for (final d in dates) days[d]?.total ?? 0];
    final top = max(goal, totals.fold(0, max)) * 1.15;
    final step = top <= 2400 ? 500.0 : (top <= 6000 ? 1000.0 : 2000.0);
    String k(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k' : '${v.toInt()}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Daily intake (ml)', style: text.titleMedium!.copyWith(fontWeight: FontWeight.w600))),
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 7, label: Text('7 days')), ButtonSegment(value: 30, label: Text('30 days'))],
              selected: {span},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onSpan(s.first),
            ),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            height: 220,
            child: BarChart(
              duration: const Duration(milliseconds: 400),
              BarChartData(
                maxY: top,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: step,
                  getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFF203858), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: step,
                      maxIncluded: false,
                      getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(k(v), style: muted)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        // 30-day view: label every 5th day, counting back from today.
                        final show = span == 7 || (dates.length - 1 - i) % 5 == 0;
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(show ? DateFormat(span == 7 ? 'E' : 'd/M').format(dates[i]) : '', style: muted),
                        );
                      },
                    ),
                  ),
                ),
                extraLinesData: ExtraLinesData(horizontalLines: [
                  HorizontalLine(
                    y: goal.toDouble(),
                    color: aqua.withValues(alpha: 0.7),
                    strokeWidth: 1.5,
                    dashArray: [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: muted.copyWith(color: aqua),
                      labelResolver: (_) => 'Goal ${k(goal.toDouble())}',
                    ),
                  ),
                ]),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => cardHigh,
                    getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                      '${DateFormat('EEE d MMM').format(dates[group.x])}\n${rod.toY.round()} ml',
                      const TextStyle(color: textMain, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                barGroups: [
                  for (final (i, d) in dates.indexed)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: totals[i].toDouble(),
                        width: span == 7 ? 22 : 7,
                        color: (days[d]?.met ?? false) ? aqua : aquaDeep.withValues(alpha: 0.55),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ]),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
