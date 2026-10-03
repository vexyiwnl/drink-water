import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers.dart';
import '../reminders/reminders.dart';
import '../theme.dart';

const _androidPerms = [
  (Permission.notification, 'Notifications', 'Needed to show reminders'),
  (Permission.scheduleExactAlarm, 'Exact alarms', 'Reminders arrive on time, not up to ~10 min late'),
  (Permission.ignoreBatteryOptimizations, 'Unrestricted battery', 'Stops Android delaying reminders in standby'),
];

class ReminderSettings extends ConsumerStatefulWidget {
  const ReminderSettings({super.key, required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends ConsumerState<ReminderSettings> {
  // Permissions are changed in system screens, so re-check when we come back.
  late final _lifecycle = AppLifecycleListener(onResume: _refresh);
  Map<Permission, bool> _granted = {};
  bool? _startup;

  @override
  void initState() {
    super.initState();
    _lifecycle; // create it
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (Platform.isAndroid) {
      final granted = {for (final (p, _, _) in _androidPerms) p: await p.isGranted};
      if (mounted) setState(() => _granted = granted);
    }
    if (Platform.isWindows) {
      final on = await launchAtStartup.isEnabled();
      if (mounted) setState(() => _startup = on);
    }
  }

  void _set(String key, Object value) => ref.read(dbProvider).saveSettings({key: '$value'});

  Widget _switch(String title, String? subtitle, bool value, ValueChanged<bool>? onChanged) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: value,
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall!.copyWith(color: textMuted);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Reminders', style: text.titleMedium!.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          _switch('Reminders on this device', 'Only while a day is in progress',
              s.remindersOn, (v) => _set('local.reminders_on', v)),
          const SizedBox(height: 8),
          Text('Remind me every', style: muted),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [for (final m in const [30, 45, 60, 90]) ButtonSegment(value: m, label: Text('$m min'))],
            selected: {s.intervalMin},
            showSelectedIcon: false,
            onSelectionChanged: (v) => _set('interval_min', v.first),
          ),
          const SizedBox(height: 8),
          _switch('Stop when goal is reached', null, s.stopAtGoal, (v) => _set('stop_at_goal', v)),
          if (Platform.isWindows) ...[
            _switch('Flash taskbar icon', 'Until you switch to the app', s.winFlash, (v) => _set('local.win_flash', v)),
            _switch('Windows notification', 'Also show a toast', s.winToast, (v) => _set('local.win_toast', v)),
            _switch(
              'Launch on startup',
              'Starts hidden in the system tray',
              _startup ?? false,
              _startup == null
                  ? null
                  : (v) async {
                      v ? await launchAtStartup.enable() : await launchAtStartup.disable();
                      await _refresh();
                    },
            ),
            Text('Closing the window keeps the app running in the tray. Quit from the tray icon menu.',
                style: muted),
          ],
          if (Platform.isAndroid) ...[
            const Divider(height: 28),
            Text('Permissions', style: text.titleSmall),
            for (final (perm, title, why) in _androidPerms)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _granted[perm] ?? false ? Icons.check_circle : Icons.error_outline,
                  color: _granted[perm] ?? false ? aqua : Theme.of(context).colorScheme.error,
                ),
                title: Text(title),
                subtitle: Text(why),
                trailing: _granted[perm] ?? true
                    ? null
                    : TextButton(
                        onPressed: () async {
                          await perm.request();
                          await _refresh();
                          requestReschedule();
                        },
                        child: const Text('Allow'),
                      ),
              ),
            Text(
              'Vivo, Xiaomi, Oppo and Samsung phones can still stop background apps. If reminders go '
              'missing, allow Drink Water to run in the background (autostart) in the phone\'s battery settings.',
              style: muted,
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: sendTestReminder,
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(Platform.isWindows ? 'Send test reminder (in 5 s)' : 'Send test reminder'),
          ),
        ]),
      ),
    );
  }
}
