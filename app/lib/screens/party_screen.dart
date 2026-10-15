import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/khata_text.dart';
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
  final List<KhataLine> lines;

  num get balance => lines.isEmpty ? 0 : lines.last.balance ?? 0;
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
    return _PartyData(results[0] as Party, results[1] as List<KhataLine>);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _view.currentState?.reload();
  }

  Future<void> _onLineTap(KhataLine line) async {
    if (line.isBroughtForward) return;
    if (line.dealId != null) return _open(DealScreen(dealId: line.dealId!));
    if (line.expenseId != null) {
      return showDone(context, 'Yeh line kharchay ki hai. Usay Kharchay tab se cancel karein.');
    }
    if (line.cancelled) return;
    final repo = Repo.of(context);
    try {
      final reason = await askCancelReason(
        context,
        title: 'Yeh line cancel karni hai?',
        message: '${lineTitle(line)}\n${money(line.amount)} · ${formatDate(line.date)}\n\n'
            'Ek cancel ki line jurr jayegi; kuch delete nahi hota.',
      );
      if (reason == null) return;
      await repo.reverseEntry(line.entryId!, reason: reason);
      if (mounted) showDone(context, 'Line cancel ho gayi');
      _view.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleArchive(Party p) async {
    final archive = !p.archived;
    final ok = await confirm(
      context,
      title: archive ? '${p.name} ko archive karna hai?' : '${p.name} ko wapas laana hai?',
      message: archive ? 'Khata mehfooz rahega, lekin nayi entry nahi ho sakegi.' : null,
      action: archive ? 'Archive' : 'Wapas laayein',
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
                  const PopupMenuItem(value: 'edit', child: Text('Tafseel badlein')),
                  CheckedPopupMenuItem(
                      value: 'cancelled', checked: _includeCancelled, child: const Text('Cancel shuda lines dikhayein')),
                  const PopupMenuItem(value: 'adjust', child: Text('Durusti')),
                  PopupMenuItem(value: 'archive', child: Text(p.archived ? 'Party wapas laayein' : 'Party archive karein')),
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
                              if (p.archived) const Text('Archive shuda', style: TextStyle(color: AppColors.pay)),
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
                            label: const Text('Paise mile'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.pay),
                            onPressed: () => _open(PaymentScreen(party: p, mode: PaymentMode.paid)),
                            icon: const Icon(Icons.call_made),
                            label: const Text('Paise diye'),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SectionTitle('Khata'),
                if (data.lines.isEmpty)
                  const EmptyState(icon: Icons.menu_book_outlined, message: 'Abhi koi entry nahi.')
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

  final KhataLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amountColor = line.amount >= 0 ? AppColors.receive : AppColors.pay;
    return ListTile(
      onTap: onTap,
      title: Text(lineTitle(line),
          style: line.cancelled ? const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey) : null),
      subtitle: Text(lineDetails(line)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!line.isBroughtForward)
            Text(signedAmount(line.amount),
                style: TextStyle(color: amountColor, fontWeight: FontWeight.w600)),
          Text('Baqaya ${plainNumber(line.balance ?? 0)}', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
