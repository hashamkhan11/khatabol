import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/ledger_repository.dart';
import '../data/models.dart';
import '../util/format.dart';

/// Gives every screen the same repository.
class Repo extends InheritedWidget {
  const Repo({super.key, required this.repository, required super.child});

  final LedgerRepository repository;

  /// The repository never changes, so no rebuild dependency is registered.
  /// That also makes this safe to call from callbacks and loaders.
  static LedgerRepository of(BuildContext context) => context.getInheritedWidgetOfExactType<Repo>()!.repository;

  @override
  bool updateShouldNotify(Repo oldWidget) => repository != oldWidget.repository;
}

class AppColors {
  static const receive = Color(0xFF1B7F3B); // they owe us
  static const pay = Color(0xFFC62828); // we owe them
}

Color balanceColor(num balance) =>
    balance > 0 ? AppColors.receive : (balance < 0 ? AppColors.pay : Colors.grey);

/// Turns a database or network error into a sentence for the user.
/// Database functions raise plain-English messages, so those are shown as is.
String errorText(Object error) {
  if (error is PostgrestException) return _capitalise(error.message);
  if (error is AuthException) return error.message;
  final s = error.toString();
  if (s.contains('SocketException') || s.contains('ClientException')) {
    return 'No internet connection. Check your connection and try again.';
  }
  return s;
}

String _capitalise(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(errorText(error)), backgroundColor: AppColors.pay),
  );
}

void showDone(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Loads data with [load], shows a spinner, an error with retry, or [builder].
/// Call [AsyncViewState.reload] (via a GlobalKey) to refresh.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<AsyncView<T>> createState() => AsyncViewState<T>();
}

class AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future = widget.load();

  Future<void> reload() async {
    final next = widget.load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorRetry(message: errorText(snap.error!), onRetry: reload);
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return widget.builder(context, snap.data as T, reload);
      },
    );
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// A balance with its meaning: "Rs 40,000" over "You owe".
class BalanceText extends StatelessWidget {
  const BalanceText(this.balance, {super.key, this.large = false});

  final num balance;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final color = balanceColor(balance);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(money(balance),
            style: (large ? theme.headlineSmall : theme.titleMedium)?.copyWith(color: color, fontWeight: FontWeight.w600)),
        Text(balanceLabel(balance), style: theme.labelSmall?.copyWith(color: color)),
      ],
    );
  }
}

/// Asks a yes/no question. Returns true when confirmed.
Future<bool> confirm(BuildContext context, {required String title, String? message, String action = 'OK'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

/// Asks for an optional reason before cancelling something.
/// Returns null if the user backed out, or the reason (possibly empty).
Future<String?> askCancelReason(BuildContext context, {required String title, required String message}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Reason (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.pay),
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Cancel it'),
        ),
      ],
    ),
  );
}

/// A form field showing a date that opens a date picker.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.value, required this.onChanged, this.label = 'Date'});

  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today, size: 18)),
        child: Text(formatDate(value)),
      ),
    );
  }
}

/// A number input. Shows the value with thousands separators as the user types.
class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.onChanged,
    this.initial,
    this.suffix,
    this.helper,
    this.allowNegative = false,
    this.autofocus = false,
  });

  final String label;
  final ValueChanged<num?> onChanged;
  final num? initial;
  final String? suffix;
  final String? helper;
  final bool allowNegative;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initial == null ? null : plainNumber(initial!).replaceAll(',', ''),
      autofocus: autofocus,
      keyboardType: TextInputType.numberWithOptions(decimal: true, signed: allowNegative),
      decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: helper),
      onChanged: (s) => onChanged(parseNumber(s)),
    );
  }
}

/// Picks one party from a searchable list.
class PartyField extends StatelessWidget {
  const PartyField({
    super.key,
    required this.label,
    required this.parties,
    required this.value,
    required this.onChanged,
    this.allowNone = false,
    this.noneLabel = 'None',
  });

  final String label;
  final List<Party> parties;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowNone;
  final String noneLabel;

  @override
  Widget build(BuildContext context) {
    final selected = parties.where((p) => p.id == value).firstOrNull;
    return InkWell(
      onTap: () async {
        final picked = await showModalBottomSheet<_Pick>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _PartyPicker(parties: parties, allowNone: allowNone, noneLabel: noneLabel),
        );
        if (picked != null) onChanged(picked.id);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.arrow_drop_down)),
        child: Text(selected?.name ?? (allowNone ? noneLabel : 'Choose…'),
            style: selected == null ? TextStyle(color: Theme.of(context).hintColor) : null),
      ),
    );
  }
}

class _Pick {
  const _Pick(this.id);
  final String? id;
}

class _PartyPicker extends StatefulWidget {
  const _PartyPicker({required this.parties, required this.allowNone, required this.noneLabel});

  final List<Party> parties;
  final bool allowNone;
  final String noneLabel;

  @override
  State<_PartyPicker> createState() => _PartyPickerState();
}

class _PartyPickerState extends State<_PartyPicker> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final q = _search.toLowerCase();
    final list = widget.parties.where((p) => p.name.toLowerCase().contains(q)).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search parties'),
                onChanged: (s) => setState(() => _search = s),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (widget.allowNone)
                    ListTile(title: Text(widget.noneLabel), onTap: () => Navigator.pop(context, const _Pick(null))),
                  for (final p in list)
                    ListTile(
                      title: Text(p.name),
                      subtitle: Text([p.type.label, ?p.city].join(' · ')),
                      onTap: () => Navigator.pop(context, _Pick(p.id)),
                    ),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No party found. Add it from the Khata tab first.', textAlign: TextAlign.center),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks one cloth type.
class ItemField extends StatelessWidget {
  const ItemField({super.key, required this.items, required this.value, required this.onChanged, this.label = 'Cloth type'});

  final List<Item> items;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: items.any((i) => i.id == value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: items.isEmpty ? 'Add cloth types in the Stock tab first' : null,
      ),
      items: [for (final i in items) DropdownMenuItem(value: i.id, child: Text(i.displayName))],
      onChanged: onChanged,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A label-value row used on detail screens.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueStyle});

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          const SizedBox(width: 16),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: valueStyle)),
        ],
      ),
    );
  }
}

/// Wraps a form in a scrollable page with a full-width save button at the bottom.
class FormPage extends StatelessWidget {
  const FormPage({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    required this.saving,
    this.saveLabel = 'Save',
    this.actions,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final bool saving;
  final String saveLabel;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving ? null : onSave,
                  child: saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(saveLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
