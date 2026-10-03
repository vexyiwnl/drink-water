import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/session_logic.dart';
import '../providers.dart';
import '../theme.dart';
import 'day_details.dart';
import 'intake_chart.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _span = 7;

  @override
  Widget build(BuildContext context) {
    final days = ref.watch(dayStatsProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final goal = ref.watch(settingsProvider).value?.goalMl ?? AppSettings.defaults.goalMl;

    final calendar = _MonthCalendar(
      month: _month,
      days: days,
      today: dateOnly(now),
      onMonth: (delta) => setState(() => _month = DateTime(_month.year, _month.month + delta)),
    );
    final stats = _StatTiles(days: days, now: now);
    final chart = IntakeChart(
      days: days,
      today: dateOnly(now),
      goal: goal,
      span: _span,
      onSpan: (s) => setState(() => _span = s),
    );
    final title = Text('History',
        style: Theme.of(context).textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w600));

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(28), children: [title, const SizedBox(height: 20), calendar]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 76, 28, 28),
              children: [stats, const SizedBox(height: 20), chart],
            ),
          ),
        ]);
      }
      return ListView(padding: const EdgeInsets.all(20), children: [
        title,
        const SizedBox(height: 16),
        stats,
        const SizedBox(height: 16),
        calendar,
        const SizedBox(height: 16),
        chart,
      ]);
    });
  }
}

class _StatTiles extends StatelessWidget {
  const _StatTiles({required this.days, required this.now});

  final Map<DateTime, DayStat> days;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final avg = averageOver(days, now);
    final current = currentStreak(days, now);
    final longest = longestStreak(days);
    String plural(int n) => '$n ${n == 1 ? 'day' : 'days'}';

    return Row(children: [
      for (final (i, (icon, value, label)) in [
        (Icons.local_fire_department_outlined, plural(current), 'Current streak'),
        (Icons.emoji_events_outlined, plural(longest), 'Longest streak'),
        (Icons.show_chart, avg == null ? '—' : '${NumberFormat.decimalPattern().format(avg)} ml', '7-day average'),
      ].indexed) ...[
        if (i > 0) const SizedBox(width: 12),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: aqua, size: 22),
                const SizedBox(height: 10),
                FittedBox(
                  child: Text(value,
                      style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 2),
                Text(label, style: Theme.of(context).textTheme.bodySmall!.copyWith(color: textMuted)),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }
}

/// Sequential single-hue scale: more aqua = closer to goal.
Color? _fill(DayStat? s) => switch (s?.fraction) {
      null => null,
      >= 1 => aqua,
      >= 0.5 => aqua.withValues(alpha: 0.45),
      _ => aqua.withValues(alpha: 0.16),
    };

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({required this.month, required this.days, required this.today, required this.onMonth});

  final DateTime month;
  final Map<DateTime, DayStat> days;
  final DateTime today;
  final ValueChanged<int> onMonth;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final lead = month.weekday - 1; // Monday first
    final count = DateUtils.getDaysInMonth(month.year, month.month);
    final isCurrentMonth = month.year == today.year && month.month == today.month;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            IconButton(tooltip: 'Previous month', onPressed: () => onMonth(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(DateFormat('MMMM yyyy').format(month),
                  textAlign: TextAlign.center, style: text.titleMedium!.copyWith(fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: isCurrentMonth ? null : () => onMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(child: Text(d, textAlign: TextAlign.center, style: text.labelMedium!.copyWith(color: textMuted))),
          ]),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (var i = 0; i < lead; i++) const SizedBox(),
              for (var day = 1; day <= count; day++) _dayCell(context, DateTime(month.year, month.month, day)),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 16, runSpacing: 6, alignment: WrapAlignment.center, children: [
            for (final (label, frac) in const [('< 50%', 0.0), ('50–99%', 0.5), ('100%+', 1.0)])
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: _fill(DayStat((frac * 100).round(), 100, false)), borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 6),
                Text(label, style: text.bodySmall!.copyWith(color: textMuted)),
              ]),
          ]),
        ]),
      ),
    );
  }

  Widget _dayCell(BuildContext context, DateTime date) {
    final s = days[date];
    final cell = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _fill(s),
        borderRadius: BorderRadius.circular(12),
        border: date == today ? Border.all(color: aqua, width: 1.5) : null,
      ),
      child: Text(
        '${date.day}',
        style: TextStyle(
          color: s == null ? (date.isAfter(today) ? textMuted.withValues(alpha: 0.4) : textMuted) : (s.met ? navy : textMain),
          fontWeight: s == null ? FontWeight.w400 : FontWeight.w600,
        ),
      ),
    );
    if (s == null) return cell;
    return Tooltip(
      message: '${s.total} / ${s.goal} ml · ${(s.fraction * 100).round()}%${s.open ? ' (in progress)' : ''}',
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => showDayDetails(context, date), child: cell),
    );
  }
}
