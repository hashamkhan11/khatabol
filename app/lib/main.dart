import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/ledger_repository.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'ui/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      child: MaterialApp(
        title: 'KhataBol',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: _AuthGate(auth: client.auth),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C), brightness: brightness),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      );
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
