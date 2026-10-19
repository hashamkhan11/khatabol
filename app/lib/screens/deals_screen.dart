import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import 'deal_form_screen.dart';
import 'deal_screen.dart';
import 'home_screen.dart';
import '../l10n/lang.dart';

IconData dealIcon(DealKind kind) => switch (kind) {
      DealKind.purchase => KIcons.purchase,
      DealKind.sale => KIcons.sale,
      DealKind.commission => KIcons.commission,
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: DealIcon(kind, size: 44),
          title: Text(kind.label, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(hint),
          trailing: Icon(KIcons.chevronRight, size: 18, color: KColors.of(context).muted),
          onTap: () => Navigator.pop(context, kind),
        );
    final kind = await showModalBottomSheet<DealKind>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text(tr('Naya sauda', 'New deal'), style: Theme.of(context).textTheme.titleLarge),
              ),
              SheetGroup(children: [
                option(DealKind.purchase, tr('Aap ne maal khareeda', 'You bought goods')),
                option(DealKind.sale, tr('Aap ne maal becha', 'You sold goods')),
                option(DealKind.commission,
                    tr('Aap ne bechne aur khareedne wale ka sauda karwaya', 'You arranged a deal between a seller and a buyer')),
              ]),
            ],
          ),
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
          ToggleAction(
            label: tr('Cancel shuda', 'Cancelled'),
            icon: KIcons.cancelled,
            on: _showCancelled,
            onChanged: (v) => setState(() => _showCancelled = v),
          ),
          const AccountMenuButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newDeal,
        icon: const Icon(KIcons.add),
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
                          EmptyState(icon: KIcons.deals, message: tr('Abhi koi sauda nahi.\n“Naya sauda” dabayein.', 'No deals yet.\nTap “New deal”.')),
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
