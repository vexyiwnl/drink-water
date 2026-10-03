import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/db.dart';
import 'data/session_logic.dart';
import 'data/sync.dart';

/// One database per isolate. The Android notification action opens its own in a
/// background isolate; drift shares the underlying connection between them.
final appDb = AppDb();

class AppSettings {
  const AppSettings(this._m);
  static const defaults = AppSettings({});

  final Map<String, String> _m;

  bool _flag(String key, bool fallback) => switch (_m[key]) { 'true' => true, 'false' => false, _ => fallback };

  int get goalMl => int.tryParse(_m['goal_ml'] ?? '') ?? 3000;
  List<int> get quickAdds => parseAmounts(_m['quick_adds'] ?? '') ?? const [150, 250, 500];
  int get intervalMin => int.tryParse(_m['interval_min'] ?? '') ?? 60;
  bool get stopAtGoal => _flag('stop_at_goal', true);

  // Per-device
  bool get remindersOn => _flag('local.reminders_on', true);
  bool get winFlash => _flag('local.win_flash', true);
  bool get winToast => _flag('local.win_toast', false);
}

final dbProvider = Provider<AppDb>((ref) => appDb);

/// Set in main() once Supabase is initialised.
late final SyncService syncService;

/// Rebuilds on sign-in/out; read the user from `Supabase.instance.client.auth`.
final authProvider = StreamProvider<AuthState>((ref) => Supabase.instance.client.auth.onAuthStateChange);

final settingsProvider =
    StreamProvider<AppSettings>((ref) => ref.watch(dbProvider).watchSettings().map(AppSettings.new));

final openSessionProvider = StreamProvider<DaySession?>((ref) => ref.watch(dbProvider).watchOpenSession());

final todayEntriesProvider = StreamProvider<List<Entry>>((ref) {
  final id = ref.watch(openSessionProvider.select((s) => s.value?.id));
  return id == null ? Stream.value(const []) : ref.watch(dbProvider).watchEntries(id);
});

final entriesProvider = StreamProvider.family<List<Entry>, String>(
    (ref, sessionId) => ref.watch(dbProvider).watchEntries(sessionId));

final sessionTotalsProvider =
    StreamProvider<List<(DaySession, int)>>((ref) => ref.watch(dbProvider).watchSessionTotals());

/// Calendar date -> that day's result.
final dayStatsProvider = Provider<Map<DateTime, DayStat>>((ref) => groupByDate([
      for (final (s, total) in ref.watch(sessionTotalsProvider).value ?? const <(DaySession, int)>[])
        (s.startedAt, s.endedAt == null, s.goalMl, total),
    ]));

/// Ticks every minute so "started 5h ago" and the 30h nudge stay current.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  while (true) {
    yield DateTime.now();
    await Future<void>.delayed(const Duration(minutes: 1));
  }
});
