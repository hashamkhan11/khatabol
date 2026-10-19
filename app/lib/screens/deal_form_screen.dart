import 'package:flutter/material.dart';

import '../data/deal_draft.dart';
import '../data/models.dart';
import '../ui/common.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../util/format.dart';
import '../l10n/lang.dart';

/// Records a new purchase, sale or commission deal, or edits one.
/// Editing cancels the old deal and records the corrected one in one step.
class DealFormScreen extends StatelessWidget {
  const DealFormScreen({super.key, required this.kind, this.editing, this.initial});

  final DealKind kind;

  /// The deal being edited, if any.
  final String? editing;
  final DealDraft? initial;

  @override
  Widget build(BuildContext context) {
    final repo = Repo.of(context);
    return AsyncView<(List<Party>, List<Item>)>(
      cacheKey: 'deal-form',
      skeleton: const SkeletonPage(),
      load: () async => await (repo.activeParties(), repo.activeItems()).wait,
      builder: (context, data, _) => _DealForm(
        draft: initial ?? _newDraft(),
        editing: editing,
        parties: data.$1,
        items: data.$2,
      ),
    );
  }

  DealDraft _newDraft() {
    final d = DealDraft(kind: kind);
    if (kind == DealKind.commission) d.commissions.add(CommissionDraft());
    return d;
  }
}

class _DealForm extends StatefulWidget {
  const _DealForm({required this.draft, required this.editing, required this.parties, required this.items});

  final DealDraft draft;
  final String? editing;
  final List<Party> parties;
  final List<Item> items;

  @override
  State<_DealForm> createState() => _DealFormState();
}

class _DealFormState extends State<_DealForm> {
  late final DealDraft d = widget.draft;
  bool _saving = false;

  String _name(String? id) => widget.parties.where((p) => p.id == id).firstOrNull?.name ?? '—';

  void _update(VoidCallback change) => setState(change);

  Future<void> _save() async {
    final problem = d.validate();
    if (problem != null) return showError(context, problem);
    setState(() => _saving = true);
    final repo = Repo.of(context);
    try {
      if (widget.editing != null) {
        await repo.replaceDeal(widget.editing!, d);
      } else {
        await repo.recordDeal(d);
      }
      if (mounted) {
        showDone(context, widget.editing != null ? tr('Sauda badal diya', 'Deal updated') : tr('Sauda save ho gaya', 'Deal saved'));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parties = widget.parties;
    return FormPage(
      title: widget.editing != null ? tr('${d.kind.label} badlein', 'Edit ${d.kind.label.toLowerCase()}') : tr('Nayi ${d.kind.label.toLowerCase()}', 'New ${d.kind.label.toLowerCase()}'),
      saving: _saving,
      onSave: _save,
      saveLabel: widget.editing != null ? tr('Tabdeeli save karein', 'Save changes') : tr('Sauda save karein', 'Save deal'),
      children: [
        DateField(value: d.date, onChanged: (v) => _update(() => d.date = v)),
        PartyField(
          label: switch (d.kind) {
            DealKind.purchase => tr('Supplier (jis se khareeda)', 'Supplier (bought from)'),
            DealKind.sale => tr('Gahak (jis ko becha)', 'Buyer (sold to)'),
            DealKind.commission => tr('Bechne wala', 'Seller'),
          },
          parties: parties,
          value: d.partyId,
          onChanged: (v) => _update(() => d.partyId = v),
        ),
        if (d.isCommission)
          PartyField(
            label: tr('Khareedne wala', 'Buyer'),
            parties: parties,
            value: d.buyerId,
            onChanged: (v) => _update(() => d.buyerId = v),
          ),
        ItemField(
          label: d.isCommission ? tr('Kapre ki qisam (agar ho)', 'Cloth type (optional)') : tr('Kapre ki qisam', 'Cloth type'),
          items: widget.items,
          value: d.itemId,
          onChanged: (v) => _update(() => d.itemId = v),
        ),
        Row(
          children: [
            Expanded(
              child: NumberField(
                label: d.isCommission ? tr('Wazan (agar ho)', 'Weight (optional)') : tr('Wazan', 'Weight'),
                suffix: 'kg',
                initial: d.weightKg,
                onChanged: (v) => _update(() => d.weightKg = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NumberField(
                label: d.isCommission ? tr('Rate (agar ho)', 'Rate (optional)') : 'Rate',
                suffix: 'Rs/kg',
                initial: d.rate,
                onChanged: (v) => _update(() => d.rate = v),
              ),
            ),
          ],
        ),
        if (d.goodsAmount != null) InfoRow(tr('Maal ki raqam', 'Goods amount'), money(d.goodsAmount!)),
        if (d.isCommission)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Maal ke paise mere zariye', 'Goods money goes through me')),
            subtitle: Text(tr('Khareedne wala aap ko deta hai, aap bechne wale ko', 'The buyer pays you, you pay the seller')),
            value: d.goodsThroughMe,
            onChanged: (v) => _update(() => d.goodsThroughMe = v),
          ),
        if (!d.isCommission) ..._paidNow(),
        if (d.isCommission) ..._commissions(),
        ..._costs(),
        TextFormField(
          initialValue: d.notes,
          maxLines: 2,
          decoration: InputDecoration(labelText: tr('Note (agar ho)', 'Note (optional)')),
          onChanged: (v) => d.notes = v,
        ),
        _Preview(effects: d.khataEffects(), nameOf: _name),
      ],
    );
  }

  List<Widget> _paidNow() => [
        NumberField(
          label: d.kind == DealKind.purchase ? tr('Abhi diye (agar diye)', 'Paid now (if any)') : tr('Abhi mile (agar mile)', 'Received now (if any)'),
          suffix: 'Rs',
          initial: d.paidNow,
          helper: tr('Sab udhaar ho to khali chhorein', 'Leave empty if all on credit'),
          onChanged: (v) => _update(() => d.paidNow = v),
        ),
        if ((d.paidNow ?? 0) > 0)
          Segments<PaymentMethod>(
            options: [for (final m in PaymentMethod.values) (m, m.label)],
            selected: d.paidMethod,
            onChanged: (m) => _update(() => d.paidMethod = m),
          ),
      ];

  List<Widget> _commissions() => [
        SectionTitle(
          'Commission',
          trailing: TextButton.icon(
            onPressed: () => _update(() => d.commissions.add(CommissionDraft())),
            icon: const Icon(KIcons.add, size: 18),
            label: Text(tr('Aur', 'Add')),
          ),
        ),
        for (final c in d.commissions)
          _CommissionRow(
            key: ObjectKey(c),
            draft: c,
            sellerId: d.partyId,
            buyerId: d.buyerId,
            nameOf: _name,
            amount: d.commissionAmount(c),
            onChanged: () => _update(() {}),
            onRemove: () => _update(() => d.commissions.remove(c)),
          ),
      ];

  List<Widget> _costs() => [
        SectionTitle(
          tr('Izafi kharchay (kiraya, mazdoori…)', 'Extra costs (fare, labour…)'),
          trailing: TextButton.icon(
            onPressed: () => _update(() => d.costs.add(CostDraft())),
            icon: const Icon(KIcons.add, size: 18),
            label: Text(tr('Aur', 'Add')),
          ),
        ),
        for (final c in d.costs)
          _CostRow(
            key: ObjectKey(c),
            draft: c,
            dealParties: [?d.partyId, if (d.isCommission) ?d.buyerId],
            parties: widget.parties,
            nameOf: _name,
            onChanged: () => _update(() {}),
            onRemove: () => _update(() => d.costs.remove(c)),
          ),
      ];
}

class _CommissionRow extends StatelessWidget {
  const _CommissionRow({
    super.key,
    required this.draft,
    required this.sellerId,
    required this.buyerId,
    required this.nameOf,
    required this.amount,
    required this.onChanged,
    required this.onRemove,
  });

  final CommissionDraft draft;
  final String? sellerId;
  final String? buyerId;
  final String Function(String?) nameOf;
  final num? amount;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final from = [?sellerId, ?buyerId];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ChoiceField<String>(
                    label: tr('Kis se', 'From whom'),
                    value: from.contains(draft.partyId) ? draft.partyId : null,
                    options: [
                      for (final id in from)
                        (id, '${nameOf(id)} (${id == sellerId ? tr('bechne wala', 'seller') : tr('khareedne wala', 'buyer')})'),
                    ],
                    onChanged: (v) {
                      draft.partyId = v;
                      onChanged();
                    },
                  ),
                ),
                IconButton(onPressed: onRemove, icon: const Icon(KIcons.close, size: 20), tooltip: tr('Hatayein', 'Remove')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ChoiceField<CommissionMode>(
                    label: tr('Kaise', 'How'),
                    value: draft.mode,
                    options: [for (final m in CommissionMode.values) (m, m.label)],
                    onChanged: (m) {
                      draft.mode = m;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NumberField(
                    label: tr('Miqdar', 'Value'),
                    initial: draft.value,
                    suffix: switch (draft.mode) {
                      CommissionMode.perKg => 'Rs/kg',
                      CommissionMode.percent => '%',
                      CommissionMode.fixed => 'Rs',
                    },
                    onChanged: (v) {
                      draft.value = v;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            if (amount != null) InfoRow('Commission', money(amount!)),
          ],
        ),
      ),
    );
  }
}

class _CostRow extends StatelessWidget {
  const _CostRow({
    super.key,
    required this.draft,
    required this.dealParties,
    required this.parties,
    required this.nameOf,
    required this.onChanged,
    required this.onRemove,
  });

  final CostDraft draft;
  final List<String> dealParties;
  final List<Party> parties;
  final String Function(String?) nameOf;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    const me = '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: draft.description,
                    decoration: InputDecoration(labelText: tr('Kis cheez ka', 'What for'), hintText: tr('Kiraya, mazdoori…', 'Fare, labour…')),
                    onChanged: (v) {
                      draft.description = v;
                      onChanged();
                    },
                  ),
                ),
                IconButton(onPressed: onRemove, icon: const Icon(KIcons.close, size: 20), tooltip: tr('Hatayein', 'Remove')),
              ],
            ),
            const SizedBox(height: 12),
            NumberField(
              label: tr('Raqam', 'Amount'),
              suffix: 'Rs',
              initial: draft.amount,
              onChanged: (v) {
                draft.amount = v;
                onChanged();
              },
            ),
            const SizedBox(height: 12),
            ChoiceField<String>(
              label: tr('Kis ke zimme', 'Charged to'),
              value: dealParties.contains(draft.chargedToId) ? draft.chargedToId : me,
              options: [
                (me, tr('Mere', 'Me')),
                for (final id in dealParties) (id, nameOf(id)),
              ],
              onChanged: (v) {
                draft.chargedToId = v == me ? null : v;
                onChanged();
              },
            ),
            const SizedBox(height: 12),
            PartyField(
              label: tr('Kis ko dena hai', 'Who to pay'),
              parties: parties,
              value: draft.paidToId,
              allowNone: true,
              noneLabel: tr('Abhi cash de diye', 'Paid cash now'),
              onChanged: (v) {
                draft.paidToId = v;
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows how each khata changes, in plain words, before saving.
class _Preview extends StatelessWidget {
  const _Preview({required this.effects, required this.nameOf});

  final Map<String, num> effects;
  final String Function(String?) nameOf;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Save ke baad khata', 'Ledger after saving'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (effects.isEmpty) Text(tr('Abhi khata mein koi tabdeeli nahi.', 'No change to the ledger yet.')),
            for (final e in effects.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  e.value > 0
                      ? tr('${nameOf(e.key)} se ${money(e.value)} mazeed lena', '${money(e.value)} more to receive from ${nameOf(e.key)}')
                      : tr('${nameOf(e.key)} ko ${money(e.value)} mazeed dena', '${money(e.value)} more to pay ${nameOf(e.key)}'),
                  style: TextStyle(color: KColors.of(context).forBalance(e.value)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
