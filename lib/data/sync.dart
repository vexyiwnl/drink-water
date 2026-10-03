import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'db.dart';

class SyncState {
  const SyncState({this.lastSync, this.error, this.busy = false});

  final DateTime? lastSync;
  final String? error;
  final bool busy;
}

/// Offline-first sync with Supabase, last write wins per row.
///
/// Push: rows marked `dirty` are upserted (the server ignores ones older than what
/// it has). Pull: rows whose `server_updated_at` is past our cursor, applied when
/// newer than the local copy. Runs after local edits, on realtime changes from the
/// other device, on resume, and every 5 minutes. Failures just wait for the next run.
class SyncService {
  SyncService(this.db, this.sb);

  final AppDb db;
  final SupabaseClient sb;
  final state = ValueNotifier(const SyncState());

  Timer? _debounce;
  Future<void>? _running;
  bool _again = false;
  RealtimeChannel? _channel;

  void start() {
    db.onLocalChange = () => schedule();
    sb.auth.onAuthStateChange.listen((s) {
      if (s.session == null) {
        _unsubscribe();
      } else {
        _subscribe();
        schedule(Duration.zero);
      }
    });
    AppLifecycleListener(onResume: () => schedule(Duration.zero));
    Timer.periodic(const Duration(minutes: 5), (_) => schedule(Duration.zero));
  }

  bool get signedIn => sb.auth.currentUser != null;

  void schedule([Duration delay = const Duration(seconds: 2)]) {
    if (!signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(delay, syncNow);
  }

  /// One run at a time; a request during a run queues exactly one more.
  Future<void> syncNow() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _run().whenComplete(() {
      _running = null;
      if (_again) {
        _again = false;
        syncNow();
      }
    });
  }

  Future<void> _run() async {
    if (!signedIn) return;
    state.value = SyncState(lastSync: state.value.lastSync, busy: true);
    try {
      await _push();
      await _pull();
      if (await db.reconcileOpenSessions()) await _push();
      state.value = SyncState(lastSync: DateTime.now());
    } catch (e) {
      debugPrint('Sync failed: $e');
      state.value = SyncState(lastSync: state.value.lastSync, error: '$e');
    }
  }

  static String _ts(DateTime t) => t.toUtc().toIso8601String();
  static DateTime? _dt(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

  Future<void> _markClean(TableInfo table, String idColumn, String id, DateTime updatedAt) => db.customUpdate(
        // Only if unchanged since we read it — an edit made mid-push stays dirty.
        'UPDATE ${table.actualTableName} SET dirty = 0 WHERE $idColumn = ? AND updated_at = ?',
        variables: [Variable.withString(id), Variable.withDateTime(updatedAt)],
        updates: {table},
      );

  Future<void> _push() async {
    final sessions = await (db.select(db.daySessions)..where((s) => s.dirty)).get();
    if (sessions.isNotEmpty) {
      await sb.from('day_sessions').upsert([
        for (final s in sessions)
          {
            'id': s.id,
            'started_at': _ts(s.startedAt),
            'ended_at': s.endedAt == null ? null : _ts(s.endedAt!),
            'goal_ml': s.goalMl,
            'updated_at': _ts(s.updatedAt),
            'deleted': s.deleted,
          },
      ]);
      for (final s in sessions) {
        await _markClean(db.daySessions, 'id', s.id, s.updatedAt);
      }
    }

    final entries = await (db.select(db.entries)..where((e) => e.dirty)).get();
    if (entries.isNotEmpty) {
      await sb.from('entries').upsert([
        for (final e in entries)
          {
            'id': e.id,
            'session_id': e.sessionId,
            'amount_ml': e.amountMl,
            'logged_at': _ts(e.loggedAt),
            'updated_at': _ts(e.updatedAt),
            'deleted': e.deleted,
          },
      ]);
      for (final e in entries) {
        await _markClean(db.entries, 'id', e.id, e.updatedAt);
      }
    }

    final settings =
        await (db.select(db.settings)..where((s) => s.dirty & s.key.like('local.%').not())).get();
    if (settings.isNotEmpty) {
      await sb.from('settings').upsert(
        [for (final s in settings) {'key': s.key, 'value': s.value, 'updated_at': _ts(s.updatedAt)}],
        onConflict: 'user_id,key',
      );
      for (final s in settings) {
        await _markClean(db.settings, 'key', s.key, s.updatedAt);
      }
    }
  }

  Future<void> _pull() async {
    await _pullTable('day_sessions', (r) async {
      final remote = DaySession(
        id: r['id'],
        startedAt: _dt(r['started_at'])!,
        endedAt: _dt(r['ended_at']),
        goalMl: r['goal_ml'],
        updatedAt: _dt(r['updated_at'])!,
        deleted: r['deleted'],
        dirty: false,
      );
      final local = await (db.select(db.daySessions)..where((s) => s.id.equals(remote.id))).getSingleOrNull();
      if (local == null || remote.updatedAt.isAfter(local.updatedAt)) {
        await db.into(db.daySessions).insertOnConflictUpdate(remote);
      }
    });
    await _pullTable('entries', (r) async {
      final remote = Entry(
        id: r['id'],
        sessionId: r['session_id'],
        amountMl: r['amount_ml'],
        loggedAt: _dt(r['logged_at'])!,
        updatedAt: _dt(r['updated_at'])!,
        deleted: r['deleted'],
        dirty: false,
      );
      final local = await (db.select(db.entries)..where((e) => e.id.equals(remote.id))).getSingleOrNull();
      if (local == null || remote.updatedAt.isAfter(local.updatedAt)) {
        await db.into(db.entries).insertOnConflictUpdate(remote);
      }
    });
    await _pullTable('settings', (r) async {
      final remote = Setting(key: r['key'], value: r['value'], updatedAt: _dt(r['updated_at'])!, dirty: false);
      final local = await (db.select(db.settings)..where((s) => s.key.equals(remote.key))).getSingleOrNull();
      if (local == null || remote.updatedAt.isAfter(local.updatedAt)) {
        await db.into(db.settings).insertOnConflictUpdate(remote);
      }
    });
  }

  Future<void> _pullTable(String table, Future<void> Function(Map<String, dynamic>) apply) async {
    final cursorKey = 'local.sync_cursor.$table';
    final saved = (await db.getSettings())[cursorKey];
    // ponytail: re-read the last minute each time, so a row committed slightly out of
    // order by a concurrent write isn't skipped. Exact cursors need a server sequence.
    var since = saved == null ? null : DateTime.parse(saved).subtract(const Duration(minutes: 1)).toIso8601String();
    var cursor = saved;
    while (true) {
      final rows = await (since == null
              ? sb.from(table).select()
              : sb.from(table).select().gt('server_updated_at', since))
          .order('server_updated_at')
          .limit(500);
      for (final r in rows) {
        await apply(r);
      }
      if (rows.isEmpty) break;
      cursor = rows.last['server_updated_at'] as String;
      since = cursor;
      if (rows.length < 500) break;
    }
    if (cursor != null && cursor != saved) {
      await db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: cursorKey, value: cursor, dirty: const Value(false)));
    }
  }

  void _subscribe() {
    if (_channel != null) return;
    final channel = sb.channel('sync');
    for (final table in const ['day_sessions', 'entries', 'settings']) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => schedule(const Duration(milliseconds: 500)),
      );
    }
    _channel = channel..subscribe();
  }

  void _unsubscribe() {
    if (_channel case final c?) sb.removeChannel(c);
    _channel = null;
  }
}
