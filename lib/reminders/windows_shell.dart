import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart'
    show ContextMenuTrigger, ImageAsset, Menu, MenuItem, MenuItemClickedEvent, MenuItemType, TrayIcon,
        TrayIconClickedEvent, TrayIconDoubleClickedEvent;
import 'package:window_manager/window_manager.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

import '../data/session_logic.dart';
import '../providers.dart';
import 'reminders.dart';

/// Windows: close-to-tray, tray menu, launch on startup, and in-process reminders
/// (taskbar flash + optional toast) that run while the app is open or in the tray.
class WindowsShell with WindowListener {
  WindowsShell._();
  static final instance = WindowsShell._();

  TrayIcon? _tray;
  DateTime? _firedFor;

  Future<void> start({required bool hidden}) async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(title: 'Drink Water', minimumSize: Size(380, 560)),
      () async {
        if (!hidden) await show();
      },
    );
    _setUpTray();
    launchAtStartup.setup(appName: 'Drink Water', appPath: Platform.resolvedExecutable, args: ['--minimized']);

    // A 30s poll instead of one long Timer: survives sleep/hibernate and picks up
    // logs from anywhere (incl. other devices after sync) without extra wiring.
    Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    unawaited(_tick());
  }

  void _setUpTray() {
    final tray = TrayIcon.create();
    final menu = Menu.create();
    if (tray == null || menu == null) return;
    tray.icon = ImageAsset.fromAsset('assets/tray.ico');
    tray.setTooltip('Drink Water');
    for (final (label, action) in [('Open Drink Water', show), (null, null), ('Quit', quit)]) {
      if (label == null) {
        menu.addSeparator();
        continue;
      }
      final item = MenuItem.createWithLabelAndType(label, MenuItemType.normal);
      item?.addListener((e) {
        if (e is MenuItemClickedEvent) action!();
      });
      menu.addItem(item);
    }
    tray.setContextMenu(menu);
    tray.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
    tray.addListener((e) {
      if (e is TrayIconClickedEvent || e is TrayIconDoubleClickedEvent) show();
    });
    tray.setVisible(true);
    _tray = tray;
  }

  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> quit() async {
    _tray?.setVisible(false);
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() => windowManager.hide();

  Future<void> _tick() async {
    final plan = await loadPlan(appDb);
    if (plan == null) return;
    final slot = dueSlot(plan.last, plan.interval, DateTime.now());
    if (slot == null || slot == _firedFor) return;
    _firedFor = slot;
    await remind(plan);
  }

  Future<void> remind(ReminderPlan plan) async {
    final s = AppSettings(await appDb.getSettings());
    if (s.winFlash && !await windowManager.isFocused()) {
      // A window hidden in the tray has no taskbar button to flash: bring it back
      // minimised, without stealing focus.
      if (!await windowManager.isVisible()) {
        await windowManager.show(inactive: true);
        await windowManager.minimize();
      }
      // Default mode stops by itself once the window is focused. Don't reset it from
      // onWindowFocus: stopping a flash re-sends activation -> focus -> endless loop.
      await WindowsTaskbar.setFlashTaskbarAppIcon();
    }
    if (s.winToast) {
      await notifications.show(
        id: 1,
        title: plan.title,
        body: plan.goal == 0 ? 'Test reminder.' : plan.body,
        notificationDetails: const NotificationDetails(windows: WindowsNotificationDetails()),
      );
    }
  }
}
