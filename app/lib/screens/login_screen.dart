import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/common.dart';
import '../ui/theme.dart';
import '../l10n/lang.dart';

/// Email and password sign-in. There is no sign-up: the account is created
/// by the owner in the Supabase dashboard, so strangers cannot register.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      showError(context, tr('Email aur password likhein', 'Enter email and password'));
      return;
    }
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final k = KColors.of(context);
    return Scaffold(
      backgroundColor: k.ink,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 48, 28, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: k.onInk.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(Icons.menu_book_rounded, size: 30, color: k.onInk),
                          ),
                          const SizedBox(height: 28),
                          Text('KhataBol',
                              style: theme.textTheme.displaySmall
                                  ?.copyWith(color: k.onInk, fontWeight: FontWeight.w800, letterSpacing: -1)),
                          const SizedBox(height: 6),
                          Text(tr('Apna khata, apni zubaan', 'Your ledger, your language'),
                              style: theme.textTheme.titleMedium?.copyWith(color: k.onInk.withValues(alpha: 0.72))),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.fromLTRB(24, 32, 24, 24 + MediaQuery.paddingOf(context).bottom),
                        decoration: BoxDecoration(
                          color: k.paper,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: AutofillGroup(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Text(tr('Sign in karein', 'Sign in'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(tr('Apne account ki email aur password likhein.', 'Enter your account email and password.'), style: TextStyle(color: k.muted)),
                                  const SizedBox(height: 24),
                                  TextField(
                                    controller: _email,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [AutofillHints.email],
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                      prefixIcon: Icon(Icons.mail_outline_rounded),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextField(
                                    controller: _password,
                                    obscureText: _hidePassword,
                                    autofillHints: const [AutofillHints.password],
                                    onSubmitted: (_) => _signIn(),
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                                      suffixIcon: IconButton(
                                        icon: Icon(_hidePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                                        onPressed: () => setState(() => _hidePassword = !_hidePassword),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  FilledButton(
                                    onPressed: _busy ? null : _signIn,
                                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                                    child: _busy
                                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                                        : const Text('Sign in'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
