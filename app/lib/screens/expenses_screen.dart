import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../util/format.dart';
import 'home_screen.dart';

/// The Kharchay tab: business costs that belong to no deal (rent, salary, tea).
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _view = GlobalKey<AsyncViewState<List<Expense>>>();
  bool _showCancelled = false;

  Future<void> _add() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseFormScreen()));
    _view.currentState?.reload();
  }

  Future<void> _cancel(Expense e) async {
    final reason = await askCancelReason(
      context,
      title: 'Yeh kharcha cancel karna hai?',
      message: '${e.category} · ${money(e.amount)} · ${formatDate(e.date)}',
    );
    if (reason == null || !mounted) return;
    try {
      await Repo.of(context).cancelExpense(e.id, reason: reason);
      if (mounted) showDone(context, 'Kharcha cancel ho gaya');
      _view.currentState?.reload();
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repo.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kharchay'),
        actions: [
          IconButton(
            tooltip: _showCancelled ? 'Cancel shuda chhupayein' : 'Cancel shuda dikhayein',
            icon: Icon(_showCancelled ? Icons.visibility : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _showCancelled = !_showCancelled),
          ),
          const AccountMenuButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Naya kharcha'),
      ),
      body: AsyncView<List<Expense>>(
        key: _view,
        load: repo.expenses,
        builder: (context, all, reload) {
          final list = all.where((e) => _showCancelled || !e.cancelled).toList();
          final now = DateTime.now();
          final thisMonth = all
              .where((e) => !e.cancelled && e.date.year == now.year && e.date.month == now.month)
              .fold<num>(0, (s, e) => s + e.amount);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                Card(
                  margin: const EdgeInsets.all(12),
                  child: ListTile(title: const Text('Is mahine'), trailing: Text(money(thisMonth))),
                ),
                if (list.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, message: 'Abhi koi kharcha nahi.'),
                for (final e in list)
                  ListTile(
                    title: Text(e.category,
                        style: e.cancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
                    subtitle: Text([
                      formatDate(e.date),
                      if (e.paidToName != null) '${e.paidToName} ko dena hai',
                      ?e.notes,
                      if (e.cancelled) 'Cancel shuda',
                    ].join(' · ')),
                    trailing: Text(money(e.amount)),
                    onLongPress: e.cancelled ? null : () => _cancel(e),
                    onTap: e.cancelled ? null : () => _cancel(e),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ExpenseFormScreen extends StatelessWidget {
  const ExpenseFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repo.of(context);
    return AsyncView<(List<Party>, List<String>)>(
      load: () async => (await repo.activeParties(), await repo.expenseCategories()),
      builder: (context, data, _) => _ExpenseForm(parties: data.$1, categories: data.$2),
    );
  }
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({required this.parties, required this.categories});

  final List<Party> parties;
  final List<String> categories;

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  static const _defaults = ['Kiraya', 'Tankhwah', 'Bijli', 'Chai pani', 'Phone', 'Transport'];

  String _category = '';
  num? _amount;
  DateTime _date = DateTime.now();
  String? _paidToId;
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_category.trim().isEmpty) return showError(context, 'Likhein kharcha kis cheez ka tha');
    if (_amount == null || _amount! <= 0) return showError(context, 'Raqam likhein');
    setState(() => _saving = true);
    try {
      await Repo.of(context).recordExpense(
        category: _category.trim(),
        amount: _amount!,
        date: _date,
        paidToId: _paidToId,
        notes: _notes.text,
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
    final options = {...widget.categories, ..._defaults}.toList();
    return FormPage(
      title: 'Naya kharcha',
      saving: _saving,
      onSave: _save,
      children: [
        Autocomplete<String>(
          optionsBuilder: (v) => options.where((o) => o.toLowerCase().contains(v.text.toLowerCase())),
          onSelected: (v) => _category = v,
          fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
            controller: controller,
            focusNode: focus,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Kis cheez ka', hintText: 'Kiraya, tankhwah, chai…'),
            onChanged: (v) => _category = v,
          ),
        ),
        NumberField(label: 'Raqam', suffix: 'Rs', onChanged: (v) => _amount = v),
        DateField(value: _date, onChanged: (d) => setState(() => _date = d)),
        PartyField(
          label: 'Kis ko dena hai',
          parties: widget.parties,
          value: _paidToId,
          allowNone: true,
          noneLabel: 'Abhi cash de diye',
          onChanged: (v) => setState(() => _paidToId = v),
        ),
        if (_paidToId != null) const Text('Abhi nahi diye: yeh is party ke dena mein jurr jayega.'),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Note (agar ho)')),
      ],
    );
  }
}
