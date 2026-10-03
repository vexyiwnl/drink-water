import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/sync.dart';
import '../providers.dart';
import '../supabase_config.dart';
import 'reminders.dart';

/// Android only. When data changes on another device, the `sync-ping` Edge Function
/// sends a silent FCM message here; even with the app closed we then sync and
/// re-plan the reminder alarms, so logging on the PC resets the phone's countdown.
Future<void> startPush() async {
  if (!Platform.isAndroid) return;
  try {
    await Firebase.initializeApp(); // reads android/app/google-services.json
  } catch (e) {
    debugPrint('Push disabled (no Firebase config?): $e');
    return;
  }
  FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
  FirebaseMessaging.onMessage.listen((_) => syncService.schedule(Duration.zero));
  Supabase.instance.client.auth.onAuthStateChange.listen((s) {
    if (s.session != null) _registerDevice();
  });
  FirebaseMessaging.instance.onTokenRefresh.listen((_) => _registerDevice());
}

Future<void> _registerDevice() async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await Supabase.instance.client
        .from('devices')
        .upsert({'token': token, 'updated_at': DateTime.now().toUtc().toIso8601String()});
  } catch (e) {
    debugPrint('Device registration failed: $e'); // retried on next start/sign-in
  }
}

/// Stop pushes to this phone, then sign out.
Future<void> signOut() async {
  if (Platform.isAndroid && Firebase.apps.isNotEmpty) {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await Supabase.instance.client.from('devices').delete().eq('token', token);
    } catch (e) {
      debugPrint('Device unregister failed: $e');
    }
  }
  await Supabase.instance.client.auth.signOut();
}

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession?.isExpired ?? false) await auth.refreshSession();
  await SyncService(appDb, Supabase.instance.client).syncNow();
  await initNotifications();
  await rescheduleAndroid();
}
