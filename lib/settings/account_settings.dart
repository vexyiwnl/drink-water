import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/sync.dart';
import '../providers.dart';
import '../reminders/push.dart';
import '../theme.dart';

class AccountSettings extends ConsumerWidget {
  const AccountSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authProvider); // rebuild on sign-in/out
    final auth = Supabase.instance.client.auth;
    final user = auth.currentUser;
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium!.copyWith(color: textMuted);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Account & sync', style: text.titleMedium!.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (user == null) ...[
            Text('Sign in to keep your phone and PC in sync. Everything works offline without it.', style: muted),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => showDialog<void>(context: context, builder: (_) => const _SignInDialog()),
              icon: const Icon(Icons.login),
              label: const Text('Sign in'),
            ),
          ] else ...[
            Text('Signed in as ${user.email}'),
            const SizedBox(height: 4),
            ValueListenableBuilder(
              valueListenable: syncService.state,
              builder: (context, s, _) => Text(_status(s), style: muted, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: syncService.syncNow,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: TextButton(onPressed: signOut, child: const Text('Sign out'))),
            ]),
            const SizedBox(height: 8),
            Text('Signing out keeps your data on this device; it just stops syncing.',
                style: text.bodySmall!.copyWith(color: textMuted)),
          ],
        ]),
      ),
    );
  }

  static String _status(SyncState s) {
    if (s.busy) return 'Syncing…';
    if (s.error != null) return 'Last sync failed, will retry: ${s.error}';
    if (s.lastSync == null) return 'Not synced yet';
    return 'Synced at ${DateFormat.Hm().format(s.lastSync!)}';
  }
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog();

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: _email.text.trim(), password: _password.text);
      if (mounted) Navigator.pop(context);
    } on AuthException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = "Couldn't reach the server. Check your connection.";
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Sign in'),
        content: SizedBox(
          width: 360,
          child: AutofillGroup(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: _email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(labelText: 'Password', errorText: _error, errorMaxLines: 3),
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sign in'),
          ),
        ],
      );
}
