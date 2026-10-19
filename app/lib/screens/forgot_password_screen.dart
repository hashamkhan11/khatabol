import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/lang.dart';
import '../ui/common.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import 'account_sheet.dart';

/// Resets a forgotten password in two steps: a code is emailed to the
/// account, then the code and a new password are entered here.
/// Checking the code signs the person in, so the app opens straight after.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.email = ''});

  final String email;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _sent = false;
  bool _busy = false;

  /// The code has been accepted; a retry after a failed save must not check it again.
  bool _verified = false;
  String? _error;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!email.contains('@')) return setState(() => _error = tr('Account ki email likhein', 'Enter the account email'));
    await _run(() async {
      await _auth.resetPasswordForEmail(email);
      if (!mounted) return;
      setState(() => _sent = true);
      showDone(context, tr('Code $email par bhej diya', 'Code sent to $email'));
    });
  }

  Future<void> _save() async {
    final code = _code.text.trim();
    if (!_verified && !RegExp(r'^\d{6,8}$').hasMatch(code)) {
      return setState(() => _error = tr('Email mein aaya hua code likhein', 'Enter the code from the email'));
    }
    final problem = passwordProblem(_password.text, _again.text);
    if (problem != null) return setState(() => _error = problem);
    await _run(() async {
      if (!_verified) {
        await _auth.verifyOTP(type: OtpType.recovery, email: _email.text.trim(), token: code);
        _verified = true;
      }
      await _auth.updateUser(UserAttributes(password: _password.text));
      if (!mounted) return;
      // Signed in now; the login screen underneath has already become the app.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((r) => r.isFirst);
      messenger.showSnackBar(SnackBar(content: Text(tr('Naya password set ho gaya', 'New password set'))));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final k = KColors.of(context);
    return Scaffold(
      backgroundColor: k.ink,
      appBar: AppBar(
        backgroundColor: k.ink,
        foregroundColor: k.onInk,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          tooltip: tr('Wapas', 'Back'),
          icon: const Icon(KIcons.back),
          onPressed: _sent && !_verified ? () => setState(() => _sent = false) : () => Navigator.maybePop(context),
        ),
      ),
      body: SafeArea(
        top: false,
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
                      padding: const EdgeInsets.fromLTRB(28, 4, 28, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: k.onInk.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: k.onInk.withValues(alpha: 0.14)),
                            ),
                            child: Icon(_sent ? KIcons.emailSent : KIcons.key, color: k.onInk, size: 28),
                          ),
                          const SizedBox(height: 22),
                          Text(tr('Password bhool gaye?', 'Forgot password?'),
                              style: theme.textTheme.headlineMedium
                                  ?.copyWith(color: k.onInk, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                          const SizedBox(height: 6),
                          Text(
                            _sent
                                ? tr('${_email.text.trim()} par code bheja hai. Woh code aur naya password likhein.',
                                    'We sent a code to ${_email.text.trim()}. Enter it with a new password.')
                                : tr('Account ki email likhein. Us par ek code aayega.',
                                    'Enter the account email. A code will be sent to it.'),
                            style: theme.textTheme.bodyLarge?.copyWith(color: k.onInk.withValues(alpha: 0.72)),
                          ),
                          const SizedBox(height: 18),
                          _Steps(step: _sent ? 2 : 1),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + MediaQuery.paddingOf(context).bottom),
                        decoration: BoxDecoration(
                          color: k.paper,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: _sent ? _codeStep(k) : _emailStep(),
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

  Widget _emailStep() {
    return Column(
      key: const ValueKey('email'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _email,
          autofocus: _email.text.isEmpty,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _sendCode(),
          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(KIcons.email, size: 20)),
        ),
        if (_error != null) FormHint(_error!, warn: true, margin: const EdgeInsets.only(top: 12)),
        const SizedBox(height: 24),
        _BusyButton(busy: _busy, label: tr('Code bhejein', 'Send code'), icon: KIcons.send, onPressed: _sendCode),
      ],
    );
  }

  Widget _codeStep(KColors k) {
    return AutofillGroup(
      key: const ValueKey('code'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_verified) ...[
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 6, fontFeatures: tabular),
              decoration: InputDecoration(
                labelText: tr('Email wala code', 'Code from the email'),
                prefixIcon: const Icon(KIcons.shield, size: 20),
              ),
            ),
            const SizedBox(height: 14),
          ],
          PasswordField(controller: _password, label: tr('Naya password', 'New password')),
          const SizedBox(height: 14),
          PasswordField(controller: _again, label: tr('Dobara likhein', 'Type it again'), onSubmitted: (_) => _save()),
          if (_error != null) FormHint(_error!, warn: true, margin: const EdgeInsets.only(top: 12)),
          const SizedBox(height: 24),
          _BusyButton(busy: _busy, label: tr('Password set karein', 'Set password'), icon: KIcons.check, onPressed: _save),
          if (!_verified) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _sendCode,
              child: Text(tr('Code nahi aaya? Dobara bhejein', 'No code? Send again')),
            ),
            Text(
              tr('Spam / Junk folder bhi dekh lein.', 'Check the Spam / Junk folder too.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: k.muted, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

/// "1 Email · 2 Naya password" progress on the ink header.
class _Steps extends StatelessWidget {
  const _Steps({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    Widget dot(int n, String label) {
      final on = n <= step;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? k.onInk : Colors.transparent,
            border: Border.all(color: k.onInk.withValues(alpha: on ? 1 : 0.35)),
          ),
          child: n < step
              ? Icon(KIcons.check, size: 12, color: k.ink)
              : Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: on ? k.ink : k.onInk.withValues(alpha: 0.6))),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: k.onInk.withValues(alpha: on ? 0.95 : 0.55))),
      ]);
    }

    return Row(children: [
      dot(1, 'Email'),
      Expanded(
        child: Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: k.onInk.withValues(alpha: 0.22),
        ),
      ),
      dot(2, tr('Naya password', 'New password')),
    ]);
  }
}

class _BusyButton extends StatelessWidget {
  const _BusyButton({required this.busy, required this.label, required this.icon, required this.onPressed});

  final bool busy;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
      icon: busy
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
          : Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
