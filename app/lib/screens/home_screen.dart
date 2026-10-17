import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/ledger_repository.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'dashboard_screen.dart';
import 'deals_screen.dart';
import 'expenses_screen.dart';
import 'parties_screen.dart';
import 'stock_screen.dart';

/// The five tabs. Each tab stays alive while another is shown, so switching
/// is instant; a tab that missed a change refreshes when it is shown again.
/// Changes made elsewhere (the WhatsApp bot) arrive live while the app is open,
/// and everything refreshes when the app comes back to the front.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final LedgerRepository _repo;
  int _tab = 0;

  static const _tabs = [
    DashboardScreen(),
    PartiesScreen(),
    DealsScreen(),
    StockScreen(),
    ExpensesScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _repo = Repo.of(context);
    _repo.startLive();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _repo.stopLive();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Live updates pause while the phone sleeps; catch up on the way back.
    if (state == AppLifecycleState.resumed) _repo.markChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            TickerMode(enabled: i == _tab, child: HeroMode(enabled: i == _tab, child: _tabs[i])),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: KColors.of(context).line))),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.space_dashboard_outlined),
                selectedIcon: Icon(Icons.space_dashboard_rounded),
                label: 'Khulasa'),
            NavigationDestination(
                icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: 'Khata'),
            NavigationDestination(
                icon: Icon(Icons.swap_horiz_rounded), selectedIcon: Icon(Icons.swap_horiz_rounded), label: 'Sauday'),
            NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2_rounded), label: 'Stock'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Kharchay'),
          ],
        ),
      ),
    );
  }
}

/// App bar button with the signed-in account and sign out.
class AccountMenuButton extends StatelessWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    final email = auth.currentUser?.email ?? '';
    final k = KColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        tooltip: 'Account',
        offset: const Offset(0, 48),
        icon: CircleAvatar(
          radius: 17,
          backgroundColor: k.ink,
          child: Text(email.isEmpty ? '?' : email[0].toUpperCase(),
              style: TextStyle(color: k.onInk, fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        itemBuilder: (_) => [
          PopupMenuItem(enabled: false, child: Text(email, style: TextStyle(color: k.muted, fontSize: 14))),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'out',
            child: Row(children: [Icon(Icons.logout_rounded, size: 20), SizedBox(width: 12), Text('Sign out karein')]),
          ),
        ],
        onSelected: (v) async {
          if (v != 'out') return;
          final repo = Repo.of(context);
          if (await confirm(context, title: 'Sign out karna hai?', action: 'Sign out')) {
            await repo.stopLive();
            // The next person to sign in on this phone must not see this khata.
            repo.clearCache();
            await auth.signOut();
          }
        },
      ),
    );
  }
}
