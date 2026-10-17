import 'package:flutter/material.dart';

import '../data/deal_draft.dart';
import '../data/models.dart';
import '../l10n/khata_text.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../util/format.dart';
import 'deal_form_screen.dart';
import 'deals_screen.dart';
import '../l10n/lang.dart';

/// A deal's details and every khata line it wrote. Deals are never changed in
/// place: editing cancels this deal and records a corrected one.
class DealScreen extends StatefulWidget {
  const DealScreen({super.key, required this.dealId});

  final String dealId;

  @override
  State<DealScreen> createState() => _DealScreenState();
}

class _DealScreenState extends State<DealScreen> {
  Future<(Deal, List<KhataLine>)> _load() async {
    final repo = Repo.of(context);
    return await (repo.deal(widget.dealId), repo.dealLines(widget.dealId)).wait;
  }

  Future<void> _edit(Deal deal, List<KhataLine> entries) async {
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
      title: tr('Yeh sauda cancel karna hai?', 'Cancel this deal?'),
      message: tr(
          'Is sauday ki har khata line ke saamne cancel ki line jurr jayegi, aur yeh stock aur munafay se nikal jayega. '
              'Kuch delete nahi hota.',
          'Every ledger line of this deal gets a cancelling line, and it leaves stock and profit. '
              'Nothing is deleted.'),
    );
    if (reason == null || !mounted) return;
    try {
      await Repo.of(context).cancelDeal(deal.id, reason: reason);
      if (mounted) showDone(context, tr('Sauda cancel ho gaya', 'Deal cancelled'));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: AsyncView<(Deal, List<KhataLine>)>(
        cacheKey: 'deal:${widget.dealId}',
        skeleton: const SkeletonPage(),
        load: _load,
        builder: (context, data, reload) {
          final (deal, entries) = data;
          final names = {for (final e in entries) e.partyId: e.partyName};
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _Header(
                  deal: deal,
                  onEdit: deal.cancelled ? null : () => _edit(deal, entries),
                  onCancel: deal.cancelled ? null : () => _cancel(deal),
                ),
                Section(
                  title: tr('Tafseel', 'Details'),
                  dividerIndent: 16,
                  children: [
                    InfoRow(tr('Tareekh', 'Date'), formatDate(deal.date)),
                    InfoRow(
                      switch (deal.kind) {
                        DealKind.purchase => 'Supplier',
                        DealKind.sale => tr('Gahak', 'Buyer'),
                        DealKind.commission => tr('Bechne wala', 'Seller'),
                      },
                      deal.partyName,
                    ),
                    if (deal.buyerName != null) InfoRow(tr('Khareedne wala', 'Buyer'), deal.buyerName!),
                    if (deal.itemName != null) InfoRow(tr('Kapre ki qisam', 'Cloth type'), deal.itemName!),
                    if (deal.weightKg != null) InfoRow(tr('Wazan', 'Weight'), kg(deal.weightKg!)),
                    if (deal.rate != null) InfoRow('Rate', '${money(deal.rate!)} ${tr('fi kg', 'per kg')}'),
                    if (deal.goodsAmount != null) InfoRow(tr('Maal ki raqam', 'Goods amount'), money(deal.goodsAmount!)),
                    if (deal.kind == DealKind.commission)
                      InfoRow(tr('Maal ke paise', 'Goods money'), deal.goodsThroughMe ? tr('Mere zariye', 'Through me') : tr('Seedhay, khareedne wale se bechne wale ko', 'Direct, from buyer to seller')),
                    if (deal.notes != null) InfoRow('Note', deal.notes!),
                    if (deal.source != 'app') InfoRow(tr('Kahan se darj hua', 'Entered from'), deal.source == 'whatsapp' ? 'WhatsApp' : deal.source),
                  ],
                ),
                if (deal.commissions.isNotEmpty)
                  Section(
                    title: 'Commission',
                    dividerIndent: 16,
                    children: [
                      for (final c in deal.commissions)
                        InfoRow(
                          '${names[c.partyId] ?? ''} · ${switch (c.mode) {
                            CommissionMode.perKg => '${plainNumber(c.value)} ${tr('fi kg', 'per kg')}',
                            CommissionMode.percent => '${plainNumber(c.value)}%',
                            CommissionMode.fixed => tr('pakki raqam', 'fixed amount'),
                          }}',
                          money(c.amount ?? 0),
                        ),
                    ],
                  ),
                if (deal.costs.isNotEmpty)
                  Section(
                    title: tr('Izafi kharchay', 'Extra costs'),
                    dividerIndent: 16,
                    children: [
                      for (final c in deal.costs)
                        InfoRow(
                          '${c.description} · ${c.chargedToId == null ? tr('mere zimme', 'on me') : tr('${names[c.chargedToId] ?? 'party'} ke zimme', 'on ${names[c.chargedToId] ?? 'party'}')}'
                          '${c.paidToName == null ? '' : ' · ${tr('${c.paidToName} ko dena hai', 'to pay ${c.paidToName}')}'}',
                          money(c.amount),
                        ),
                    ],
                  ),
                Section(
                  title: tr('Khata ki lines', 'Ledger lines'),
                  children: [
                    for (final e in entries)
                      ListTile(
                        leading: LineIcon(kind: e.reversesId == null ? e.kind : 'reversal', amount: e.amount),
                        title: Text(e.partyName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(lineTitle(e), maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Amount(e.amount, signed: true, size: 15, color: KColors.of(context).forBalance(e.amount)),
                      ),
                  ],
                ),
                FormHint(
                  tr('+ ka matlab party se lena barha. − ka matlab party ko dena barha.', '+ means more to receive from the party. − means more to pay them.'),
                  margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.deal, this.onEdit, this.onCancel});

  final Deal deal;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    final text = Theme.of(context).textTheme;
    final summary = [
      if (deal.itemName != null) deal.itemName!,
      if (deal.weightKg != null) kg(deal.weightKg!),
      if (deal.rate != null) '${money(deal.rate!)} ${tr('fi kg', 'per kg')}',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(color: k.surface, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DealIcon(deal.kind, cancelled: deal.cancelled, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deal.partyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${deal.kind.label} · ${dayLabel(deal.date)}', style: TextStyle(color: k.muted)),
                  ],
                ),
              ),
            ],
          ),
          if (deal.goodsAmount != null) ...[
            const SizedBox(height: 20),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Amount(deal.goodsAmount!,
                  size: 34, weight: FontWeight.w800, color: deal.cancelled ? k.muted : null),
            ),
          ],
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(summary, style: TextStyle(color: k.muted, fontFeatures: tabular)),
          ],
          const SizedBox(height: 16),
          if (deal.cancelled)
            FormHint('${tr('Cancel shuda', 'Cancelled')}${deal.cancelReason == null ? '' : ': ${deal.cancelReason}'}', warn: true)
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    label: Text(tr('Badlein', 'Edit')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(foregroundColor: k.dena),
                    icon: const Icon(Icons.block_rounded, size: 20),
                    label: const Text('Cancel'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
