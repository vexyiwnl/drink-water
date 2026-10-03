/// Pure date/settings/stats logic, kept Flutter-free so it's easy to test.
library;

import 'dart:math';

const staleAfter = Duration(hours: 30);

bool shouldSuggestEnding(DateTime startedAt, DateTime now) => now.difference(startedAt) > staleAfter;

/// Applies an edited clock time to an entry. Sessions cross midnight, so pick the
/// day (-1/0/+1) closest to the original time that isn't in the future.
DateTime withTime(DateTime original, int hour, int minute, DateTime now) {
  final candidates = [-1, 0, 1]
      .map((d) => DateTime(original.year, original.month, original.day + d, hour, minute))
      .where((t) => !t.isAfter(now));
  return candidates.reduce(
      (a, b) => a.difference(original).abs() <= b.difference(original).abs() ? a : b);
}

/// "150, 250,500" -> [150, 250, 500]; null if invalid (1–6 amounts, each 1–5000 ml).
List<int>? parseAmounts(String input) {
  final parts = input.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final amounts = parts.map(int.tryParse).toList();
  if (amounts.isEmpty || amounts.length > 6) return null;
  if (amounts.any((a) => a == null || a < 1 || a > 5000)) return null;
  return amounts.cast<int>();
}

String formatDuration(Duration d) => d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}m' : '${d.inMinutes}m';

DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// One calendar date's result. Several sessions starting on the same date add up.
class DayStat {
  const DayStat(this.total, this.goal, this.open);

  final int total;
  final int goal;
  final bool open;

  double get fraction => goal <= 0 ? 0 : total / goal;
  bool get met => total >= goal;
}

/// Groups (startedAt, open, goal, total) sessions by the local date they started on.
Map<DateTime, DayStat> groupByDate(Iterable<(DateTime, bool, int, int)> sessions) {
  final days = <DateTime, DayStat>{};
  for (final (startedAt, open, goal, total) in sessions) {
    final d = dateOnly(startedAt);
    final prev = days[d];
    days[d] = prev == null
        ? DayStat(total, goal, open)
        : DayStat(prev.total + total, max(prev.goal, goal), prev.open || open);
  }
  return days;
}

/// Consecutive met days ending today. An unfinished day (today with nothing yet, or a
/// still-open session) doesn't break the streak; a missing or closed unmet day does.
int currentStreak(Map<DateTime, DayStat> days, DateTime now) {
  final today = dateOnly(now);
  bool pending(DateTime d) {
    final s = days[d];
    return s == null ? d == today : !s.met && s.open;
  }

  var d = today;
  while (pending(d)) {
    d = addDays(d, -1);
  }
  var streak = 0;
  while (days[d]?.met ?? false) {
    streak++;
    d = addDays(d, -1);
  }
  return streak;
}

int longestStreak(Map<DateTime, DayStat> days) {
  final met = [for (final e in days.entries) if (e.value.met) e.key]..sort();
  var best = 0, run = 0;
  for (var i = 0; i < met.length; i++) {
    run = i > 0 && addDays(met[i - 1], 1) == met[i] ? run + 1 : 1;
    best = max(best, run);
  }
  return best;
}

/// Average total of finished days in the last [span] calendar days; null if none.
int? averageOver(Map<DateTime, DayStat> days, DateTime now, {int span = 7}) {
  final today = dateOnly(now);
  final totals = [
    for (var i = 0; i < span; i++)
      if (days[addDays(today, -i)] case final s? when !s.open) s.total,
  ];
  return totals.isEmpty ? null : (totals.reduce((a, b) => a + b) / totals.length).round();
}

/// Reminders run while a day is open, unless they're off or the goal is met and [stopAtGoal].
bool remindersActive({required bool enabled, required int total, required int goal, required bool stopAtGoal}) =>
    enabled && !(stopAtGoal && total >= goal);

/// Reminder slots fall every [interval] after [last] (the last drink, or the day's start).
/// Returns the newest slot that is already due, or null if none is.
DateTime? dueSlot(DateTime last, Duration interval, DateTime now) {
  final k = now.difference(last).inMicroseconds ~/ interval.inMicroseconds;
  return k < 1 ? null : last.add(interval * k);
}

/// Slots still to come within [horizon], scheduled ahead so they fire with the app closed.
List<DateTime> upcomingSlots(DateTime last, Duration interval, DateTime now,
    {Duration horizon = const Duration(hours: 24)}) {
  final end = now.add(horizon);
  return [for (var t = (dueSlot(last, interval, now) ?? last).add(interval); t.isBefore(end); t = t.add(interval)) t];
}
