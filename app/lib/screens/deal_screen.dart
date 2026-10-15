import 'package:flutter/material.dart';

import '../data/deal_draft.dart';
import '../data/models.dart';
import '../ui/common.dart';
import '../util/format.dart';
import 'deal_form_screen.dart';

/// A deal's details and every khata line it wrote. Deals are never changed in
/// place: "Edit" cancels this deal and records a corrected one.
class DealScreen extends StatefulWidget {
  const DealScreen({super.key, required this.dealId});

  final String dealId;

  @override
  State<DealScreen> createState() => _DealScreenState();
}

class _DealScreenState extends State<DealScreen> {
  final _view = GlobalKey<AsyncViewState<(Deal, List<KhataEntry>)>>();

  Future<(Deal, List<KhataEntry>)> _load() async {
    final repo = Repo.of(context);
    return (await repo.deal(widget.dealId), await repo.dealEntries(widget.dealId));
  }

  Future<void> _edit(Deal deal, List<KhataEntry> entries) async {
    // Money paid on the spot is a khata line of the deal, not a deal column.
    final paid = entries
        .where((e) => e.reversesId == null && (e.kind == 'payment_out' || e.kind == 'payment_in'))
        .firstOrNull;
    final draft = DealDraft.fromDeal(deal, paidNow: paid?.amount.abs(), paidMethod: paid?.method);
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DealFormScreen(kind: deal.kind, editing: deal.id, initial: draft)),
    );
    // The edit created a new deal; this one is now cancelled.
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _cancel(Deal deal) async {
    final reason = await askCancelReason(
      context,
      title: 'Cancel this deal?',
      message: 'Every khata line of this deal gets a cancelling line, and it leaves stock and profit. '
          'Nothing is deleted.',
    );
    if (reason == null || !mounted) return;
    try {
      await Repo.of(context).cancelDeal(deal.id, reason: reason);
      if (mounted) showDone(context, 'Deal cancelled');
      _view.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<(Deal, List<KhataEntry>)>(
      key: _view,
      load: _load,
      builder: (context, data, reload) {
        final (deal, entries) = data;
        final names = {for (final e in entries) e.partyId: e.partyName};
        return Scaffold(
          appBar: AppBar(
            title: Text(deal.kind.label),
            actions: [
              if (!deal.cancelled) ...[
                IconButton(
                    tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(deal, entries)),
                IconButton(
                    tooltip: 'Cancel deal', icon: const Icon(Icons.delete_outline), onPressed: () => _cancel(deal)),
              ],
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (deal.cancelled)
                MaterialBanner(
                  content: Text('Cancelled${deal.cancelReason == null ? '' : ': ${deal.cancelReason}'}'),
                  leading: const Icon(Icons.block, color: AppColors.pay),
                  actions: const [SizedBox.shrink()],
                ),
              const SectionTitle('Deal'),
              InfoRow('Date', formatDate(deal.date)),
              InfoRow(
                switch (deal.kind) {
                  DealKind.purchase => 'Supplier',
                  DealKind.sale => 'Buyer',
                  DealKind.commission => 'Seller',
                },
                deal.partyName,
              ),
              if (deal.buyerName != null) InfoRow('Buyer', deal.buyerName!),
              if (deal.itemName != null) InfoRow('Cloth type', deal.itemName!),
              if (deal.weightKg != null) InfoRow('Weight', kg(deal.weightKg!)),
              if (deal.rate != null) InfoRow('Rate', '${money(deal.rate!)} per kg'),
              if (deal.goodsAmount != null)
                InfoRow('Goods amount', money(deal.goodsAmount!), valueStyle: const TextStyle(fontWeight: FontWeight.w600)),
              if (deal.kind == DealKind.commission)
                InfoRow('Goods money', deal.goodsThroughMe ? 'Through me' : 'Direct, buyer to seller'),
              if (deal.notes != null) InfoRow('Notes', deal.notes!),
              if (deal.source != 'app') InfoRow('Entered by', deal.source == 'whatsapp' ? 'WhatsApp' : deal.source),
              if (deal.commissions.isNotEmpty) ...[
                const SectionTitle('Commission'),
                for (final c in deal.commissions)
                  InfoRow(
                    '${names[c.partyId] ?? ''} · ${switch (c.mode) {
                      CommissionMode.perKg => '${plainNumber(c.value)} per kg',
                      CommissionMode.percent => '${plainNumber(c.value)}%',
                      CommissionMode.fixed => 'fixed',
                    }}',
                    money(c.amount ?? 0),
                  ),
              ],
              if (deal.costs.isNotEmpty) ...[
                const SectionTitle('Extra costs'),
                for (final c in deal.costs)
                  InfoRow(
                    '${c.description} · ${c.chargedToId == null ? 'you bear it' : 'charged to ${names[c.chargedToId] ?? 'party'}'}'
                    '${c.paidToName == null ? '' : ' · owed to ${c.paidToName}'}',
                    money(c.amount),
                  ),
              ],
              const SectionTitle('Khata lines'),
              for (final e in entries)
                ListTile(
                  dense: true,
                  title: Text(e.partyName ?? ''),
                  subtitle: Text(e.note ?? e.kind),
                  trailing: Text(
                    '${e.amount >= 0 ? '+' : '−'} ${plainNumber(e.amount.abs())}',
                    style: TextStyle(color: balanceColor(e.amount), fontWeight: FontWeight.w600),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('+ means the party owes you more. − means you owe them more.'),
              ),
            ],
          ),
        );
      },
    );
  }
}
