import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../util/format.dart';

enum _Range {
  thisMonth('Is mahine'),
  lastMonth('Pichle mahine'),
  thisYear('Is saal'),
  custom('Apni tareekhein');

  const _Range(this.label);
  final String label;
}

/// The Munafa screen. Profit = sales − cost of the cloth sold + commission − costs.
/// Unsold stock is not a loss; it is valued in the Stock tab.
class ProfitScreen extends StatefulWidget {
  const ProfitScreen({super.key});

  @override
  State<ProfitScreen> createState() => _ProfitScreenState();
}

class _ProfitScreenState extends State<ProfitScreen> {
  final _view = GlobalKey<AsyncViewState<ProfitReport>>();
  _Range _range = _Range.thisMonth;
  late DateTimeRange _dates = _datesFor(_Range.thisMonth);

  static DateTimeRange _datesFor(_Range r) {
    final now = DateTime.now();
    return switch (r) {
      _Range.thisMonth => DateTimeRange(start: DateTime(now.year, now.month), end: now),
      _Range.lastMonth => DateTimeRange(
          start: DateTime(now.year, now.month - 1), end: DateTime(now.year, now.month).subtract(const Duration(days: 1))),
      _Range.thisYear => DateTimeRange(start: DateTime(now.year), end: now),
      _Range.custom => DateTimeRange(start: DateTime(now.year, now.month), end: now),
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
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repo.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Munafa')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                for (final r in _Range.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(r.label), selected: _range == r, onSelected: (_) => _pick(r)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('${formatDate(_dates.start)} – ${formatDate(_dates.end)}'),
          ),
          Expanded(
            child: AsyncView<ProfitReport>(
              key: _view,
              load: () => repo.profit(_dates.start, _dates.end),
              builder: (context, r, reload) => RefreshIndicator(
                onRefresh: reload,
                child: ListView(
                  children: [
                    Card(
                      margin: const EdgeInsets.all(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(r.netProfit >= 0 ? 'Khalis munafa' : 'Khalis nuqsan'),
                            Text(
                              money(r.netProfit),
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    color: r.netProfit >= 0 ? AppColors.receive : AppColors.pay,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SectionTitle('Khareed o farokht'),
                    InfoRow('Farokht', money(r.salesAmount)),
                    InfoRow('Beche gaye maal ki laagat', '− ${money(r.costOfGoodsSold)}'),
                    if (r.saleCosts != 0) InfoRow('Farokht par mere kharchay', '− ${money(r.saleCosts)}'),
                    _total(context, 'Maal ka munafa', r.tradingProfit),
                    const SectionTitle('Commission'),
                    InfoRow('Commission ki kamai', money(r.commissionIncome)),
                    if (r.commissionCosts != 0) InfoRow('Commission saudon par mere kharchay', '− ${money(r.commissionCosts)}'),
                    const SectionTitle('Deegar'),
                    InfoRow('Kharchay', '− ${money(r.expenses)}'),
                    if (r.stockLosses != 0) InfoRow('Stock ka nuqsan', '− ${money(r.stockLosses)}'),
                    _total(context, 'Khalis munafa', r.netProfit),
                    if (r.hasEstimates)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Kuch maal khareed darj hone se pehle bik gaya, is liye us ki laagat andaza hai. '
                          'Sahi munafay ke liye baqi khareed darj karein.',
                          style: TextStyle(color: AppColors.pay),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _total(BuildContext context, String label, num value) => InfoRow(
        label,
        '${value < 0 ? '− ' : ''}${money(value)}',
        valueStyle: TextStyle(fontWeight: FontWeight.w700, color: value < 0 ? AppColors.pay : null),
      );
}
