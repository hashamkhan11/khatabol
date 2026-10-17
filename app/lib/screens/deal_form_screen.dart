import 'package:flutter/material.dart';

import '../data/deal_draft.dart';
import '../data/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../util/format.dart';

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
        showDone(context, widget.editing != null ? 'Sauda badal diya' : 'Sauda save ho gaya');
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
      title: widget.editing != null ? '${d.kind.label} badlein' : 'Nayi ${d.kind.label.toLowerCase()}',
      saving: _saving,
      onSave: _save,
      saveLabel: widget.editing != null ? 'Tabdeeli save karein' : 'Sauda save karein',
      children: [
        DateField(value: d.date, onChanged: (v) => _update(() => d.date = v)),
        PartyField(
          label: switch (d.kind) {
            DealKind.purchase => 'Supplier (jis se khareeda)',
            DealKind.sale => 'Gahak (jis ko becha)',
            DealKind.commission => 'Bechne wala',
          },
          parties: parties,
          value: d.partyId,
          onChanged: (v) => _update(() => d.partyId = v),
        ),
        if (d.isCommission)
          PartyField(
            label: 'Khareedne wala',
            parties: parties,
            value: d.buyerId,
            onChanged: (v) => _update(() => d.buyerId = v),
          ),
        ItemField(
          label: d.isCommission ? 'Kapre ki qisam (agar ho)' : 'Kapre ki qisam',
          items: widget.items,
          value: d.itemId,
          onChanged: (v) => _update(() => d.itemId = v),
        ),
        Row(
          children: [
            Expanded(
              child: NumberField(
                label: d.isCommission ? 'Wazan (agar ho)' : 'Wazan',
                suffix: 'kg',
                initial: d.weightKg,
                onChanged: (v) => _update(() => d.weightKg = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NumberField(
                label: d.isCommission ? 'Rate (agar ho)' : 'Rate',
                suffix: 'Rs/kg',
                initial: d.rate,
                onChanged: (v) => _update(() => d.rate = v),
              ),
            ),
          ],
        ),
        if (d.goodsAmount != null) InfoRow('Maal ki raqam', money(d.goodsAmount!)),
        if (d.isCommission)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Maal ke paise mere zariye'),
            subtitle: const Text('Khareedne wala aap ko deta hai, aap bechne wale ko'),
            value: d.goodsThroughMe,
            onChanged: (v) => _update(() => d.goodsThroughMe = v),
          ),
        if (!d.isCommission) ..._paidNow(),
        if (d.isCommission) ..._commissions(),
        ..._costs(),
        TextFormField(
          initialValue: d.notes,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Note (agar ho)'),
          onChanged: (v) => d.notes = v,
        ),
        _Preview(effects: d.khataEffects(), nameOf: _name),
      ],
    );
  }

  List<Widget> _paidNow() => [
        NumberField(
          label: d.kind == DealKind.purchase ? 'Abhi diye (agar diye)' : 'Abhi mile (agar mile)',
          suffix: 'Rs',
          initial: d.paidNow,
          helper: 'Sab udhaar ho to khali chhorein',
          onChanged: (v) => _update(() => d.paidNow = v),
        ),
        if ((d.paidNow ?? 0) > 0)
          SegmentedButton<PaymentMethod>(
            segments: [for (final m in PaymentMethod.values) ButtonSegment(value: m, label: Text(m.label))],
            selected: {d.paidMethod},
            onSelectionChanged: (s) => _update(() => d.paidMethod = s.first),
          ),
      ];

  List<Widget> _commissions() => [
        SectionTitle(
          'Commission',
          trailing: TextButton.icon(
            onPressed: () => _update(() => d.commissions.add(CommissionDraft())),
            icon: const Icon(Icons.add),
            label: const Text('Aur'),
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
          'Izafi kharchay (kiraya, mazdoori…)',
          trailing: TextButton.icon(
            onPressed: () => _update(() => d.costs.add(CostDraft())),
            icon: const Icon(Icons.add),
            label: const Text('Aur'),
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
                  child: DropdownButtonFormField<String>(
                    initialValue: from.contains(draft.partyId) ? draft.partyId : null,
                    decoration: const InputDecoration(labelText: 'Kis se'),
                    items: [
                      for (final id in from)
                        DropdownMenuItem(
                            value: id, child: Text('${nameOf(id)} (${id == sellerId ? 'bechne wala' : 'khareedne wala'})')),
                    ],
                    onChanged: (v) {
                      draft.partyId = v;
                      onChanged();
                    },
                  ),
                ),
                IconButton(onPressed: onRemove, icon: const Icon(Icons.close), tooltip: 'Hatayein'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<CommissionMode>(
                    initialValue: draft.mode,
                    decoration: const InputDecoration(labelText: 'Kaise'),
                    items: [for (final m in CommissionMode.values) DropdownMenuItem(value: m, child: Text(m.label))],
                    onChanged: (m) {
                      draft.mode = m!;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NumberField(
                    label: 'Miqdar',
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
                    decoration: const InputDecoration(labelText: 'Kis cheez ka', hintText: 'Kiraya, mazdoori…'),
                    onChanged: (v) {
                      draft.description = v;
                      onChanged();
                    },
                  ),
                ),
                IconButton(onPressed: onRemove, icon: const Icon(Icons.close), tooltip: 'Hatayein'),
              ],
            ),
            const SizedBox(height: 12),
            NumberField(
              label: 'Raqam',
              suffix: 'Rs',
              initial: draft.amount,
              onChanged: (v) {
                draft.amount = v;
                onChanged();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: dealParties.contains(draft.chargedToId) ? draft.chargedToId : me,
              decoration: const InputDecoration(labelText: 'Kis ke zimme'),
              items: [
                const DropdownMenuItem(value: me, child: Text('Mere')),
                for (final id in dealParties) DropdownMenuItem(value: id, child: Text(nameOf(id))),
              ],
              onChanged: (v) {
                draft.chargedToId = v == me ? null : v;
                onChanged();
              },
            ),
            const SizedBox(height: 12),
            PartyField(
              label: 'Kis ko dena hai',
              parties: parties,
              value: draft.paidToId,
              allowNone: true,
              noneLabel: 'Abhi cash de diye',
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
            Text('Save ke baad khata', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (effects.isEmpty) const Text('Abhi khata mein koi tabdeeli nahi.'),
            for (final e in effects.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  e.value > 0
                      ? '${nameOf(e.key)} se ${money(e.value)} mazeed lena'
                      : '${nameOf(e.key)} ko ${money(e.value)} mazeed dena',
                  style: TextStyle(color: KColors.of(context).forBalance(e.value)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
