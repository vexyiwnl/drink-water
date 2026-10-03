import 'package:drift/native.dart';
import 'package:drinkwater/data/db.dart';
import 'package:drinkwater/data/session_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('withTime keeps edits on the right side of midnight and out of the future', () {
    final now = DateTime(2026, 10, 3, 2, 0);
    // 01:00 today -> 23:30 means last night, not tonight.
    expect(withTime(DateTime(2026, 10, 3, 1, 0), 23, 30, now), DateTime(2026, 10, 2, 23, 30));
    // 23:00 last night -> 00:30 means just after midnight.
    expect(withTime(DateTime(2026, 10, 2, 23, 0), 0, 30, now), DateTime(2026, 10, 3, 0, 30));
    // Same-day nudge.
    expect(withTime(DateTime(2026, 10, 3, 1, 0), 1, 15, now), DateTime(2026, 10, 3, 1, 15));
  });

  test('30h nudge', () {
    final start = DateTime(2026, 10, 1, 8);
    expect(shouldSuggestEnding(start, start.add(const Duration(hours: 29))), isFalse);
    expect(shouldSuggestEnding(start, start.add(const Duration(hours: 31))), isTrue);
  });

  test('parseAmounts', () {
    expect(parseAmounts(' 150, 250,500 '), [150, 250, 500]);
    expect(parseAmounts(''), isNull);
    expect(parseAmounts('100, abc'), isNull);
    expect(parseAmounts('0'), isNull);
    expect(parseAmounts('1,2,3,4,5,6,7'), isNull);
  });

  group('stats', () {
    final now = DateTime(2026, 10, 10, 1, 30); // 1:30 am, late-night session from the 9th still open
    DateTime d(int day) => DateTime(2026, 10, day);
    // (startedAt, open, goal, total)
    final days = groupByDate([
      (DateTime(2026, 10, 3, 8), false, 3000, 3000), // met
      (DateTime(2026, 10, 4, 8), false, 3000, 1000), // missed
      (DateTime(2026, 10, 5, 8), false, 3000, 3200), // met
      (DateTime(2026, 10, 6, 8), false, 3000, 1500), // two sessions same date: 1500 + 1600 = met
      (DateTime(2026, 10, 6, 15), false, 3000, 1600),
      (DateTime(2026, 10, 7, 9), false, 3000, 3000), // met
      (DateTime(2026, 10, 8, 9), false, 2500, 2600), // met
      (DateTime(2026, 10, 9, 9), true, 3000, 1200), // open, not met yet
    ]);

    test('groupByDate sums same-date sessions', () {
      expect(days[d(6)]!.total, 3100);
      expect(days[d(6)]!.met, isTrue);
      expect(days.length, 7);
    });

    test('current streak skips the in-progress day and an empty today', () {
      expect(currentStreak(days, now), 4); // 5,6,7,8
      // Once the open day hits its goal it counts too.
      final done = {...days, d(9): const DayStat(3000, 3000, true)};
      expect(currentStreak(done, now), 5);
      // A closed, missed day breaks it.
      final missed = {...days, d(9): const DayStat(1200, 3000, false)};
      expect(currentStreak(missed, now), 0);
      // A gap breaks it.
      expect(currentStreak(days, DateTime(2026, 10, 12)), 0);
    });

    test('longest streak', () {
      expect(longestStreak(days), 4);
      expect(longestStreak({}), 0);
    });

    test('7-day average ignores the open day and empty days', () {
      // 4..9 within range, 9 is open -> (1000 + 3200 + 3100 + 3000 + 2600) / 5
      expect(averageOver(days, now), 2580);
      expect(averageOver({}, now), isNull);
    });
  });

  group('reminder slots', () {
    final last = DateTime(2026, 10, 3, 10, 0);
    const hour = Duration(hours: 1);

    test('dueSlot: nothing until one interval passes, then the newest due slot', () {
      expect(dueSlot(last, hour, DateTime(2026, 10, 3, 10, 59)), isNull);
      expect(dueSlot(last, hour, DateTime(2026, 10, 3, 11, 0)), DateTime(2026, 10, 3, 11, 0));
      expect(dueSlot(last, hour, DateTime(2026, 10, 3, 13, 20)), DateTime(2026, 10, 3, 13, 0));
    });

    test('upcomingSlots: strictly future, on the grid, within the horizon', () {
      final now = DateTime(2026, 10, 3, 12, 30);
      final slots = upcomingSlots(last, hour, now, horizon: const Duration(hours: 3));
      expect(slots, [DateTime(2026, 10, 3, 13), DateTime(2026, 10, 3, 14), DateTime(2026, 10, 3, 15)]);
      // Just logged: first reminder one interval later.
      expect(upcomingSlots(now, hour, now, horizon: const Duration(hours: 2)).first, DateTime(2026, 10, 3, 13, 30));
      // 30 min interval over 24h = 48 alarms max.
      expect(upcomingSlots(now, const Duration(minutes: 30), now).length, 47);
    });

    test('remindersActive', () {
      expect(remindersActive(enabled: true, total: 1000, goal: 3000, stopAtGoal: true), isTrue);
      expect(remindersActive(enabled: true, total: 3000, goal: 3000, stopAtGoal: true), isFalse);
      expect(remindersActive(enabled: true, total: 3000, goal: 3000, stopAtGoal: false), isTrue);
      expect(remindersActive(enabled: false, total: 0, goal: 3000, stopAtGoal: true), isFalse);
    });
  });

  group('reconcileOpenSessions (two devices each started a day offline)', () {
    late AppDb db;
    setUp(() => db = AppDb(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<String> open(DateTime start) async =>
        (await db.into(db.daySessions).insertReturning(DaySessionsCompanion.insert(startedAt: start, goalMl: 3000))).id;
    Future<void> log(String session, int ml) =>
        db.into(db.entries).insert(EntriesCompanion.insert(sessionId: session, amountMl: ml, loggedAt: DateTime(2026, 10, 3, 12)));

    test('same day: newer open day merges into the older one', () async {
      final pc = await open(DateTime(2026, 10, 3, 9));
      final phone = await open(DateTime(2026, 10, 3, 11));
      await log(pc, 500);
      await log(phone, 250);

      expect(await db.reconcileOpenSessions(), isTrue);
      expect((await db.getOpenSession())!.id, pc);
      expect((await db.watchEntries(pc).first).map((e) => e.amountMl).toSet(), {500, 250});
      final merged = await (db.select(db.daySessions)..where((s) => s.id.equals(phone))).getSingle();
      expect(merged.deleted, isTrue);
      expect(merged.dirty, isTrue); // so the deletion syncs
    });

    test('forgotten day: a stale open day is closed where the new one started', () async {
      final old = await open(DateTime(2026, 10, 1, 9));
      final today = await open(DateTime(2026, 10, 3, 9));

      expect(await db.reconcileOpenSessions(), isTrue);
      expect((await db.getOpenSession())!.id, today);
      final closed = await (db.select(db.daySessions)..where((s) => s.id.equals(old))).getSingle();
      expect(closed.endedAt, DateTime(2026, 10, 3, 9));
      expect(closed.deleted, isFalse);
    });

    test('one open day: nothing to do', () async {
      await open(DateTime(2026, 10, 3, 9));
      expect(await db.reconcileOpenSessions(), isFalse);
    });
  });

  test('local edits notify sync; reconcile does not (no sync loop)', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    var calls = 0;
    db.onLocalChange = () => calls++;
    await db.addWater(250, 3000);
    expect(calls, greaterThan(0));
    calls = 0;
    await db.reconcileOpenSessions();
    expect(calls, 0);
  });

  test('session totals exclude deleted entries', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final a = await db.addWater(250, 3000);
    await db.addWater(500, 3000);
    await db.updateEntry(a, deleted: true);
    await db.startDay(3000); // empty session -> total 0
    final rows = await db.watchSessionTotals().first;
    // Both sessions start in the same second here, so order is unspecified.
    expect(rows.map((r) => r.$2), unorderedEquals([500, 0]));
  });

  test('logging auto-starts a day; ending closes it; new goal applies to open day', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await db.watchOpenSession().first, isNull);
    final id = await db.addWater(250, 3000);
    final s = (await db.watchOpenSession().first)!;
    expect(s.goalMl, 3000);
    await db.addWater(500, 3000);
    expect((await db.watchEntries(s.id).first).map((e) => e.amountMl).toSet(), {250, 500});

    await db.updateEntry(id, deleted: true); // undo / delete
    expect((await db.watchEntries(s.id).first).single.amountMl, 500);

    await db.saveSettings({'goal_ml': '2500', 'quick_adds': '200'});
    expect((await db.watchOpenSession().first)!.goalMl, 2500);
    expect(await db.watchSettings().first, {'goal_ml': '2500', 'quick_adds': '200'});

    await db.endDay();
    expect(await db.watchOpenSession().first, isNull);

    final newId = await db.startDay(2500);
    expect((await db.watchOpenSession().first)!.id, newId);
    expect(await db.watchEntries(newId).first, isEmpty);
  });
}
