import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../util/format.dart';
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

  Future<void> _rowMenu(StockRow row) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(row.item.displayName), subtitle: Text(kg(row.weightKg))),
            const Divider(height: 1),
            if (!row.archived) ...[
              ListTile(
                leading: const Icon(Icons.add_box_outlined),
                title: const Text('Add stock'),
                subtitle: const Text('Opening stock or stock found'),
                onTap: () => Navigator.pop(context, 'add'),
              ),
              ListTile(
                leading: const Icon(Icons.indeterminate_check_box_outlined),
                title: const Text('Remove stock'),
                subtitle: const Text('Wastage, shortage or damage'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(row.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
              title: Text(row.archived ? 'Restore' : 'Archive'),
              onTap: () => Navigator.pop(context, 'archive'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'add':
        await _open(StockAdjustmentScreen(item: row.item, adding: true));
      case 'remove':
        await _open(StockAdjustmentScreen(item: row.item, adding: false));
      case 'edit':
        await _open(ItemFormScreen(item: row.item));
      case 'archive':
        try {
          await Repo.of(context).setItemArchived(row.itemId, !row.archived);
          _view.currentState?.reload();
        } catch (e) {
          if (mounted) showError(context, e);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repo.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        actions: [
          IconButton(
            tooltip: _showArchived ? 'Hide archived' : 'Show archived',
            icon: Icon(_showArchived ? Icons.inventory : Icons.inventory_outlined),
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
          const AccountMenuButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const ItemFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Cloth type'),
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
                        Expanded(child: Text('Total stock\n${kg(totalKg)}')),
                        Text('Value\n${money(totalValue)}', textAlign: TextAlign.end),
                      ],
                    ),
                  ),
                ),
                if (rows.isEmpty)
                  const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: 'No cloth types yet.\nAdd the types you trade, like “Used cloth” or “Cotton waste”.',
                  ),
                for (final r in rows)
                  ListTile(
                    onTap: () => _rowMenu(r),
                    title: Text(r.item.displayName),
                    subtitle: Text(r.avgCost == null ? 'No purchases yet' : 'Avg cost ${money(r.avgCost!)}/kg'),
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
                    child: Text('Red stock is below zero: more was sold than bought. '
                        'A purchase may not have been entered yet.'),
                  ),
              ],
            ),
          );
        },
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
    if (_en.text.trim().isEmpty) return showError(context, 'Enter a name');
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
      title: widget.item == null ? 'New cloth type' : 'Rename cloth type',
      saving: _saving,
      onSave: _save,
      children: [
        TextField(
          controller: _en,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'Used cloth'),
        ),
        TextField(
          controller: _ur,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(labelText: 'Urdu name (optional)', hintText: 'پرانا کپڑا'),
        ),
      ],
    );
  }
}

/// Stock change outside a deal. Adding needs a cost per kg so stock stays
/// valued correctly; removing is valued at the current average cost.
class StockAdjustmentScreen extends StatefulWidget {
  const StockAdjustmentScreen({super.key, required this.item, required this.adding});

  final Item item;
  final bool adding;

  @override
  State<StockAdjustmentScreen> createState() => _StockAdjustmentScreenState();
}

class _StockAdjustmentScreenState extends State<StockAdjustmentScreen> {
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
    if (_weight == null || _weight! <= 0) return showError(context, 'Enter the weight');
    if (widget.adding && (_cost == null || _cost! < 0)) return showError(context, 'Enter the cost per kg');
    setState(() => _saving = true);
    try {
      await Repo.of(context).recordStockAdjustment(
        itemId: widget.item.id,
        weightKg: widget.adding ? _weight! : -_weight!,
        costPerKg: widget.adding ? _cost : null,
        date: _date,
        reason: _reason.text,
      );
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
      title: '${widget.adding ? 'Add' : 'Remove'} ${widget.item.nameEn}',
      saving: _saving,
      onSave: _save,
      children: [
        NumberField(label: 'Weight', suffix: 'kg', autofocus: true, onChanged: (v) => _weight = v),
        if (widget.adding)
          NumberField(
            label: 'Cost per kg',
            suffix: 'Rs/kg',
            helper: 'What this stock cost you, so profit is right',
            onChanged: (v) => _cost = v,
          ),
        DateField(value: _date, onChanged: (d) => setState(() => _date = d)),
        TextField(
          controller: _reason,
          decoration: InputDecoration(
            labelText: 'Reason (optional)',
            hintText: widget.adding ? 'Opening stock' : 'Wastage',
          ),
        ),
      ],
    );
  }
}
