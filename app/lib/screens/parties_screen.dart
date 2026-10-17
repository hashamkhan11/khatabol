import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
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
  String _search = '';
  _Filter _filter = _Filter.all;
  bool _showArchived = false;

  void _open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final repo = Repo.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Archive' : 'Khata'),
        actions: [
          IconButton(
            tooltip: _showArchived ? 'Archive chhupayein' : 'Archive dikhayein',
            icon: Icon(_showArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
          const AccountMenuButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const PartyFormScreen()),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nayi party'),
      ),
      body: AsyncView<List<PartyBalance>>(
        cacheKey: 'parties',
        load: repo.partyBalances,
        builder: (context, all, reload) {
          final active = all.where((p) => !p.archived);
          final toReceive = active.where((p) => p.balance > 0).fold<num>(0, (s, p) => s + p.balance);
          final toPay = active.where((p) => p.balance < 0).fold<num>(0, (s, p) => s - p.balance);
          final receiveCount = active.where((p) => p.balance > 0).length;
          final payCount = active.where((p) => p.balance < 0).length;

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

          final header = <Widget>[
            if (!_showArchived) TotalsRow(toReceive: toReceive, toPay: toPay),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Naam ya shehar talaash karein',
                ),
                onChanged: (s) => setState(() => _search = s),
              ),
            ),
            if (!_showArchived)
              FilterChips<_Filter>(
                options: [
                  (_Filter.all, 'Sab ${active.length}'),
                  (_Filter.receive, 'Lena hai $receiveCount'),
                  (_Filter.pay, 'Dena hai $payCount'),
                ],
                selected: _filter,
                onSelected: (f) => setState(() => _filter = f),
              ),
            const SizedBox(height: 12),
          ];

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: header.length + (list.isEmpty ? 1 : list.length),
              itemBuilder: (context, i) {
                if (i < header.length) return header[i];
                if (list.isEmpty) {
                  return all.isEmpty
                      ? const EmptyState(
                          icon: Icons.people_outline_rounded,
                          message: 'Abhi koi party nahi.\nApne supplier, gahak aur transporter shamil karein.',
                        )
                      : const EmptyState(icon: Icons.search_off_rounded, message: 'Koi party nahi mili.');
                }
                final n = i - header.length;
                final p = list[n];
                return GroupedRow(
                  first: n == 0,
                  last: n == list.length - 1,
                  child: PartyTile(party: p, showLastEntry: true, onTap: () => _open(PartyScreen(partyId: p.id))),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
