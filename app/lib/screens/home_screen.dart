import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/common.dart';
import 'dashboard_screen.dart';
import 'deals_screen.dart';
import 'expenses_screen.dart';
import 'parties_screen.dart';
import 'stock_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    // Tabs are rebuilt when opened, so they always show fresh data after
    // changes made elsewhere (a deal changes balances, stock and profit).
    final body = switch (_tab) {
      0 => const DashboardScreen(),
      1 => const PartiesScreen(),
      2 => const DealsScreen(),
      3 => const StockScreen(),
      _ => const ExpensesScreen(),
    };
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Khulasa'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Khata'),
          NavigationDestination(
              icon: Icon(Icons.swap_horiz_outlined), selectedIcon: Icon(Icons.swap_horiz), label: 'Sauday'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Stock'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Kharchay'),
        ],
      ),
    );
  }
}

/// App bar menu with the signed-in account and sign out.
class AccountMenuButton extends StatelessWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.account_circle_outlined),
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text(auth.currentUser?.email ?? '')),
        const PopupMenuItem(value: 'out', child: Text('Sign out karein')),
      ],
      onSelected: (v) async {
        if (v != 'out') return;
        if (await confirm(context, title: 'Sign out karna hai?', action: 'Sign out')) {
          await auth.signOut();
        }
      },
    );
  }
}
