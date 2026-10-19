import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/khata_text.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../util/format.dart';
import 'home_screen.dart';
import 'party_screen.dart';
import 'profit_screen.dart';
import '../l10n/lang.dart';

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
  Future<_Summary> _load() async {
    final repo = Repo.of(context);
    final now = DateTime.now();
    final results = await Future.wait([
      repo.partyBalances(),
      repo.profit(DateTime(now.year, now.month), now),
      repo.stockSummary(),
      repo.recentLines(limit: 8),
    ]);
    return _Summary(
      results[0] as List<PartyBalance>,
      results[1] as ProfitReport,
      results[2] as List<StockRow>,
      results[3] as List<KhataLine>,
    );
  }

  void _open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(longDayDate(DateTime.now()),
                style: TextStyle(fontSize: 13, color: k.muted, fontWeight: FontWeight.w600)),
            Text(tr('Khulasa', 'Summary')),
          ],
        ),
        actions: const [AccountMenuButton()],
      ),
      body: AsyncView<_Summary>(
        cacheKey: 'dashboard',
        load: _load,
        skeleton: const SkeletonList(header: true, rows: 4),
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

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _Hero(toReceive: toReceive, toPay: toPay, debtors: debtors.length, creditors: creditors.length),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Tile(
                          icon: profit < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                          iconColor: k.forBalance(profit),
                          label: profit < 0 ? tr('Is mahine ka nuqsan', 'Loss this month') : tr('Is mahine ka munafa', 'Profit this month'),
                          value: Amount(profit, color: k.forBalance(profit), size: 19, weight: FontWeight.w800),
                          note: tr('Tafseel', 'Details'),
                          onTap: () => _open(const ProfitScreen()),
                        ),
                        const SizedBox(width: 12),
                        _Tile(
                          icon: Icons.inventory_2_outlined,
                          iconColor: Theme.of(context).colorScheme.primary,
                          label: tr('Stock haath mein', 'Stock in hand'),
                          value: Text(kg(stockKg),
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w800, fontFeatures: tabular, color: k.text)),
                          note: money(stockValue),
                        ),
                      ],
                    ),
                  ),
                ),
                if (debtors.isNotEmpty)
                  Section(
                    title: tr('Sab se zyada lena', 'Most to receive'),
                    children: [
                      for (final p in debtors.take(5)) PartyTile(party: p, onTap: () => _open(PartyScreen(partyId: p.id))),
                    ],
                  ),
                if (creditors.isNotEmpty)
                  Section(
                    title: tr('Sab se zyada dena', 'Most to pay'),
                    children: [
                      for (final p in creditors.take(5))
                        PartyTile(party: p, onTap: () => _open(PartyScreen(partyId: p.id))),
                    ],
                  ),
                if (s.recent.isEmpty)
                  EmptyState(icon: Icons.menu_book_outlined, message: tr('Abhi koi entry nahi.', 'No entries yet.'))
                else
                  Section(
                    title: tr('Taaza hisaab', 'Latest entries'),
                    children: [
                      for (final l in s.recent)
                        ListTile(
                          leading: LineIcon(kind: l.isReversal ? 'reversal' : l.kind, amount: l.amount),
                          title: Text(l.partyName ?? lineTitle(l), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${dayLabel(l.date)} · ${lineTitle(l)}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Amount(l.amount, signed: true, color: k.forBalance(l.amount), size: 15),
                          onTap: l.partyId == null ? null : () => _open(PartyScreen(partyId: l.partyId!)),
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The one bold block in the app: everything owed both ways, as two numbers,
/// a bar showing their weight against each other, and the net in plain words.
class _Hero extends StatelessWidget {
  const _Hero({required this.toReceive, required this.toPay, required this.debtors, required this.creditors});

  final num toReceive;
  final num toPay;
  final int debtors;
  final int creditors;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    final net = toReceive - toPay;
    final total = toReceive + toPay;
    final onInkMuted = k.onInk.withValues(alpha: 0.72);

    Widget side(String label, num amount, int parties, Color dot, CrossAxisAlignment align) => Column(
          crossAxisAlignment: align,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: onInkMuted, fontWeight: FontWeight.w600, fontSize: 13.5)),
            ]),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Amount(amount, color: k.onInk, size: 26, weight: FontWeight.w800),
            ),
            Text('$parties ${parties == 1 ? tr('party', 'party') : tr('parties', 'parties')}', style: TextStyle(color: onInkMuted, fontSize: 12.5)),
          ],
        );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(color: k.ink, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: side(tr('Kul lena', 'To receive'), toReceive, debtors, k.lenaOnInk, CrossAxisAlignment.start)),
              const SizedBox(width: 16),
              Expanded(child: side(tr('Kul dena', 'To pay'), toPay, creditors, k.denaOnInk, CrossAxisAlignment.end)),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: total == 0
                  ? ColoredBox(color: k.onInk.withValues(alpha: 0.18))
                  : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (toReceive > 0) Expanded(flex: _flex(toReceive, total), child: ColoredBox(color: k.lenaOnInk)),
                      if (toReceive > 0 && toPay > 0) const SizedBox(width: 3),
                      if (toPay > 0) Expanded(flex: _flex(toPay, total), child: ColoredBox(color: k.denaOnInk)),
                    ]),
            ),
          ),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              style: TextStyle(color: onInkMuted, fontSize: 14.5, height: 1.3),
              children: net == 0
                  ? [TextSpan(text: tr('Kul mila kar hisaab barabar hai', 'Overall, everything is settled'))]
                  : [
                      TextSpan(text: tr('Kul mila kar ', 'Overall, ')),
                      TextSpan(
                        text: money(net),
                        style: TextStyle(color: k.onInk, fontWeight: FontWeight.w800, fontFeatures: tabular),
                      ),
                      TextSpan(text: net > 0 ? tr(' lene hain', ' to receive') : tr(' dene hain', ' to pay')),
                    ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bar widths out of 1000, never so thin a side disappears.
  static int _flex(num part, num total) => (part / total * 1000).round().clamp(20, 1000);
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.note,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Widget value;
  final String note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    return Expanded(
      child: Material(
        color: k.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, size: 20, color: iconColor),
                  const Spacer(),
                  if (onTap != null) Icon(Icons.chevron_right_rounded, size: 20, color: k.muted),
                ]),
                const SizedBox(height: 10),
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 2),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
                Text(note, style: TextStyle(fontSize: 12.5, color: k.muted, fontFeatures: tabular)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
