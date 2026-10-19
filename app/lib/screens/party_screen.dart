import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/khata_text.dart';
import '../ui/common.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../util/format.dart';
import 'deal_screen.dart';
import 'party_form_screen.dart';
import 'payment_screen.dart';
import '../l10n/lang.dart';

/// One party's khata: balance, payment buttons and the running statement.
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
  bool _includeCancelled = false;

  Future<_PartyData> _load() async {
    final repo = Repo.of(context);
    final results = await Future.wait([
      repo.party(widget.partyId),
      repo.statement(widget.partyId, includeCancelled: _includeCancelled),
    ]);
    return _PartyData(results[0] as Party, results[1] as List<KhataLine>);
  }

  void _open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  Future<void> _onLineTap(KhataLine line) async {
    if (line.isBroughtForward) return;
    if (line.dealId != null) return _open(DealScreen(dealId: line.dealId!));
    if (line.expenseId != null) {
      return showDone(context, tr('Yeh line kharchay ki hai. Usay Kharchay tab se cancel karein.', 'This line is an expense. Cancel it from the Expenses tab.'));
    }
    if (line.cancelled) return;
    final repo = Repo.of(context);
    try {
      final reason = await askCancelReason(
        context,
        title: tr('Yeh line cancel karni hai?', 'Cancel this line?'),
        message: '${lineTitle(line)}\n${money(line.amount)} · ${formatDate(line.date)}\n\n'
            '${tr('Ek cancel ki line jurr jayegi; kuch delete nahi hota.', 'A cancelling line will be added; nothing is deleted.')}',
      );
      if (reason == null) return;
      await repo.reverseEntry(line.entryId!, reason: reason);
      if (mounted) showDone(context, tr('Line cancel ho gayi', 'Line cancelled'));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleArchive(Party p) async {
    final archive = !p.archived;
    final ok = await confirm(
      context,
      title: archive ? tr('${p.name} ko archive karna hai?', 'Archive ${p.name}?') : tr('${p.name} ko wapas laana hai?', 'Restore ${p.name}?'),
      message: archive ? tr('Khata mehfooz rahega, lekin nayi entry nahi ho sakegi.', 'The ledger is kept, but no new entries can be made.') : null,
      action: archive ? 'Archive' : tr('Wapas laayein', 'Restore'),
      icon: KIcons.archive,
      danger: archive,
    );
    if (!ok || !mounted) return;
    try {
      await Repo.of(context).setPartyArchived(p.id, archive);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<_PartyData>(
      cacheKey: 'party:${widget.partyId}:$_includeCancelled',
      load: _load,
      skeleton: const SkeletonPage(),
      builder: (context, data, reload) {
        final p = data.party;
        final days = DayGroups<KhataLine>(data.lines.reversed.toList(), (l) => l.date);
        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                tooltip: tr('Aur', 'More'),
                icon: const Icon(KIcons.more),
                onPressed: () async {
                  final v = await showActions<String>(context, title: p.name, actions: [
                    SheetAction('edit', tr('Tafseel badlein', 'Edit details'), KIcons.edit),
                    SheetAction('adjust', tr('Durusti', 'Correction'), KIcons.adjustment),
                    SheetAction('cancelled', tr('Cancel shuda lines dikhayein', 'Show cancelled lines'), KIcons.cancelled,
                        checked: _includeCancelled),
                    SheetAction('archive', p.archived ? tr('Party wapas laayein', 'Restore party') : tr('Party archive karein', 'Archive party'),
                        KIcons.archive, danger: !p.archived),
                  ]);
                  switch (v) {
                    case 'edit':
                      _open(PartyFormScreen(party: p));
                    case 'cancelled':
                      setState(() => _includeCancelled = !_includeCancelled);
                    case 'adjust':
                      _open(PaymentScreen(party: p, mode: PaymentMode.adjustment));
                    case 'archive':
                      _toggleArchive(p);
                  }
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: reload,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: 2 + (days.rows.isEmpty ? 1 : days.rows.length),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _Header(
                    party: p,
                    balance: data.balance,
                    onReceived: () => _open(PaymentScreen(party: p, mode: PaymentMode.received)),
                    onPaid: () => _open(PaymentScreen(party: p, mode: PaymentMode.paid)),
                  );
                }
                if (i == 1) {
                  return SectionTitle(tr('Khata', 'Ledger'), trailing: Text('${data.lines.length} ${tr('lines', 'lines')}  ',
                      style: Theme.of(context).textTheme.labelMedium));
                }
                if (days.rows.isEmpty) {
                  return EmptyState(icon: KIcons.ledger, message: tr('Abhi koi entry nahi.', 'No entries yet.'));
                }
                return days.build(i - 2, (line) => _LineTile(line: line, onTap: () => _onLineTap(line)));
              },
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.party, required this.balance, required this.onReceived, required this.onPaid});

  final Party party;
  final num balance;
  final VoidCallback onReceived;
  final VoidCallback onPaid;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    final p = party;
    final color = k.onInkForBalance(balance);
    final muted = k.onInk.withValues(alpha: 0.72);
    return InkCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PartyAvatar(name: p.name, size: 52, onInk: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: k.onInk, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text([p.type.label, ?p.city, ?p.phone].join(' · '), style: TextStyle(color: muted, fontSize: 13.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(tr('Baqaya', 'Balance'), style: TextStyle(color: muted, fontWeight: FontWeight.w600, fontSize: 13.5)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Amount(balance, color: balance == 0 ? k.onInk : color, size: 34, weight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Tag(balanceLabel(balance), color: balance == 0 ? k.onInk : color),
            ],
          ),
          if (p.archived) ...[
            const SizedBox(height: 14),
            Tag(tr('Archive shuda: nayi entry nahi ho sakti', 'Archived: no new entries'), color: k.denaOnInk),
          ] else ...[
            const SizedBox(height: 20),
            Row(
              children: [
                ActionButton(
                    icon: KIcons.received, label: tr('Paise mile', 'Received'), color: k.lenaOnInk, foreground: k.ink, onTap: onReceived),
                const SizedBox(width: 12),
                ActionButton(icon: KIcons.paid, label: tr('Paise diye', 'Paid'), color: k.denaOnInk, foreground: k.ink, onTap: onPaid),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.onTap});

  final KhataLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    final l = line;
    final details = [
      ?l.method?.label,
      // A deal cost's note is its description, already in the title.
      if (l.kind != 'deal_cost') ?l.note,
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: LineIcon(kind: l.isReversal ? 'reversal' : l.kind, amount: l.amount, cancelled: l.cancelled),
      title: Text(lineTitle(l),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: l.cancelled ? TextStyle(color: k.muted, decoration: TextDecoration.lineThrough) : null),
      subtitle: l.cancelled
          ? Align(alignment: Alignment.centerLeft, child: Tag('Cancel', color: k.dena))
          : (details.isEmpty ? null : Text(details, maxLines: 2, overflow: TextOverflow.ellipsis)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!l.isBroughtForward)
            Amount(l.amount, signed: true, size: 15, color: l.cancelled ? k.muted : k.forBalance(l.amount)),
          Text('${tr('Baqaya', 'Balance')} ${plainNumber(l.balance ?? 0)}',
              style: TextStyle(fontSize: 12, color: k.muted, fontFeatures: tabular)),
        ],
      ),
    );
  }
}
