import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/session_logic.dart';
import '../providers.dart';
import '../theme.dart';

void showDayDetails(BuildContext context, DateTime date) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: card,
      constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      builder: (_) => _DayDetails(date),
    );

class _DayDetails extends ConsumerWidget {
  const _DayDetails(this.date);

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = [
      for (final (s, total) in ref.watch(sessionTotalsProvider).value ?? const <(DaySession, int)>[])
        if (dateOnly(s.startedAt) == date) (s, total),
    ];
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
      Text(DateFormat('EEEE d MMMM yyyy').format(date),
          style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w600)),
      for (final (s, total) in sessions) _SessionDetails(s, total),
    ]);
  }
}

class _SessionDetails extends ConsumerWidget {
  const _SessionDetails(this.session, this.total);

  final DaySession session;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium!.copyWith(color: textMuted);
    final entries = (ref.watch(entriesProvider(session.id)).value ?? const <Entry>[]).reversed;
    final end = session.endedAt;
    final fmt = DateFormat('EEE d MMM, HH:mm');

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$total / ${session.goalMl} ml · ${(total * 100 / session.goalMl).round()}%',
            style: text.headlineSmall!.copyWith(color: aqua, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Started ${fmt.format(session.startedAt)}', style: muted),
        Text(
          end == null
              ? 'In progress'
              : 'Ended ${fmt.format(end)} · ${formatDuration(end.difference(session.startedAt))}',
          style: muted,
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty) Text('No entries.', style: muted),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Icon(Icons.water_drop, color: aqua, size: 18),
              const SizedBox(width: 10),
              SizedBox(width: 110, child: Text(DateFormat('EEE HH:mm').format(e.loggedAt), style: muted)),
              Text('${e.amountMl} ml'),
            ]),
          ),
      ]),
    );
  }
}
