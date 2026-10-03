import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/session_logic.dart';
import '../providers.dart';
import '../theme.dart';
import 'amount_dialog.dart';
import 'progress_ring.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(openSessionProvider).value;
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final entries = ref.watch(todayEntriesProvider).value ?? const <Entry>[];
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final goal = session?.goalMl ?? settings.goalMl;
    final total = entries.fold(0, (sum, e) => sum + e.amountMl);

    void log(int ml) => _log(context, ref, ml, settings.goalMl);
    void endDay() => _confirmEndDay(context, ref, total, goal);

    final top = [
      _Header(session: session, now: now, onEnd: endDay, onStart: () => ref.read(dbProvider).startDay(settings.goalMl)),
      if (session != null && shouldSuggestEnding(session.startedAt, now)) ...[
        const SizedBox(height: 12),
        _StaleBanner(open: now.difference(session.startedAt), onEnd: endDay),
      ],
      const SizedBox(height: 24),
      Center(child: ProgressRing(total: total, goal: goal)),
      const SizedBox(height: 28),
      Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: [
        for (final ml in settings.quickAdds)
          FilledButton.icon(onPressed: () => log(ml), icon: const Icon(Icons.water_drop), label: Text('$ml ml')),
        OutlinedButton.icon(
          onPressed: () async {
            final r = await showAmountDialog(context, title: 'Custom amount');
            if (r != null) log(r.$1);
          },
          icon: const Icon(Icons.edit),
          label: const Text('Custom'),
        ),
      ]),
    ];
    final list = _EntryList(entries: entries, sessionStart: session?.startedAt);

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: ListView(padding: const EdgeInsets.all(28), children: top)),
          Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(0, 28, 28, 28), children: [list])),
        ]);
      }
      return ListView(padding: const EdgeInsets.all(20), children: [...top, const SizedBox(height: 28), list]);
    });
  }

  Future<void> _log(BuildContext context, WidgetRef ref, int ml, int goal) async {
    final db = ref.read(dbProvider);
    HapticFeedback.lightImpact(); // no-op on Windows
    final id = await db.addWater(ml, goal);
    if (!context.mounted) return;
    _snack(context, 'Logged $ml ml', () => db.updateEntry(id, deleted: true));
  }

  Future<void> _confirmEndDay(BuildContext context, WidgetRef ref, int total, int goal) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('End this day?'),
        content: Text('You drank $total of $goal ml (${(total * 100 / goal).round()}%).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, 'end'), child: const Text('End day')),
          FilledButton(onPressed: () => Navigator.pop(c, 'new'), child: const Text('End & start new')),
        ],
      ),
    );
    final db = ref.read(dbProvider);
    if (choice == 'end') await db.endDay();
    if (choice == 'new') await db.startDay(ref.read(settingsProvider).value?.goalMl ?? goal);
  }
}

void _snack(BuildContext context, String msg, VoidCallback undo) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(msg), action: SnackBarAction(label: 'Undo', onPressed: undo)));

class _Header extends StatelessWidget {
  const _Header({required this.session, required this.now, required this.onEnd, required this.onStart});

  final DaySession? session;
  final DateTime now;
  final VoidCallback onEnd;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = session;
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s == null ? 'No day in progress' : 'Today', style: text.headlineSmall!.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            s == null
                ? 'Log water or press Start day'
                : 'Started ${DateFormat('EEE d MMM, HH:mm').format(s.startedAt)} · ${formatDuration(now.difference(s.startedAt))} ago',
            style: text.bodyMedium!.copyWith(color: textMuted),
          ),
        ]),
      ),
      const SizedBox(width: 12),
      s == null
          ? FilledButton.tonalIcon(onPressed: onStart, icon: const Icon(Icons.wb_sunny_outlined), label: const Text('Start day'))
          : OutlinedButton.icon(onPressed: onEnd, icon: const Icon(Icons.nightlight_round), label: const Text('End day')),
    ]);
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.open, required this.onEnd});

  final Duration open;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => Card(
        color: cardHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            const Icon(Icons.schedule, color: aqua),
            const SizedBox(width: 12),
            Expanded(child: Text('This day has been open for ${open.inHours} hours. Time to start a new one?')),
            TextButton(onPressed: onEnd, child: const Text('End day')),
          ]),
        ),
      );
}

class _EntryList extends ConsumerWidget {
  const _EntryList({required this.entries, required this.sessionStart});

  final List<Entry> entries;
  final DateTime? sessionStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final db = ref.read(dbProvider);
    final start = sessionStart;

    String time(DateTime t) => DateFormat(
            start != null && DateUtils.isSameDay(t, start) ? 'HH:mm' : 'EEE HH:mm')
        .format(t);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text("Today's entries", style: text.titleMedium!.copyWith(fontWeight: FontWeight.w600)),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Nothing logged yet.', style: text.bodyMedium!.copyWith(color: textMuted)),
            ),
          for (final e in entries)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: aqua.withValues(alpha: 0.14),
                child: const Icon(Icons.water_drop, color: aqua, size: 20),
              ),
              title: Text('${e.amountMl} ml'),
              subtitle: Text(time(e.loggedAt)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final r = await showAmountDialog(context, title: 'Edit entry', initialMl: e.amountMl, time: e.loggedAt);
                    if (r != null) await db.updateEntry(e.id, ml: r.$1, loggedAt: r.$2);
                  },
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await db.updateEntry(e.id, deleted: true);
                    if (context.mounted) {
                      _snack(context, 'Deleted ${e.amountMl} ml', () => db.updateEntry(e.id, deleted: false));
                    }
                  },
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
