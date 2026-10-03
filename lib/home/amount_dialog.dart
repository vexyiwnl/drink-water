import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/session_logic.dart';

/// Asks for an amount, plus a time when [time] is given (editing an entry).
/// Returns (ml, time) or null if cancelled.
Future<(int, DateTime?)?> showAmountDialog(BuildContext context,
        {required String title, int? initialMl, DateTime? time}) =>
    showDialog(context: context, builder: (_) => _AmountDialog(title, initialMl, time));

class _AmountDialog extends StatefulWidget {
  const _AmountDialog(this.title, this.initialMl, this.time);

  final String title;
  final int? initialMl;
  final DateTime? time;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _ctrl = TextEditingController(text: widget.initialMl?.toString() ?? '');
  late DateTime? _time = widget.time;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final ml = int.tryParse(_ctrl.text.trim());
    if (ml == null || ml < 1 || ml > 5000) {
      setState(() => _error = 'Enter 1–5000 ml');
      return;
    }
    Navigator.pop(context, (ml, _time));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_time!));
    if (t != null) setState(() => _time = withTime(_time!, t.hour, t.minute, DateTime.now()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(suffixText: 'ml', errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
          if (_time != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule),
              label: Text(DateFormat('EEE HH:mm').format(_time!)),
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Save')),
        ],
      );
}
