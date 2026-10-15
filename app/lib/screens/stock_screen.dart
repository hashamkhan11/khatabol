import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../util/format.dart';
import 'deal_screen.dart';
import 'home_screen.dart';

/// The Stock tab: kg in stock per cloth type, valued at average cost.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final _view = GlobalKey<AsyncViewState<List<StockRow>>>();
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
        title: const Text('Stock'),
        actions: [
          IconButton(
            tooltip: _showArchived ? 'Archive chhupayein' : 'Archive dikhayein',
            icon: Icon(_showArchived ? Icons.inventory : Icons.inventory_outlined),
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
          const AccountMenuButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const ItemFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Kapre ki qisam'),
      ),
      body: AsyncView<List<StockRow>>(
        key: _view,
        load: repo.stockSummary,
        builder: (context, all, reload) {
          final rows = all.where((r) => r.archived == _showArchived).toList();
          final totalKg = rows.fold<num>(0, (s, r) => s + r.weightKg);
          final totalValue = rows.fold<num>(0, (s, r) => s + r.stockValue);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                Card(
                  margin: const EdgeInsets.all(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(child: Text('Kul stock\n${kg(totalKg)}')),
                        Text('Qeemat\n${money(totalValue)}', textAlign: TextAlign.end),
                      ],
                    ),
                  ),
                ),
                if (rows.isEmpty)
                  const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: 'Abhi kapre ki koi qisam nahi.\nJo maal aap bechte hain woh shamil karein, jaise “Purana kapra”.',
                  ),
                for (final r in rows)
                  ListTile(
                    onTap: () => _open(StockItemScreen(row: r)),
                    title: Text(r.item.displayName),
                    subtitle: Text(r.avgCost == null ? 'Abhi koi khareed nahi' : 'Ausat laagat ${money(r.avgCost!)}/kg'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(kg(r.weightKg),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: r.weightKg < 0 ? AppColors.pay : null,
                            )),
                        Text(money(r.stockValue), style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                if (rows.any((r) => r.weightKg < 0))
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Laal stock zero se kam hai: khareed se zyada becha gaya. '
                        'Shayad koi khareed abhi darj nahi hui.'),
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
  final _view = GlobalKey<AsyncViewState<(StockRow, List<StockMove>)>>();

  Future<(StockRow, List<StockMove>)> _load() async {
    final repo = Repo.of(context);
    final id = widget.row.itemId;
    final results = await Future.wait([repo.stockSummary(), repo.stockHistory(id)]);
    final row = (results[0] as List<StockRow>).where((r) => r.itemId == id).firstOrNull ?? widget.row;
    return (row, results[1] as List<StockMove>);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _view.currentState?.reload();
  }

  Future<void> _toggleArchive(StockRow row) async {
    try {
      await Repo.of(context).setItemArchived(row.itemId, !row.archived);
      _view.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<(StockRow, List<StockMove>)>(
      key: _view,
      load: _load,
      builder: (context, data, reload) {
        final (row, moves) = data;
        return Scaffold(
          appBar: AppBar(
            title: Text(row.item.displayName),
            actions: [
              PopupMenuButton<String>(
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Naam badlein')),
                  PopupMenuItem(value: 'archive', child: Text(row.archived ? 'Wapas laayein' : 'Archive karein')),
                ],
                onSelected: (v) => v == 'edit' ? _open(ItemFormScreen(item: row.item)) : _toggleArchive(row),
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
                              const Text('Haath mein'),
                              Text(kg(row.weightKg),
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: row.weightKg < 0 ? AppColors.pay : null,
                                      )),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(money(row.stockValue)),
                            if (row.avgCost != null) Text('${money(row.avgCost!)}/kg ausat'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (!row.archived)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.receive),
                            onPressed: () => _open(StockAdjustmentScreen(item: row.item, incoming: true)),
                            icon: const Icon(Icons.add),
                            label: const Text('Stock aaya'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.pay),
                            onPressed: () => _open(StockAdjustmentScreen(item: row.item, incoming: false)),
                            icon: const Icon(Icons.remove),
                            label: const Text('Stock gaya'),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text('Khareed aur farokht Sauday tab se darj hoti hain. '
                      'Yahan baqi tabdeeli likhein: shuru ka stock, zaya, namoona, ginti ka farq.'),
                ),
                const SectionTitle('Stock register'),
                if (moves.isEmpty)
                  const EmptyState(icon: Icons.inventory_2_outlined, message: 'Abhi koi aamad ya nikasi nahi.')
                else
                  for (final m in moves.reversed)
                    _MoveTile(
                      move: m,
                      onTap: m.dealId == null ? null : () => _open(DealScreen(dealId: m.dealId!)),
                    ),
              ],
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
    final m = move;
    final incoming = m.weightKg >= 0;
    return ListTile(
      onTap: onTap,
      title: Text(stockMoveTitle(m)),
      subtitle: Text([
        formatDate(m.date),
        if (m.rate != null) '@ ${plainNumber(m.rate!)}',
        ?m.reason,
      ].join(' · ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${incoming ? '+' : '−'} ${kg(m.weightKg.abs())}',
              style: TextStyle(color: incoming ? AppColors.receive : AppColors.pay, fontWeight: FontWeight.w600)),
          Text('Baqi ${kg(m.qtyAfter)}', style: Theme.of(context).textTheme.bodySmall),
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
    if (_en.text.trim().isEmpty) return showError(context, 'Naam likhein');
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
      title: widget.item == null ? 'Kapre ki nayi qisam' : 'Naam badlein',
      saving: _saving,
      onSave: _save,
      children: [
        TextField(
          controller: _en,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Naam', hintText: 'Purana kapra'),
        ),
        TextField(
          controller: _ur,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(labelText: 'Urdu naam (agar ho)', hintText: 'پرانا کپڑا'),
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
    if (_weight == null || _weight! <= 0) return showError(context, 'Wazan likhein');
    if (widget.incoming && (_cost == null || _cost! < 0)) return showError(context, 'Qeemat fi kg likhein');
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
        showDone(context, '${kg(_weight!)} ${widget.incoming ? 'stock mein jur gaye' : 'stock se nikal gaye'}');
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
      title: '${widget.item.nameEn}: ${widget.incoming ? 'stock aaya' : 'stock gaya'}',
      saving: _saving,
      onSave: _save,
      children: [
        const Text('Kyun?'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final k in _kinds)
              ChoiceChip(label: Text(k.label), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
          ],
        ),
        NumberField(label: 'Wazan', suffix: 'kg', autofocus: true, onChanged: (v) => _weight = v),
        if (widget.incoming)
          NumberField(
            label: 'Qeemat fi kg',
            suffix: 'Rs/kg',
            helper: 'Yeh maal aap ko kitne ka para, taake munafa sahi aaye',
            onChanged: (v) => _cost = v,
          )
        else
          const Text('Yeh maal ausat laagat par nuqsan mein likha jayega.'),
        DateField(value: _date, onChanged: (d) => setState(() => _date = d)),
        TextField(
          controller: _reason,
          decoration: const InputDecoration(labelText: 'Tafseel (agar ho)'),
        ),
      ],
    );
  }
}
