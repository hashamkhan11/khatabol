import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/ledger_repository.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'ui/common.dart';
import 'ui/theme.dart';
import 'l10n/lang.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadLang();
  await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseKey);
  runApp(KhataBolApp(client: Supabase.instance.client));
}

class KhataBolApp extends StatelessWidget {
  const KhataBolApp({super.key, required this.client});

  final SupabaseClient client;

  @override
  Widget build(BuildContext context) {
    return Repo(
      repository: LedgerRepository(client),
      child: ValueListenableBuilder<AppLang>(
        valueListenable: appLang,
        builder: (context, lang, _) => MaterialApp(
          title: 'KhataBol',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          // A new key rebuilds every screen, so each one picks up the new wording.
          // Data comes from the repository cache, so nothing reloads.
          builder: (context, child) => KeyedSubtree(key: ValueKey(lang), child: child!),
          home: _AuthGate(auth: client.auth),
        ),
      ),
    );
  }
}

/// Shows the login screen or the app, following the Supabase session.
class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.auth});

  final GoTrueClient auth;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) => auth.currentSession == null ? const LoginScreen() : const HomeScreen(),
    );
  }
}
