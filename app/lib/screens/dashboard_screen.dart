import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/khata_text.dart';
import '../ui/common.dart';
import '../util/format.dart';
import 'home_screen.dart';
import 'party_screen.dart';
import 'profit_screen.dart';

/// The Khulasa tab, the screen the owner opens most: what is owed both ways,
/// this month's profit, stock in hand, the biggest balances and the latest
/// activity. Most entries are expected to arrive from the WhatsApp bot, so this
/// screen is for reading; every number taps through to its detail.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _Summary {
  _Summary(this.balances, this.profit, this.stock, this.recent);
  final List<PartyBalance> balances;
  final ProfitReport profit;
  final List<StockRow> stock;
  final List<KhataLine> recent;
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _view = GlobalKey<AsyncViewState<_Summary>>();

  Future<_Summary> _load() async {
    final repo = Repo.of(context);
    final now = DateTime.now();
    final results = await Future.wait([
      repo.partyBalances(),
      repo.profit(DateTime(now.year, now.month), now),
      repo.stockSummary(),
      repo.recentLines(limit: 10),
    ]);
    return _Summary(
      results[0] as List<PartyBalance>,
      results[1] as ProfitReport,
      results[2] as List<StockRow>,
      results[3] as List<KhataLine>,
    );
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Khulasa'), actions: const [AccountMenuButton()]),
      body: AsyncView<_Summary>(
        key: _view,
        load: _load,
        builder: (context, s, reload) {
          final active = s.balances.where((p) => !p.archived).toList();
          final debtors = active.where((p) => p.balance > 0).toList()..sort((a, b) => b.balance.compareTo(a.balance));
          final creditors = active.where((p) => p.balance < 0).toList()..sort((a, b) => a.balance.compareTo(b.balance));
          final toReceive = debtors.fold<num>(0, (t, p) => t + p.balance);
          final toPay = creditors.fold<num>(0, (t, p) => t - p.balance);
          final stock = s.stock.where((r) => !r.archived);
          final stockKg = stock.fold<num>(0, (t, r) => t + r.weightKg);
          final stockValue = stock.fold<num>(0, (t, r) => t + r.stockValue);
          final profit = s.profit.netProfit;
          final text = Theme.of(context).textTheme;

          Widget partyTile(PartyBalance p) => ListTile(
                dense: true,
                title: Text(p.name),
                subtitle: Text([p.type.label, ?p.city].join(' · ')),
                trailing: BalanceText(p.balance),
                onTap: () => _open(PartyScreen(partyId: p.id)),
              );

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                TotalsRow(toReceive: toReceive, toPay: toPay),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: InkWell(
                            onTap: () => _open(const ProfitScreen()),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Is mahine ka munafa'),
                                  Text(
                                    '${profit < 0 ? '− ' : ''}${money(profit)}',
                                    style: text.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: profit < 0 ? AppColors.pay : AppColors.receive,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Stock haath mein'),
                                Text(kg(stockKg), style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                                Text(money(stockValue), style: text.bodySmall),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (debtors.isNotEmpty) ...[
                  const SectionTitle('Sab se zyada lena'),
                  for (final p in debtors.take(5)) partyTile(p),
                ],
                if (creditors.isNotEmpty) ...[
                  const SectionTitle('Sab se zyada dena'),
                  for (final p in creditors.take(5)) partyTile(p),
                ],
                const SectionTitle('Taaza hisaab'),
                if (s.recent.isEmpty)
                  const EmptyState(icon: Icons.menu_book_outlined, message: 'Abhi koi entry nahi.')
                else
                  for (final l in s.recent)
                    ListTile(
                      dense: true,
                      title: Text(l.partyName ?? lineTitle(l)),
                      subtitle: Text('${lineTitle(l)} · ${formatShortDate(l.date)}'),
                      trailing: Text(signedAmount(l.amount),
                          style: TextStyle(
                            color: l.amount >= 0 ? AppColors.receive : AppColors.pay,
                            fontWeight: FontWeight.w600,
                          )),
                      onTap: l.partyId == null ? null : () => _open(PartyScreen(partyId: l.partyId!)),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}
