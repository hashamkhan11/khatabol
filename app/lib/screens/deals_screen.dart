import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../util/format.dart';
import 'deal_form_screen.dart';
import 'deal_screen.dart';
import 'home_screen.dart';

IconData dealIcon(DealKind kind) => switch (kind) {
      DealKind.purchase => Icons.south_west,
      DealKind.sale => Icons.north_east,
      DealKind.commission => Icons.handshake_outlined,
    };

/// The Deals tab: purchases, sales and commission deals, newest first.
class DealsScreen extends StatefulWidget {
  const DealsScreen({super.key});

  @override
  State<DealsScreen> createState() => _DealsScreenState();
}

class _DealsScreenState extends State<DealsScreen> {
  final _view = GlobalKey<AsyncViewState<List<Deal>>>();
  DealKind? _kind;
  bool _showCancelled = false;

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _view.currentState?.reload();
  }

  Future<void> _newDeal() async {
    final kind = await showModalBottomSheet<DealKind>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('New deal')),
            ListTile(
              leading: Icon(dealIcon(DealKind.purchase)),
              title: const Text('Purchase'),
              subtitle: const Text('You bought cloth'),
              onTap: () => Navigator.pop(context, DealKind.purchase),
            ),
            ListTile(
              leading: Icon(dealIcon(DealKind.sale)),
              title: const Text('Sale'),
              subtitle: const Text('You sold cloth'),
              onTap: () => Navigator.pop(context, DealKind.sale),
            ),
            ListTile(
              leading: Icon(dealIcon(DealKind.commission)),
              title: const Text('Commission'),
              subtitle: const Text('You arranged a deal between a seller and a buyer'),
              onTap: () => Navigator.pop(context, DealKind.commission),
            ),
          ],
        ),
      ),
    );
    if (kind != null) await _open(DealFormScreen(kind: kind));
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repo.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deals'),
        actions: [
          IconButton(
            tooltip: _showCancelled ? 'Hide cancelled' : 'Show cancelled',
            icon: Icon(_showCancelled ? Icons.visibility : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _showCancelled = !_showCancelled),
          ),
          const AccountMenuButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newDeal,
        icon: const Icon(Icons.add),
        label: const Text('Deal'),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                for (final k in <DealKind?>[null, ...DealKind.values])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(k?.label ?? 'All'),
                      selected: _kind == k,
                      onSelected: (_) {
                        setState(() => _kind = k);
                        _view.currentState?.reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<List<Deal>>(
              key: _view,
              load: () => repo.deals(kind: _kind),
              builder: (context, all, reload) {
                final list = all.where((d) => _showCancelled || !d.cancelled).toList();
                return RefreshIndicator(
                  onRefresh: reload,
                  child: list.isEmpty
                      ? ListView(children: const [
                          EmptyState(icon: Icons.swap_horiz, message: 'No deals yet.\nTap “Deal” to add one.'),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: list.length,
                          itemBuilder: (context, i) => DealTile(
                            deal: list[i],
                            onTap: () => _open(DealScreen(dealId: list[i].id)),
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
    final d = deal;
    final cancelled = d.cancelled ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey) : null;
    final amount = d.kind == DealKind.commission ? d.commissionTotal : d.goodsAmount;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(child: Icon(dealIcon(d.kind), size: 20)),
      title: Text(d.title, style: cancelled),
      subtitle: Text(
        [formatShortDate(d.date), d.kind.label, if (d.summary.isNotEmpty) d.summary, if (d.cancelled) 'Cancelled']
            .join(' · '),
      ),
      trailing: amount == null ? null : Text(money(amount), style: cancelled ?? const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
