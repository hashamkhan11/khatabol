import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'deal_form_screen.dart';
import 'deal_screen.dart';
import 'home_screen.dart';
import '../l10n/lang.dart';

IconData dealIcon(DealKind kind) => switch (kind) {
      DealKind.purchase => Icons.move_to_inbox_rounded,
      DealKind.sale => Icons.local_shipping_outlined,
      DealKind.commission => Icons.handshake_outlined,
    };

/// A deal kind's icon on a soft ink badge.
class DealIcon extends StatelessWidget {
  const DealIcon(this.kind, {super.key, this.cancelled = false, this.size = 40});

  final DealKind kind;
  final bool cancelled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return RowIcon(
      dealIcon(kind),
      size: size,
      color: cancelled ? k.muted : primary,
      background: cancelled ? k.paper : primary.withValues(alpha: 0.1),
    );
  }
}

/// The Sauday tab: purchases, sales and commission deals, newest first.
class DealsScreen extends StatefulWidget {
  const DealsScreen({super.key});

  @override
  State<DealsScreen> createState() => _DealsScreenState();
}

class _DealsScreenState extends State<DealsScreen> {
  DealKind? _kind;
  bool _showCancelled = false;

  void _open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  Future<void> _newDeal() async {
    Widget option(DealKind kind, String hint) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          leading: DealIcon(kind, size: 44),
          title: Text(kind.label),
          subtitle: Text(hint),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.pop(context, kind),
        );
    final kind = await showModalBottomSheet<DealKind>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(tr('Naya sauda', 'New deal'), style: Theme.of(context).textTheme.titleLarge),
            ),
            option(DealKind.purchase, tr('Aap ne maal khareeda', 'You bought goods')),
            option(DealKind.sale, tr('Aap ne maal becha', 'You sold goods')),
            option(DealKind.commission, tr('Aap ne bechne aur khareedne wale ka sauda karwaya', 'You arranged a deal between a seller and a buyer')),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (kind != null) _open(DealFormScreen(kind: kind));
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repo.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Sauday', 'Deals')),
        actions: [
          IconButton(
            tooltip: _showCancelled ? tr('Cancel shuda chhupayein', 'Hide cancelled') : tr('Cancel shuda dikhayein', 'Show cancelled'),
            icon: Icon(_showCancelled ? Icons.visibility_rounded : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _showCancelled = !_showCancelled),
          ),
          const AccountMenuButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newDeal,
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Naya sauda', 'New deal')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: FilterChips<DealKind?>(
              options: [(null, tr('Sab', 'All')), for (final k in DealKind.values) (k, k.label)],
              selected: _kind,
              onSelected: (k) => setState(() => _kind = k),
            ),
          ),
          Expanded(
            child: AsyncView<List<Deal>>(
              cacheKey: 'deals:${_kind?.name ?? 'all'}',
              load: () => repo.deals(kind: _kind),
              builder: (context, all, reload) {
                final list = all.where((d) => _showCancelled || !d.cancelled).toList();
                final days = DayGroups<Deal>(list, (d) => d.date);
                return RefreshIndicator(
                  onRefresh: reload,
                  child: list.isEmpty
                      ? ListView(children: [
                          EmptyState(icon: Icons.swap_horiz_rounded, message: tr('Abhi koi sauda nahi.\n“Naya sauda” dabayein.', 'No deals yet.\nTap “New deal”.')),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: days.rows.length,
                          itemBuilder: (context, i) => days.build(
                            i,
                            (d) => DealTile(deal: d, onTap: () => _open(DealScreen(dealId: d.id))),
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DealTile extends StatelessWidget {
  const DealTile({super.key, required this.deal, required this.onTap});

  final Deal deal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    final d = deal;
    final amount = d.kind == DealKind.commission ? d.commissionTotal : d.goodsAmount;
    return ListTile(
      onTap: onTap,
      leading: DealIcon(d.kind, cancelled: d.cancelled),
      title: Text(d.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: d.cancelled ? TextStyle(decoration: TextDecoration.lineThrough, color: k.muted) : null),
      subtitle: Text([d.kind.label, if (d.summary.isNotEmpty) d.summary].join(' · '),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: d.cancelled
          ? Tag('Cancel', color: k.dena)
          : (amount == null ? null : Amount(amount, size: 15)),
    );
  }
}
