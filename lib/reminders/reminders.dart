import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/db.dart';
import '../data/session_logic.dart';
import '../providers.dart';
import 'windows_shell.dart';

final notifications = FlutterLocalNotificationsPlugin();

const _logAction = 'log250';
const _androidDetails = AndroidNotificationDetails(
  'reminders',
  'Water reminders',
  channelDescription: 'Reminders to drink water while a day is in progress',
  icon: 'ic_stat_water',
  importance: Importance.high,
  priority: Priority.high,
  category: AndroidNotificationCategory.reminder,
  actions: [AndroidNotificationAction(_logAction, 'Log 250 ml', cancelNotification: true)],
);

class ReminderPlan {
  const ReminderPlan(this.last, this.interval, this.total, this.goal);

  final DateTime last;
  final Duration interval;
  final int total;
  final int goal;

  String get title => 'Time for some water 💧';
  String get body => '$total of $goal ml so far today.';
}

/// What reminders should do right now, or null if they shouldn't run.
Future<ReminderPlan?> loadPlan(AppDb db) async {
  final s = AppSettings(await db.getSettings());
  final session = await db.getOpenSession();
  if (session == null) return null;
  final entries = await db.watchEntries(session.id).first;
  final total = entries.fold(0, (sum, e) => sum + e.amountMl);
  if (!remindersActive(enabled: s.remindersOn, total: total, goal: session.goalMl, stopAtGoal: s.stopAtGoal)) {
    return null;
  }
  final last = [session.startedAt, for (final e in entries) e.loggedAt].reduce((a, b) => a.isAfter(b) ? a : b);
  return ReminderPlan(last, Duration(minutes: s.intervalMin), total, session.goalMl);
}

Future<void> initNotifications() => notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_water'),
        windows: WindowsInitializationSettings(
          appName: 'Drink Water',
          appUserModelId: 'Vexy.DrinkWater',
          guid: '6f1d7c2e-4b8a-4f0e-9c3d-2a5b7e8f9d10',
        ),
      ),
      onDidReceiveNotificationResponse: onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: onNotificationResponse,
    );

/// "Log 250 ml" on Android. May run in a background isolate with the app closed.
@pragma('vm:entry-point')
Future<void> onNotificationResponse(NotificationResponse r) async {
  if (r.actionId != _logAction) {
    if (Platform.isWindows) await WindowsShell.instance.show(); // toast clicked
    return;
  }
  DartPluginRegistrant.ensureInitialized();
  await appDb.addWater(250, AppSettings(await appDb.getSettings()).goalMl);
  await rescheduleAndroid();
}

/// Starts reminders for this platform. Call once from main().
Future<void> startReminders({required bool startHidden}) async {
  await initNotifications();
  if (Platform.isWindows) return WindowsShell.instance.start(hidden: startHidden);
  if (!Platform.isAndroid) return;

  unawaited(Permission.notification.request()); // Android 13+ prompt; no-op once decided
  appDb.tableUpdates().listen((_) => requestReschedule());
  AppLifecycleListener(onResume: requestReschedule); // e.g. exact-alarm permission just granted
  requestReschedule();
}

Timer? _debounce;
Future<void> _queue = Future.value();

/// Re-plans Android's scheduled alarms. Debounced and serialised, since a log
/// touches several tables at once.
void requestReschedule() {
  if (!Platform.isAndroid) return;
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 300), () => _queue = _queue.then((_) => rescheduleAndroid()));
}

/// Android alarms survive the app being closed, so schedule the next 24h of
/// reminders up front and replace them whenever anything changes.
Future<void> rescheduleAndroid() async {
  try {
    final plan = await loadPlan(appDb);
    await notifications.cancelAll();
    if (plan == null) return;
    final android = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final exact = await android?.canScheduleExactNotifications() ?? false;
    for (final (i, t) in upcomingSlots(plan.last, plan.interval, DateTime.now()).indexed) {
      await notifications.zonedSchedule(
        id: i + 1,
        scheduledDate: tz.TZDateTime.from(t, tz.UTC),
        notificationDetails: const NotificationDetails(android: _androidDetails),
        androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
        title: plan.title,
        body: plan.body,
      );
    }
  } catch (e, st) {
    debugPrint('Reminder scheduling failed: $e\n$st');
  }
}

/// Settings → "Send test reminder".
Future<void> sendTestReminder() async {
  final plan = await loadPlan(appDb) ?? ReminderPlan(DateTime(0), Duration.zero, 0, 0);
  if (Platform.isWindows) {
    // Give time to switch away, since the taskbar only flashes for an unfocused window.
    await Future<void>.delayed(const Duration(seconds: 5));
    return WindowsShell.instance.remind(plan);
  }
  await notifications.show(
    id: 999,
    title: plan.title,
    body: plan.goal == 0 ? 'Test reminder — reminders run while a day is in progress.' : plan.body,
    notificationDetails: const NotificationDetails(android: _androidDetails),
  );
}
