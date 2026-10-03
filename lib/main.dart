import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'data/sync.dart';
import 'providers.dart';
import 'reminders/push.dart';
import 'reminders/reminders.dart';
import 'supabase_config.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Offline-safe: restores the saved session locally; refreshing it happens in the background.
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  syncService = SyncService(appDb, Supabase.instance.client)..start();
  // --minimized is passed by "launch on startup": start in the Windows tray.
  await startReminders(startHidden: args.contains('--minimized'));
  await startPush();
  runApp(const ProviderScope(child: App()));
}
