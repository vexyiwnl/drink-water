import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'session_logic.dart';

part 'db.g.dart';

const _uuid = Uuid();

/// Columns every synced row carries. `dirty` = changed locally, not yet pushed (M4).
mixin Synced on Table {
  TextColumn get id => text().clientDefault(() => _uuid.v4())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

class DaySessions extends Table with Synced {
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get goalMl => integer()();
}

class Entries extends Table with Synced {
  TextColumn get sessionId => text().references(DaySessions, #id)();
  IntColumn get amountMl => integer()();
  DateTimeColumn get loggedAt => dateTime()();
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [DaySessions, Entries, Settings])
class AppDb extends _$AppDb {
  AppDb([QueryExecutor? executor])
      : super(executor ??
            driftDatabase(
              name: 'drinkwater',
              native: const DriftNativeOptions(
                databaseDirectory: getApplicationSupportDirectory,
                // The Android notification action (M3) writes from a background isolate.
                shareAcrossIsolates: true,
              ),
            ));

  @override
  int get schemaVersion => 1;

  SimpleSelectStatement<$DaySessionsTable, DaySession> _openSession() =>
      select(daySessions)
        ..where((s) => s.endedAt.isNull() & s.deleted.not())
        ..orderBy([(s) => OrderingTerm.desc(s.startedAt)])
        ..limit(1);

  Stream<DaySession?> watchOpenSession() => _openSession().watchSingleOrNull();

  Stream<List<Entry>> watchEntries(String sessionId) => (select(entries)
        ..where((e) => e.sessionId.equals(sessionId) & e.deleted.not())
        ..orderBy([(e) => OrderingTerm.desc(e.loggedAt)]))
      .watch();

  /// Every session with its summed intake, oldest first. Few hundred rows a year, so the
  /// calendar and stats just work on the full list in memory.
  Stream<List<(DaySession, int)>> watchSessionTotals() => customSelect(
        'SELECT s.*, COALESCE(SUM(e.amount_ml), 0) AS total FROM day_sessions s '
        'LEFT JOIN entries e ON e.session_id = s.id AND e.deleted = 0 '
        'WHERE s.deleted = 0 GROUP BY s.id ORDER BY s.started_at',
        readsFrom: {daySessions, entries},
      ).watch().map((rows) => [for (final r in rows) (daySessions.map(r.data), r.read<int>('total'))]);


  /// Called after every local edit (never after applying synced rows), so the
  /// sync engine knows there's something to push. Null when signed out.
  void Function()? onLocalChange;

  Future<T> _edit<T>(Future<T> Function() body) async {
    final result = await transaction(body);
    onLocalChange?.call();
    return result;
  }

  /// Closes any open session. The next one starts on "Start day" or the next log.
  Future<void> endDay() => _edit(() {
        final now = DateTime.now();
        return (update(daySessions)..where((s) => s.endedAt.isNull())).write(
            DaySessionsCompanion(endedAt: Value(now), updatedAt: Value(now), dirty: const Value(true)));
      });

  Future<String> startDay(int goalMl) => _edit(() async {
        await endDay();
        final s = await into(daySessions)
            .insertReturning(DaySessionsCompanion.insert(startedAt: DateTime.now(), goalMl: goalMl));
        return s.id;
      });

  /// Logs water into the open session, starting one if none is open. Returns the entry id.
  Future<String> addWater(int ml, int goalMl) => _edit(() async {
        final sessionId = (await _openSession().getSingleOrNull())?.id ?? await startDay(goalMl);
        final e = await into(entries).insertReturning(
            EntriesCompanion.insert(sessionId: sessionId, amountMl: ml, loggedAt: DateTime.now()));
        return e.id;
      });

  Future<void> updateEntry(String id, {int? ml, DateTime? loggedAt, bool? deleted}) =>
      _edit(() => (update(entries)..where((e) => e.id.equals(id))).write(EntriesCompanion(
            amountMl: Value.absentIfNull(ml),
            loggedAt: Value.absentIfNull(loggedAt),
            deleted: Value.absentIfNull(deleted),
            updatedAt: Value(DateTime.now()),
            dirty: const Value(true),
          )));

  Future<DaySession?> getOpenSession() => _openSession().getSingleOrNull();

  Stream<Map<String, String>> watchSettings() =>
      select(settings).watch().map((rows) => {for (final r in rows) r.key: r.value});

  Future<Map<String, String>> getSettings() => watchSettings().first;

  /// Saves settings. Keys starting with `local.` are per-device (never synced).
  /// A new `goal_ml` also applies to the day in progress.
  Future<void> saveSettings(Map<String, String> values) => _edit(() async {
        final now = DateTime.now();
        for (final MapEntry(:key, :value) in values.entries) {
          await into(settings).insertOnConflictUpdate(
              SettingsCompanion.insert(key: key, value: value, updatedAt: Value(now), dirty: const Value(true)));
        }
        if (int.tryParse(values['goal_ml'] ?? '') case final goal?) {
          await (update(daySessions)..where((s) => s.endedAt.isNull())).write(
              DaySessionsCompanion(goalMl: Value(goal), updatedAt: Value(now), dirty: const Value(true)));
        }
      });

  /// Two devices can each start a day before they've synced. A newer open day that
  /// started within [staleAfter] of the older one is the same day: its entries move
  /// into the older one. Otherwise the older one was forgotten: close it there.
  /// Returns whether anything changed (so the caller pushes again).
  Future<bool> reconcileOpenSessions() => transaction(() async {
        final open = await (select(daySessions)
              ..where((s) => s.endedAt.isNull() & s.deleted.not())
              ..orderBy([(s) => OrderingTerm.asc(s.startedAt)]))
            .get();
        if (open.length < 2) return false;
        final now = DateTime.now();
        var keep = open.first;
        for (final s in open.skip(1)) {
          if (s.startedAt.difference(keep.startedAt) < staleAfter) {
            await (update(entries)..where((e) => e.sessionId.equals(s.id))).write(
                EntriesCompanion(sessionId: Value(keep.id), updatedAt: Value(now), dirty: const Value(true)));
            await (update(daySessions)..where((x) => x.id.equals(s.id))).write(
                DaySessionsCompanion(deleted: const Value(true), updatedAt: Value(now), dirty: const Value(true)));
          } else {
            await (update(daySessions)..where((x) => x.id.equals(keep.id))).write(
                DaySessionsCompanion(endedAt: Value(s.startedAt), updatedAt: Value(now), dirty: const Value(true)));
            keep = s;
          }
        }
        return true;
      });
}
