import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/ledger_repository.dart';
import '../ui/common.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import 'account_sheet.dart';
import 'dashboard_screen.dart';
import 'deals_screen.dart';
import 'expenses_screen.dart';
import 'parties_screen.dart';
import 'stock_screen.dart';
import '../l10n/lang.dart';

/// The five tabs. Each tab stays alive while another is shown, so switching
/// is instant; a tab refreshes quietly each time it is shown again.
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
          destinations: [
            NavigationDestination(
                icon: const Icon(KIcons.summary), selectedIcon: const Icon(KIcons.summaryOn), label: tr('Khulasa', 'Summary')),
            NavigationDestination(
                icon: const Icon(KIcons.parties), selectedIcon: const Icon(KIcons.partiesOn), label: tr('Khata', 'Parties')),
            NavigationDestination(
                icon: const Icon(KIcons.deals), selectedIcon: const Icon(KIcons.dealsOn), label: tr('Sauday', 'Deals')),
            const NavigationDestination(icon: Icon(KIcons.stock), selectedIcon: Icon(KIcons.stockOn), label: 'Stock'),
            NavigationDestination(
                icon: const Icon(KIcons.expenses), selectedIcon: const Icon(KIcons.expensesOn), label: tr('Kharchay', 'Expenses')),
          ],
        ),
      ),
    );
  }
}

/// App bar button with the signed-in account; opens the account sheet.
class AccountMenuButton extends StatelessWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Tooltip(
        message: tr('Account', 'Account'),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => showAccountSheet(context),
          child: AccountAvatar(email: email, size: 38),
        ),
      ),
    );
  }
}
