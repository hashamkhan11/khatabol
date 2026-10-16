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
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _StatCard(
                          label: 'Is mahine ka munafa',
                          value: '${profit < 0 ? '− ' : ''}${money(profit)}',
                          color: profit < 0 ? AppColors.pay : AppColors.receive,
                          note: 'Tafseel dekhein ›',
                          onTap: () => _open(const ProfitScreen()),
                        ),
                        _StatCard(label: 'Stock haath mein', value: kg(stockKg), note: money(stockValue)),
                      ],
                    ),
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

/// A small dashboard number card, styled like [TotalsRow].
class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.note, this.color, this.onTap});

  final String label;
  final String value;
  final String? note;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.labelMedium),
                const SizedBox(height: 4),
                Text(value, style: text.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w600)),
                if (note != null) Text(note!, style: text.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
