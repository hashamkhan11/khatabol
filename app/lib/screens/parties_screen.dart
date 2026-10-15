import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../util/format.dart';
import 'home_screen.dart';
import 'party_form_screen.dart';
import 'party_screen.dart';

/// The Khata tab: every party with its live balance.
class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key});

  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

enum _Filter { all, receive, pay }

class _PartiesScreenState extends State<PartiesScreen> {
  final _view = GlobalKey<AsyncViewState<List<PartyBalance>>>();
  String _search = '';
  _Filter _filter = _Filter.all;
  bool _showArchived = false;

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repo.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khata'),
        actions: [
          IconButton(
            tooltip: _showArchived ? 'Hide archived' : 'Show archived',
            icon: Icon(_showArchived ? Icons.inventory : Icons.inventory_outlined),
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
          const AccountMenuButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const PartyFormScreen()),
        icon: const Icon(Icons.person_add),
        label: const Text('Party'),
      ),
      body: AsyncView<List<PartyBalance>>(
        key: _view,
        load: repo.partyBalances,
        builder: (context, all, reload) {
          final active = all.where((p) => !p.archived);
          final toReceive = active.where((p) => p.balance > 0).fold<num>(0, (s, p) => s + p.balance);
          final toPay = active.where((p) => p.balance < 0).fold<num>(0, (s, p) => s - p.balance);

          final q = _search.toLowerCase();
          final list = all.where((p) {
            if (p.archived != _showArchived) return false;
            if (q.isNotEmpty && !p.name.toLowerCase().contains(q) && !(p.city ?? '').toLowerCase().contains(q)) {
              return false;
            }
            return switch (_filter) {
              _Filter.all => true,
              _Filter.receive => p.balance > 0,
              _Filter.pay => p.balance < 0,
            };
          }).toList();

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                _Totals(toReceive: toReceive, toPay: toPay),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name or city'),
                    onChanged: (s) => setState(() => _search = s),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: SegmentedButton<_Filter>(
                    segments: const [
                      ButtonSegment(value: _Filter.all, label: Text('All')),
                      ButtonSegment(value: _Filter.receive, label: Text('Owe you')),
                      ButtonSegment(value: _Filter.pay, label: Text('You owe')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) => setState(() => _filter = s.first),
                  ),
                ),
                if (all.isEmpty)
                  const EmptyState(
                    icon: Icons.people_outline,
                    message: 'No parties yet.\nAdd your suppliers, buyers and transporters.',
                  )
                else if (list.isEmpty)
                  const EmptyState(icon: Icons.search_off, message: 'No party matches.')
                else
                  for (final p in list)
                    ListTile(
                      title: Text(p.name),
                      subtitle: Text([
                        p.type.label,
                        ?p.city,
                        if (p.lastEntryDate != null) 'last ${formatShortDate(p.lastEntryDate!)}',
                      ].join(' · ')),
                      trailing: BalanceText(p.balance),
                      onTap: () => _open(PartyScreen(partyId: p.id)),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.toReceive, required this.toPay});

  final num toReceive;
  final num toPay;

  @override
  Widget build(BuildContext context) {
    Widget box(String label, num amount, Color color) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text(money(amount),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(children: [
        box('To receive', toReceive, AppColors.receive),
        box('To pay', toPay, AppColors.pay),
      ]),
    );
  }
}
