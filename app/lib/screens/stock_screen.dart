import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../util/format.dart';
import 'deal_screen.dart';
import 'home_screen.dart';
import '../l10n/lang.dart';

/// The Stock tab: kg in stock per cloth type, valued at average cost.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  bool _showArchived = false;

  void _open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final repo = Repo.of(context);
    final k = KColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? tr('Stock archive', 'Stock archive') : 'Stock'),
        actions: [
          ToggleAction(
            label: 'Archive',
            icon: KIcons.archive,
            on: _showArchived,
            onChanged: (v) => setState(() => _showArchived = v),
          ),
          const AccountMenuButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const ItemFormScreen()),
        icon: const Icon(KIcons.add),
        label: Text(tr('Kapre ki qisam', 'Cloth type')),
      ),
      body: AsyncView<List<StockRow>>(
        cacheKey: 'stock',
        load: repo.stockSummary,
        builder: (context, all, reload) {
          final rows = all.where((r) => r.archived == _showArchived).toList();
          final totalKg = rows.fold<num>(0, (s, r) => s + r.weightKg);
          final totalValue = rows.fold<num>(0, (s, r) => s + r.stockValue);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                InkCard(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: OnInkFigure(
                          label: tr('Kul stock', 'Total stock'),
                          value: Text(kg(totalKg),
                              style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.8,
                                  fontFeatures: tabular,
                                  color: totalKg < 0 ? k.denaOnInk : k.onInk)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OnInkFigure(
                        end: true,
                        label: tr('Qeemat', 'Value'),
                        value: Amount(totalValue, size: 17, color: k.onInk),
                      ),
                    ],
                  ),
                ),
                if (rows.isEmpty)
                  EmptyState(
                    icon: KIcons.stock,
                    message: tr('Abhi kapre ki koi qisam nahi.\nJo maal aap bechte hain woh shamil karein, jaise “Purana kapra”.', 'No cloth types yet.\nAdd the goods you trade, like “Used cloth”.'),
                  )
                else
                  Section(
                    title: tr('Kapre ki qisam', 'Cloth type'),
                    children: [
                      for (final r in rows)
                        ListTile(
                          onTap: () => _open(StockItemScreen(row: r)),
                          leading: RowIcon(KIcons.cloth,
                              color: primary, background: primary.withValues(alpha: 0.1)),
                          title: Text(r.item.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(r.avgCost == null ? tr('Abhi koi khareed nahi', 'No purchases yet') : '${tr('Ausat', 'Avg')} ${money(r.avgCost!)}/kg'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(kg(r.weightKg),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: tabular,
                                    color: r.weightKg < 0 ? k.dena : k.text,
                                  )),
                              Text(money(r.stockValue),
                                  style: TextStyle(fontSize: 12, color: k.muted, fontFeatures: tabular)),
                            ],
                          ),
                        ),
                    ],
                  ),
                if (rows.any((r) => r.weightKg < 0))
                  FormHint(
                    tr('Laal stock zero se kam hai: khareed se zyada becha gaya. Shayad koi khareed abhi darj nahi hui.', 'Red stock is below zero: more sold than bought. A purchase may not be entered yet.'),
                    warn: true,
                    margin: EdgeInsets.fromLTRB(16, 12, 16, 0),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One cloth type: kg in hand, stock in / out buttons, and its stock register
/// (every purchase, sale and adjustment, newest first, with kg in hand after it).
class StockItemScreen extends StatefulWidget {
  const StockItemScreen({super.key, required this.row});

  final StockRow row;

  @override
  State<StockItemScreen> createState() => _StockItemScreenState();
}

class _StockItemScreenState extends State<StockItemScreen> {
  Future<(StockRow, List<StockMove>)> _load() async {
    final repo = Repo.of(context);
    final id = widget.row.itemId;
    final results = await Future.wait([repo.stockSummary(), repo.stockHistory(id)]);
    final row = (results[0] as List<StockRow>).where((r) => r.itemId == id).firstOrNull ?? widget.row;
    return (row, results[1] as List<StockMove>);
  }

  void _open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  /// A deal's stock line opens the deal; a stock in / out line can be cancelled.
  Future<void> _onMoveTap(StockMove m) async {
    if (m.dealId != null) return _open(DealScreen(dealId: m.dealId!));
    final repo = Repo.of(context);
    try {
      final reason = await askCancelReason(
        context,
        title: tr('Yeh stock line cancel karni hai?', 'Cancel this stock line?'),
        message: '${stockMoveTitle(m)} · ${kg(m.weightKg.abs())} · ${formatDate(m.date)}',
      );
      if (reason == null) return;
      await repo.cancelStockAdjustment(m.adjustmentId!, reason: reason);
      if (mounted) showDone(context, tr('Stock line cancel ho gayi', 'Stock line cancelled'));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleArchive(StockRow row) async {
    try {
      await Repo.of(context).setItemArchived(row.itemId, !row.archived);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    return AsyncView<(StockRow, List<StockMove>)>(
      cacheKey: 'stock:${widget.row.itemId}',
      load: _load,
      skeleton: const SkeletonPage(),
      builder: (context, data, reload) {
        final (row, moves) = data;
        final days = DayGroups<StockMove>(moves.reversed.toList(), (m) => m.date);
        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                tooltip: tr('Aur', 'More'),
                icon: const Icon(KIcons.more),
                onPressed: () async {
                  final v = await showActions<String>(context, title: row.item.displayName, actions: [
                    SheetAction('edit', tr('Naam badlein', 'Rename'), KIcons.edit),
                    SheetAction('archive', row.archived ? tr('Wapas laayein', 'Restore') : tr('Archive karein', 'Archive'),
                        KIcons.archive, danger: !row.archived),
                  ]);
                  if (v == 'edit') _open(ItemFormScreen(item: row.item));
                  if (v == 'archive') _toggleArchive(row);
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: reload,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: 3 + (days.rows.isEmpty ? 1 : days.rows.length),
              itemBuilder: (context, i) {
                if (i == 0) {
                  final muted = k.onInk.withValues(alpha: 0.72);
                  return InkCard(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          RowIcon(KIcons.cloth, size: 52, color: k.onInk, background: k.onInk.withValues(alpha: 0.14)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(row.item.displayName,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: k.onInk, fontWeight: FontWeight.w800)),
                          ),
                        ]),
                        const SizedBox(height: 22),
                        Text(tr('Haath mein', 'In hand'), style: TextStyle(color: muted, fontWeight: FontWeight.w600, fontSize: 13.5)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(kg(row.weightKg),
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                                fontFeatures: tabular,
                                color: row.weightKg < 0 ? k.denaOnInk : k.onInk,
                              )),
                        ),
                        Text(
                          [money(row.stockValue), if (row.avgCost != null) '${tr('ausat', 'avg')} ${money(row.avgCost!)}/kg'].join(' · '),
                          style: TextStyle(color: muted, fontFeatures: tabular),
                        ),
                        if (!row.archived) ...[
                          const SizedBox(height: 20),
                          Row(children: [
                            ActionButton(
                              icon: KIcons.add,
                              label: tr('Stock aaya', 'Stock in'),
                              color: k.onInk,
                              foreground: k.ink,
                              onTap: () => _open(StockAdjustmentScreen(item: row.item, incoming: true)),
                            ),
                            const SizedBox(width: 12),
                            ActionButton(
                              icon: KIcons.remove,
                              label: tr('Stock gaya', 'Stock out'),
                              color: k.onInk.withValues(alpha: 0.14),
                              foreground: k.onInk,
                              onTap: () => _open(StockAdjustmentScreen(item: row.item, incoming: false)),
                            ),
                          ]),
                        ],
                      ],
                    ),
                  );
                }
                if (i == 1) {
                  return FormHint(
                    tr(
                        'Khareed aur farokht Sauday tab se darj hoti hain. '
                            'Yahan baqi tabdeeli likhein: shuru ka stock, zaya, namoona, ginti ka farq.',
                        'Purchases and sales are entered from the Deals tab. '
                            'Record other changes here: opening stock, waste, samples, count differences.'),
                    margin: EdgeInsets.fromLTRB(16, 12, 16, 0),
                  );
                }
                if (i == 2) return const SectionTitle('Stock register');
                if (days.rows.isEmpty) {
                  return EmptyState(icon: KIcons.stock, message: tr('Abhi koi aamad ya nikasi nahi.', 'No stock in or out yet.'));
                }
                return days.build(i - 3, (m) => _MoveTile(move: m, onTap: () => _onMoveTap(m)));
              },
            ),
          ),
        );
      },
    );
  }
}

/// "Khareed · Rashid" or "Kharab / zaya".
String stockMoveTitle(StockMove m) => switch (m.kind) {
      'purchase' => [DealKind.purchase.label, ?m.partyName].join(' · '),
      'sale' => [DealKind.sale.label, ?m.partyName].join(' · '),
      _ => StockAdjustmentKind.tryParse(m.kind)?.label ?? m.kind,
    };

class _MoveTile extends StatelessWidget {
  const _MoveTile({required this.move, this.onTap});

  final StockMove move;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final m = move;
    final incoming = m.weightKg >= 0;
    final details = [if (m.rate != null) '@ ${plainNumber(m.rate!)}/kg', ?m.reason].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: RowIcon(
        incoming ? KIcons.received : KIcons.paid,
        color: incoming ? primary : k.muted,
        background: incoming ? primary.withValues(alpha: 0.1) : k.paper,
      ),
      title: Text(stockMoveTitle(m), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty ? null : Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${incoming ? '+' : '−'} ${kg(m.weightKg.abs())}',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: tabular, color: k.text)),
          Text('${tr('Baqi', 'Left')} ${kg(m.qtyAfter)}',
              style: TextStyle(fontSize: 12, color: m.qtyAfter < 0 ? k.dena : k.muted, fontFeatures: tabular)),
        ],
      ),
    );
  }
}

class ItemFormScreen extends StatefulWidget {
  const ItemFormScreen({super.key, this.item});

  final Item? item;

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  late final _en = TextEditingController(text: widget.item?.nameEn);
  late final _ur = TextEditingController(text: widget.item?.nameUr);
  bool _saving = false;

  @override
  void dispose() {
    _en.dispose();
    _ur.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_en.text.trim().isEmpty) return showError(context, tr('Naam likhein', 'Enter a name'));
    setState(() => _saving = true);
    final repo = Repo.of(context);
    try {
      if (widget.item == null) {
        await repo.createItem(_en.text.trim(), _ur.text);
      } else {
        await repo.updateItem(widget.item!.id, _en.text.trim(), _ur.text);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: widget.item == null ? tr('Kapre ki nayi qisam', 'New cloth type') : tr('Naam badlein', 'Rename'),
      saving: _saving,
      onSave: _save,
      children: [
        TextField(
          controller: _en,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Naam', 'Name'), hintText: tr('Purana kapra', 'Used cloth')),
        ),
        TextField(
          controller: _ur,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(labelText: tr('Urdu naam (agar ho)', 'Urdu name (optional)'), hintText: 'پرانا کپڑا'),
        ),
      ],
    );
  }
}

/// Stock that came in or went out outside a deal, with the reason as a kind
/// (opening stock, wastage, own use, ...). Stock coming in needs a cost per kg
/// so stock stays valued correctly; stock going out is valued at average cost.
class StockAdjustmentScreen extends StatefulWidget {
  const StockAdjustmentScreen({super.key, required this.item, required this.incoming});

  final Item item;
  final bool incoming;

  @override
  State<StockAdjustmentScreen> createState() => _StockAdjustmentScreenState();
}

class _StockAdjustmentScreenState extends State<StockAdjustmentScreen> {
  late final _kinds = StockAdjustmentKind.values.where((k) => k.isIn == widget.incoming).toList();
  late StockAdjustmentKind _kind = _kinds.first;
  num? _weight;
  num? _cost;
  DateTime _date = DateTime.now();
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_weight == null || _weight! <= 0) return showError(context, tr('Wazan likhein', 'Enter the weight'));
    if (widget.incoming && (_cost == null || _cost! < 0)) return showError(context, tr('Qeemat fi kg likhein', 'Enter the cost per kg'));
    setState(() => _saving = true);
    try {
      await Repo.of(context).recordStockAdjustment(
        itemId: widget.item.id,
        kind: _kind,
        weightKg: _weight!,
        costPerKg: widget.incoming ? _cost : null,
        date: _date,
        reason: _reason.text,
      );
      if (mounted) {
        showDone(context, '${kg(_weight!)} ${widget.incoming ? tr('stock mein jur gaye', 'added to stock') : tr('stock se nikal gaye', 'taken out of stock')}');
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
    return FormPage(
      title: '${widget.item.nameEn}: ${widget.incoming ? tr('stock aaya', 'stock in') : tr('stock gaya', 'stock out')}',
      saving: _saving,
      onSave: _save,
      children: [
        FieldLabel(tr('Kyun?', 'Why?')),
        FilterChips<StockAdjustmentKind>(
          wrap: true,
          options: [for (final k in _kinds) (k, k.label)],
          selected: _kind,
          onSelected: (k) => setState(() => _kind = k),
        ),
        NumberField(label: tr('Wazan', 'Weight'), suffix: 'kg', autofocus: true, onChanged: (v) => _weight = v),
        if (widget.incoming)
          NumberField(
            label: tr('Qeemat fi kg', 'Cost per kg'),
            suffix: 'Rs/kg',
            helper: tr('Yeh maal aap ko kitne ka para, taake munafa sahi aaye', 'What these goods cost you, so profit comes out right'),
            onChanged: (v) => _cost = v,
          )
        else
          FormHint(tr('Yeh maal ausat laagat par nuqsan mein likha jayega.', 'These goods are written off as a loss at average cost.')),
        DateField(value: _date, onChanged: (d) => setState(() => _date = d)),
        TextField(
          controller: _reason,
          decoration: InputDecoration(labelText: tr('Tafseel (agar ho)', 'Details (optional)')),
        ),
      ],
    );
  }
}
