import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../util/format.dart';
import 'deal_screen.dart';
import 'party_form_screen.dart';
import 'payment_screen.dart';

/// One party's khata: balance, running statement, and payment buttons.
class PartyScreen extends StatefulWidget {
  const PartyScreen({super.key, required this.partyId});

  final String partyId;

  @override
  State<PartyScreen> createState() => _PartyScreenState();
}

class _PartyData {
  _PartyData(this.party, this.lines);
  final Party party;
  final List<StatementLine> lines;

  num get balance => lines.isEmpty ? 0 : lines.last.balance;
}

class _PartyScreenState extends State<PartyScreen> {
  final _view = GlobalKey<AsyncViewState<_PartyData>>();
  bool _includeCancelled = false;

  Future<_PartyData> _load() async {
    final repo = Repo.of(context);
    final results = await Future.wait([
      repo.party(widget.partyId),
      repo.statement(widget.partyId, includeCancelled: _includeCancelled),
    ]);
    return _PartyData(results[0] as Party, results[1] as List<StatementLine>);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _view.currentState?.reload();
  }

  Future<void> _onLineTap(StatementLine line) async {
    if (line.isBroughtForward || line.entryId == null) return;
    final repo = Repo.of(context);
    try {
      final entry = await repo.entry(line.entryId!);
      if (!mounted) return;
      if (entry.dealId != null) {
        return _open(DealScreen(dealId: entry.dealId!));
      }
      if (entry.expenseId != null) {
        return showDone(context, 'This line is from an expense. Cancel it from the Expenses tab.');
      }
      if (line.isReversal) return;
      final reason = await askCancelReason(
        context,
        title: 'Cancel this line?',
        message: '${line.note}\n${money(line.amount)} on ${formatDate(line.date)}\n\n'
            'A cancelling line is added; nothing is deleted.',
      );
      if (reason == null) return;
      await repo.reverseEntry(line.entryId!, reason: reason);
      if (mounted) showDone(context, 'Line cancelled');
      _view.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleArchive(Party p) async {
    final archive = !p.archived;
    final ok = await confirm(
      context,
      title: archive ? 'Archive ${p.name}?' : 'Restore ${p.name}?',
      message: archive ? 'The khata is kept, but no new entries can be added.' : null,
      action: archive ? 'Archive' : 'Restore',
    );
    if (!ok || !mounted) return;
    try {
      await Repo.of(context).setPartyArchived(p.id, archive);
      _view.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<_PartyData>(
      key: _view,
      load: _load,
      builder: (context, data, reload) {
        final p = data.party;
        return Scaffold(
          appBar: AppBar(
            title: Text(p.name),
            actions: [
              PopupMenuButton<String>(
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit details')),
                  CheckedPopupMenuItem(
                      value: 'cancelled', checked: _includeCancelled, child: const Text('Show cancelled lines')),
                  const PopupMenuItem(value: 'adjust', child: Text('Correction')),
                  PopupMenuItem(value: 'archive', child: Text(p.archived ? 'Restore party' : 'Archive party')),
                ],
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      _open(PartyFormScreen(party: p));
                    case 'cancelled':
                      setState(() => _includeCancelled = !_includeCancelled);
                      reload();
                    case 'adjust':
                      _open(PaymentScreen(party: p, mode: PaymentMode.adjustment));
                    case 'archive':
                      _toggleArchive(p);
                  }
                },
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Card(
                  margin: const EdgeInsets.all(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text([p.type.label, ?p.city].join(' · ')),
                              if (p.phone != null) Text(p.phone!),
                              if (p.archived) const Text('Archived', style: TextStyle(color: AppColors.pay)),
                            ],
                          ),
                        ),
                        BalanceText(data.balance, large: true),
                      ],
                    ),
                  ),
                ),
                if (!p.archived)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.receive),
                            onPressed: () => _open(PaymentScreen(party: p, mode: PaymentMode.received)),
                            icon: const Icon(Icons.call_received),
                            label: const Text('Received'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.pay),
                            onPressed: () => _open(PaymentScreen(party: p, mode: PaymentMode.paid)),
                            icon: const Icon(Icons.call_made),
                            label: const Text('Paid'),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SectionTitle('Khata'),
                if (data.lines.isEmpty)
                  const EmptyState(icon: Icons.menu_book_outlined, message: 'No entries yet.')
                else
                  for (final line in data.lines.reversed) _LineTile(line: line, onTap: () => _onLineTap(line)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.onTap});

  final StatementLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = line.isReversal;
    final amountColor = line.amount >= 0 ? AppColors.receive : AppColors.pay;
    return ListTile(
      onTap: onTap,
      title: Text(line.note, style: muted ? const TextStyle(fontStyle: FontStyle.italic) : null),
      subtitle: Text([formatDate(line.date), if (line.method != null) line.method!.label].join(' · ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!line.isBroughtForward)
            Text('${line.amount >= 0 ? '+' : '−'} ${plainNumber(line.amount.abs())}',
                style: TextStyle(color: amountColor, fontWeight: FontWeight.w600)),
          Text('Bal ${plainNumber(line.balance)}', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
