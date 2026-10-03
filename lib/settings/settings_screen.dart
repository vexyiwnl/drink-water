import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/session_logic.dart';
import '../providers.dart';
import 'account_settings.dart';
import 'reminder_settings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  final _goal = TextEditingController();
  final _quick = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _goal.dispose();
    _quick.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await ref
        .read(dbProvider)
        .saveSettings({'goal_ml': _goal.text, 'quick_adds': parseAmounts(_quick.text)!.join(',')});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).value;
    if (s == null) return const Center(child: CircularProgressIndicator());
    if (!_loaded) {
      _goal.text = '${s.goalMl}';
      _quick.text = s.quickAdds.join(', ');
      _loaded = true;
    }
    final text = Theme.of(context).textTheme;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Settings', style: text.headlineSmall!.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextFormField(
                    controller: _goal,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Daily goal',
                      suffixText: 'ml',
                      helperText: 'Also updates the day in progress',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 250 || n > 10000 ? 'Enter 250–10000 ml' : null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _quick,
                    decoration: const InputDecoration(
                      labelText: 'Quick-add amounts (ml)',
                      helperText: 'Comma-separated, e.g. 150, 250, 500',
                    ),
                    validator: (v) => parseAmounts(v ?? '') == null ? '1–6 amounts, each 1–5000 ml' : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _save, child: const Text('Save')),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ReminderSettings(settings: s),
          const SizedBox(height: 20),
          const AccountSettings(),
        ]),
      ),
    );
  }
}
