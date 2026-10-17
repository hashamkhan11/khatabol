import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../util/format.dart';
import '../l10n/lang.dart';

enum _Range {
  thisMonth('Is mahine', 'This month'),
  lastMonth('Pichle mahine', 'Last month'),
  thisYear('Is saal', 'This year'),
  custom('Apni tareekhein', 'Pick dates');

  const _Range(this._ru, this._en);
  final String _ru, _en;
  String get label => tr(_ru, _en);
}

/// The Munafa screen. Profit = sales − cost of the cloth sold + commission − costs.
/// Unsold stock is not a loss; it is valued in the Stock tab.
class ProfitScreen extends StatefulWidget {
  const ProfitScreen({super.key});

  @override
  State<ProfitScreen> createState() => _ProfitScreenState();
}

class _ProfitScreenState extends State<ProfitScreen> {
  _Range _range = _Range.thisMonth;
  late DateTimeRange _dates = _datesFor(_Range.thisMonth);

  static DateTimeRange _datesFor(_Range r) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (r) {
      _Range.thisMonth => DateTimeRange(start: DateTime(now.year, now.month), end: today),
      _Range.lastMonth => DateTimeRange(
          start: DateTime(now.year, now.month - 1), end: DateTime(now.year, now.month).subtract(const Duration(days: 1))),
      _Range.thisYear => DateTimeRange(start: DateTime(now.year), end: today),
      _Range.custom => DateTimeRange(start: DateTime(now.year, now.month), end: today),
    };
  }

  Future<void> _pick(_Range r) async {
    var dates = _datesFor(r);
    if (r == _Range.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDateRange: _dates,
      );
      if (picked == null) return;
      dates = picked;
    }
    setState(() {
      _range = r;
      _dates = dates;
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repo.of(context);
    final k = KColors.of(context);
    final key = 'profit:${_dates.start.toIso8601String()}:${_dates.end.toIso8601String()}';
    return Scaffold(
      appBar: AppBar(title: Text(tr('Munafa', 'Profit'))),
      body: Column(
        children: [
          const SizedBox(height: 4),
          FilterChips<_Range>(
            options: [for (final r in _Range.values) (r, r.label)],
            selected: _range,
            onSelected: _pick,
          ),
          Expanded(
            child: AsyncView<ProfitReport>(
              cacheKey: key,
              skeleton: const SkeletonList(header: true, rows: 5),
              load: () => repo.profit(_dates.start, _dates.end),
              builder: (context, r, reload) {
                final net = r.netProfit;
                return RefreshIndicator(
                  onRefresh: reload,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: k.surface, borderRadius: BorderRadius.circular(24)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                RowIcon(
                                  net >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                                  color: net >= 0 ? k.lena : k.dena,
                                  background: net >= 0 ? k.lenaSoft : k.denaSoft,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(net >= 0 ? tr('Khalis munafa', 'Net profit') : tr('Khalis nuqsan', 'Net loss'),
                                          style: Theme.of(context).textTheme.titleSmall),
                                      Text('${formatDate(_dates.start)} – ${formatDate(_dates.end)}',
                                          style: TextStyle(color: k.muted, fontSize: 13, fontFeatures: tabular)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Amount(net.abs(), size: 36, weight: FontWeight.w800, color: net >= 0 ? k.lena : k.dena),
                            ),
                          ],
                        ),
                      ),
                      Section(
                        title: tr('Khareed o farokht', 'Trading'),
                        dividerIndent: 16,
                        children: [
                          InfoRow(tr('Farokht', 'Sales'), money(r.salesAmount)),
                          InfoRow(tr('Beche gaye maal ki laagat', 'Cost of goods sold'), '− ${money(r.costOfGoodsSold)}'),
                          if (r.saleCosts != 0) InfoRow(tr('Farokht par mere kharchay', 'My costs on sales'), '− ${money(r.saleCosts)}'),
                          _total(k, tr('Maal ka munafa', 'Trading profit'), r.tradingProfit),
                        ],
                      ),
                      Section(
                        title: 'Commission',
                        dividerIndent: 16,
                        children: [
                          InfoRow(tr('Commission ki kamai', 'Commission earned'), money(r.commissionIncome)),
                          if (r.commissionCosts != 0)
                            InfoRow(tr('Commission saudon par mere kharchay', 'My costs on commission deals'), '− ${money(r.commissionCosts)}'),
                        ],
                      ),
                      Section(
                        title: tr('Deegar', 'Other'),
                        dividerIndent: 16,
                        children: [
                          InfoRow(tr('Kharchay', 'Expenses'), '− ${money(r.expenses)}'),
                          if (r.stockLosses != 0) InfoRow(tr('Stock ka nuqsan', 'Stock losses'), '− ${money(r.stockLosses)}'),
                          _total(k, tr('Khalis munafa', 'Net profit'), net),
                        ],
                      ),
                      if (r.hasEstimates)
                        FormHint(
                          tr(
                              'Kuch maal khareed darj hone se pehle bika ya stock se nikla, is liye us ki laagat andaza hai. '
                                  'Sahi munafay ke liye baqi khareed darj karein.',
                              'Some goods were sold or taken out before their purchase was entered, so their cost is estimated. '
                                  'Enter the missing purchases for exact profit.'),
                          warn: true,
                          margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _total(KColors k, String label, num value) => InfoRow(
        label,
        '${value < 0 ? '− ' : ''}${money(value.abs())}',
        valueStyle: TextStyle(fontWeight: FontWeight.w800, color: value < 0 ? k.dena : k.lena),
      );
}
