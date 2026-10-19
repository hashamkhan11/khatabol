import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/lang.dart';
import '../ui/common.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';

/// The account sheet: who is signed in, the language, password and sign out.
Future<void> showAccountSheet(BuildContext context) async {
  final auth = Supabase.instance.client.auth;
  final repo = Repo.of(context);
  final email = auth.currentUser?.email ?? '';
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (context) {
      final k = KColors.of(context);
      final text = Theme.of(context).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                child: Row(children: [
                  AccountAvatar(email: email, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Aap ka account', 'Your account'), style: text.labelMedium),
                        const SizedBox(height: 2),
                        Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(children: [
                  Icon(KIcons.language, size: 18, color: k.muted),
                  const SizedBox(width: 8),
                  Text(tr('Zubaan', 'Language'), style: text.labelLarge?.copyWith(color: k.muted)),
                ]),
              ),
              Segments<AppLang>(
                options: [for (final l in AppLang.values) (l, l.label)],
                selected: appLang.value,
                // The whole app redraws in the new language, which also closes this sheet.
                onChanged: setLang,
              ),
              const SizedBox(height: 16),
              SheetGroup(children: [
                ListTile(
                  leading: RowIcon(KIcons.key, size: 38, color: k.text, background: k.surface),
                  title: Text(tr('Password badlein', 'Change password')),
                  trailing: Icon(KIcons.chevronRight, size: 18, color: k.muted),
                  onTap: () => Navigator.pop(context, 'password'),
                ),
                ListTile(
                  leading: RowIcon(KIcons.signOut, size: 38, color: k.dena, background: k.denaSoft),
                  title: Text(tr('Sign out karein', 'Sign out'), style: TextStyle(color: k.dena)),
                  onTap: () => Navigator.pop(context, 'out'),
                ),
              ]),
            ],
          ),
        ),
      );
    },
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'password':
      await showChangePasswordSheet(context);
    case 'out':
      final ok = await confirm(
        context,
        title: tr('Sign out karna hai?', 'Sign out?'),
        message: tr('Dobara kholne ke liye email aur password chahiye hoga.', 'You will need the email and password to open it again.'),
        icon: KIcons.signOut,
        danger: true,
        action: 'Sign out',
      );
      if (!ok) return;
      await repo.stopLive(all: true);
      // The next person to sign in on this phone must not see this khata.
      repo.clearCache();
      await auth.signOut();
  }
}

/// The signed-in account's initial on an ink tile.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.email, this.size = 36});

  final String email;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(k.ink, Colors.white, 0.18)!, k.ink],
        ),
      ),
      child: Text(email.isEmpty ? '?' : email[0].toUpperCase(),
          style: TextStyle(color: k.onInk, fontWeight: FontWeight.w800, fontSize: size * 0.42)),
    );
  }
}

/// Sets a new password for the signed-in account.
Future<void> showChangePasswordSheet(BuildContext context) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ChangePassword(),
  );
  if (changed == true && context.mounted) showDone(context, tr('Password badal gaya', 'Password changed'));
}

class _ChangePassword extends StatefulWidget {
  const _ChangePassword();

  @override
  State<_ChangePassword> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends State<_ChangePassword> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = passwordProblem(_password.text, _again.text);
    if (problem != null) return setState(() => _error = problem);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: _password.text));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      icon: KIcons.key,
      title: tr('Naya password', 'New password'),
      message: tr('Kam az kam 8 huroof. Agli dafa isi se sign in hoga.', 'At least 8 characters. You will sign in with it next time.'),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(tr('Wapas', 'Back'))),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
              : Text(tr('Save karein', 'Save')),
        ),
      ],
      children: [
        PasswordField(controller: _password, label: tr('Naya password', 'New password'), autofocus: true),
        PasswordField(
          controller: _again,
          label: tr('Dobara likhein', 'Type it again'),
          onSubmitted: (_) => _save(),
        ),
        if (_error != null) FormHint(_error!, warn: true),
      ],
    );
  }
}

/// Why a new password cannot be used, or null when it is fine.
String? passwordProblem(String password, String again) {
  if (password.length < 8) return tr('Password kam az kam 8 huroof ka ho', 'Use at least 8 characters');
  if (password != again) return tr('Dono password ek jaise nahi', 'The two passwords do not match');
  return null;
}

/// A password input with a show / hide eye.
class PasswordField extends StatefulWidget {
  const PasswordField({super.key, required this.controller, required this.label, this.autofocus = false, this.onSubmitted});

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      obscureText: _hidden,
      autofillHints: const [AutofillHints.newPassword],
      textInputAction: widget.onSubmitted == null ? TextInputAction.next : TextInputAction.done,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(KIcons.lock, size: 20),
        suffixIcon: IconButton(
          tooltip: _hidden ? tr('Dikhayein', 'Show') : tr('Chhupayein', 'Hide'),
          icon: Icon(_hidden ? KIcons.show : KIcons.hide, size: 20),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}
