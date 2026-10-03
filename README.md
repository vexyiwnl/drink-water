# Drink Water

Personal water tracker for Windows + Android (Flutter). Offline-first, with optional Supabase sync between devices.

## Status

| Milestone | Scope | State |
|---|---|---|
| 1 | Local app: logging, goal, manual day reset | ✅ |
| 2 | Calendar + stats | ✅ |
| 3 | Reminders (Android notifications, Windows flash/tray/toast) | ✅ |
| 4 | Supabase sign-in + sync | ✅ |
| 5 | Polish (icon, splash, haptics) + Firebase push for a closed phone app | ✅ (push needs the setup below) |

## Prerequisites

- Flutter stable (`C:\dev\flutter\bin` on PATH) — `flutter doctor` must be clean
- Visual Studio 2022+ with **Desktop development with C++** (Windows builds)
- Android Studio with SDK, Platform-Tools and Command-line Tools; `flutter doctor --android-licenses`
- Windows **Developer Mode** on (plugins need symlinks)
- Phone: Developer options → USB debugging (Vivo/Xiaomi: also allow "Install via USB")

## Run during development

```powershell
cd drink_water                   # the folder containing pubspec.yaml
flutter pub get
dart run build_runner build      # regenerate lib/data/db.g.dart after changing tables
flutter run -d windows           # or: flutter devices, then flutter run -d <phone id>
flutter test
```

## Build and install

**Windows**

```powershell
flutter build windows
```

Output: `build\windows\x64\runner\Release\`. Copy the **whole folder** (the exe needs the DLLs and `data\` next to it), e.g. to `C:\Apps\DrinkWater`, and pin `drinkwater.exe` to Start/taskbar.

**Android**

```powershell
flutter build apk --release
flutter install -d <phone id>     # or copy build\app\outputs\flutter-apk\app-release.apk to the phone and open it
```

The release APK is signed with the debug key — fine for your own phone, not for the Play Store.

## Where data lives

- Windows: `%APPDATA%\com.vexy\Drink Water\drinkwater.sqlite`. The folder comes from `CompanyName`/`ProductName` in `windows/runner/Runner.rc`; changing either moves it (copy the old file across).
- Android: app-private storage (removed on uninstall)

## How a "day" works

- A day session starts when you press **Start day**, or automatically when you log water with no day open.
- It ends only when you press **End day** (with confirmation). "End & start new" does both at once.
- Each session stores start/end time and the goal at the time; the total is summed from its entries.
- A session counts towards the calendar date it **started** on.
- After 30 hours open, the home screen suggests ending it.
- Changing the goal in Settings also updates the day in progress.

## History and stats

- Calendar colours: < 50%, 50–99%, 100%+ of that day's goal. Tap a coloured day for its sessions and entries.
- **Current streak**: consecutive days that met their goal, ending today. Today (or a day still in progress) doesn't break it until it's ended under goal; a day with no session does.
- **7-day average**: average of finished days in the last 7 calendar days (the open day is left out).
- Chart: last 7 or 30 days with the current goal as a dashed line.

## Reminders

Reminders fire every *interval* (30/45/60/90 min, synced setting) after your last drink, or after the day started if you haven't logged yet. Logging resets the countdown. They only run while a day is in progress, and stop once the goal is reached (toggle). "Reminders on this device" turns them off per device.

**Android**

- The next 24 h of reminders are scheduled as system alarms, so they fire with the app closed or the phone locked, and survive reboots. Any change (log, edit, end day, settings) replaces them.
- Notifications have a **Log 250 ml** button that logs in the background without opening the app.
- Settings → Reminders → Permissions shows and fixes: notifications (Android 13+), exact alarms (otherwise reminders may be ~10 min late), unrestricted battery.
- Vivo/Xiaomi/Oppo/Samsung add their own background killers. On Vivo: Settings → Battery → Background power consumption management → Drink Water → allow (wording varies by OriginOS version). Use **Send test reminder** to check.

**Windows**

- Closing the window hides it to the system tray; reminders keep running. Click the tray icon to reopen, right-click → Quit to exit.
- On a reminder the taskbar icon flashes until you switch to the app. If the app was hidden in the tray it's restored *minimised* (without stealing focus) so there's a taskbar button to flash.
- Optional Windows toast notification (Settings toggle).
- **Launch on startup** (Settings) starts the app hidden in the tray (--minimized). It registers the exe's current path, so set it after copying the app to its final folder.
- Only one copy runs at a time; launching it again brings the existing window back.

**Limitations**

- Windows reminders need the app running (normal or in the tray). It picks up phone logs within seconds (realtime) or 5 min.
- A closed phone app learns about PC changes through Firebase push (below). Without that setup it catches up when opened.

## Sync (Supabase)

One-time setup (done for this project; repeat for a new one):

1. Create a Supabase project (free tier), then **SQL Editor** → run `supabase/schema.sql` (tables, row-level security, last-write-wins trigger, realtime).
2. **Authentication → Users → Add user** (tick *Auto Confirm User*); **Sign In / Providers → Allow new users to sign up: off**.
3. Put the project URL and **publishable** key in `lib/supabase_config.dart` (never the secret key).

How it works:

- Sign-in is optional (Settings → Account & sync). Signed out, the app is purely local.
- Every row has a UUID, `updated_at` and `dirty` flag. Local edits mark rows dirty; sync pushes dirty rows (upsert), then pulls rows changed on the server since the last pull (`server_updated_at` cursor). Newer `updated_at` wins; the server enforces the same rule for pushes.
- Deletes are soft (`deleted`), so they sync too.
- Sync runs ~2 s after a local edit, instantly on a realtime change from the other device, on app resume, and every 5 min. Offline failures just retry later.
- If both devices started a day before syncing: a newer open day within 30 h of the older one is merged into it; otherwise the older (forgotten) one is closed when the new one started.
- Signing out keeps local data and stops syncing. Per-device settings (`local.*` keys: reminder toggles, flash/toast) never sync.
- Free Supabase projects pause after 7 days with no requests; daily use keeps it awake, and **Restore** in the dashboard wakes it.

## Push to a closed phone app (Firebase)

When anything changes on the server, a Database Webhook calls the `sync-ping` Edge Function, which sends a silent FCM message to your phones. The phone app wakes in the background, syncs and re-plans its reminder alarms. Windows doesn't need it (it's either running with realtime, or closed).

Setup is one-time; until `android/app/google-services.json` exists the app builds and runs with push off. `firebase_core` is vendored in `third_party/` without its Windows platform, which would otherwise download a 918 MB C++ SDK into every clean Windows build.

1. Firebase console: create a project, add an Android app `com.vexy.drinkwater`, download `google-services.json` into `android/app/`.
2. Firebase → Project settings → Service accounts → **Generate new private key** (JSON).
3. Supabase SQL Editor: run `supabase/push.sql`.
4. Supabase → Edge Functions → **Deploy a new function** → via editor, name `sync-ping`, paste `supabase/functions/sync-ping/index.ts`, deploy; then in its settings turn **Verify JWT** off.
5. Supabase → Edge Functions → **Secrets**: `FCM_SERVICE_ACCOUNT` = the whole service-account JSON, `WEBHOOK_SECRET` = a long random string.
6. Supabase → Database → **Webhooks**: one per table (`entries`, `day_sessions`, `settings`), events Insert + Update, type *Supabase Edge Functions* → `sync-ping`, HTTP header `x-webhook-secret` = the same random string.
7. Rebuild and install the Android app, sign in once (registers the phone in `devices`).

## Code layout

```
lib/
  main.dart, app.dart        entry point, responsive shell (bottom bar / side rail at >= 720 px)
  theme.dart                 colours and component styles
  providers.dart             Riverpod providers + AppSettings
  data/db.dart               drift tables and queries (sync-ready: uuid ids, updated_at, deleted, dirty)
  data/session_logic.dart    pure logic (time edits, 30h nudge, amount parsing, stats, reminder slots)
  data/sync.dart             Supabase push/pull/realtime sync
  supabase_config.dart       project URL + publishable key
  home/                      home screen, progress ring, amount dialog
  history/                   calendar, stat tiles, intake chart (fl_chart), day details sheet
  reminders/reminders.dart   reminder plan, Android alarms + notification action, test reminder
  reminders/windows_shell.dart  tray, close-to-tray, taskbar flash, toast, launch on startup
  reminders/push.dart        Android FCM: device registration, background sync on ping
  settings/                  settings screen, reminder settings/permissions, account & sync
supabase/schema.sql          database schema to run in the Supabase SQL editor
supabase/push.sql            devices table for push
supabase/functions/sync-ping Edge Function that sends the FCM sync ping
tool/make_icon_test.dart     renders assets/icon/*.png; then `dart run flutter_launcher_icons`
third_party/firebase_core     firebase_core 4.15.0 minus its Windows platform
test/logic_test.dart
```
