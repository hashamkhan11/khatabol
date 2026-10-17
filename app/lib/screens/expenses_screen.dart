import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../util/format.dart';
import 'home_screen.dart';

/// The Kharchay tab: business costs that belong to no deal (rent, salary, tea).
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  bool _showCancelled = false;

  void _add() => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseFormScreen()));

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
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repo.of(context);
    final k = KColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kharchay'),
        actions: [
          IconButton(
            tooltip: _showCancelled ? 'Cancel shuda chhupayein' : 'Cancel shuda dikhayein',
            icon: Icon(_showCancelled ? Icons.visibility_rounded : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _showCancelled = !_showCancelled),
          ),
          const AccountMenuButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Naya kharcha'),
      ),
      body: AsyncView<List<Expense>>(
        cacheKey: 'expenses',
        load: repo.expenses,
        builder: (context, all, reload) {
          final list = all.where((e) => _showCancelled || !e.cancelled).toList();
          final days = DayGroups<Expense>(list, (e) => e.date);
          final now = DateTime.now();
          final live = all.where((e) => !e.cancelled);
          final thisMonth =
              live.where((e) => e.date.year == now.year && e.date.month == now.month).fold<num>(0, (s, e) => s + e.amount);
          final lastMonthStart = DateTime(now.year, now.month - 1);
          final lastMonth = live
              .where((e) => e.date.year == lastMonthStart.year && e.date.month == lastMonthStart.month)
              .fold<num>(0, (s, e) => s + e.amount);

          final header = Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: BoxDecoration(color: k.surface, borderRadius: BorderRadius.circular(22)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Is mahine', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Amount(thisMonth, size: 30, weight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Pichle mahine', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 2),
                    Amount(lastMonth, size: 16, color: k.muted),
                  ],
                ),
              ],
            ),
          );

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: 1 + (list.isEmpty ? 1 : days.rows.length),
              itemBuilder: (context, i) {
                if (i == 0) return header;
                if (list.isEmpty) {
                  return const EmptyState(icon: Icons.receipt_long_outlined, message: 'Abhi koi kharcha nahi.');
                }
                return days.build(i - 1, (e) => _ExpenseTile(expense: e, onTap: e.cancelled ? null : () => _cancel(e)));
              },
            ),
          );
        },
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.expense, this.onTap});

  final Expense expense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    final e = expense;
    final details = [if (e.paidToName != null) '${e.paidToName} ko dena hai' else 'Cash', ?e.notes].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: e.cancelled ? const RowIconPlain(Icons.receipt_long_outlined) : RowIcon(
        Icons.receipt_long_outlined,
        color: k.dena,
        background: k.denaSoft,
      ),
      title: Text(e.category,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: e.cancelled ? TextStyle(decoration: TextDecoration.lineThrough, color: k.muted) : null),
      subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: e.cancelled ? Tag('Cancel', color: k.dena) : Amount(e.amount, size: 15),
    );
  }
}

class ExpenseFormScreen extends StatelessWidget {
  const ExpenseFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repo.of(context);
    return AsyncView<(List<Party>, List<String>)>(
      cacheKey: 'expense-form',
      skeleton: const SkeletonPage(),
      load: () async {
        final (parties, categories) = await (repo.activeParties(), repo.expenseCategories()).wait;
        return (parties, categories);
      },
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
        if (_paidToId != null) const FormHint('Abhi nahi diye: yeh is party ke dena mein jurr jayega.'),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Note (agar ho)')),
      ],
    );
  }
}
