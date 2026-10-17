import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/ledger_repository.dart';
import '../data/models.dart';
import '../util/format.dart';
import 'theme.dart';

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

/// Turns a database or network error into a sentence for the user.
/// Database functions raise plain-English messages; the common ones are shown
/// in Roman Urdu, the rest as they are.
String errorText(Object error) {
  if (error is PostgrestException) return _dbMessages[error.message] ?? _capitalise(error.message);
  if (error is AuthException) return error.message;
  final s = error.toString();
  if (s.contains('SocketException') || s.contains('ClientException')) {
    return 'Internet nahi chal raha. Connection check kar ke dobara koshish karein.';
  }
  return s;
}

const _dbMessages = {
  'party not found': 'Party nahi mili',
  'cloth type not found': 'Kapre ki qisam nahi mili',
  'deal not found': 'Sauda nahi mila',
  'entry not found': 'Line nahi mili',
  'seller and buyer must be different parties': 'Bechne wala aur khareedne wala alag hon',
  'record payments for commission deals separately': 'Commission sauday ki payment alag se darj karein',
  'payment amount must be positive': 'Raqam zero se zyada honi chahiye',
  'paid_now cannot be negative': 'Abhi di gayi raqam manfi nahi ho sakti',
  'weight must be positive': 'Wazan zero se zyada hona chahiye',
  'stock coming in needs a cost per kg': 'Aane wale stock ki qeemat fi kg likhein',
  'deal is already cancelled': 'Yeh sauda pehle hi cancel ho chuka hai',
  'entry is already cancelled': 'Yeh line pehle hi cancel ho chuki hai',
  'expense not found or already cancelled': 'Kharcha nahi mila ya pehle hi cancel hai',
  'this line belongs to a deal or expense; cancel that instead': 'Yeh line sauday ya kharchay ki hai; usay cancel karein',
  'a cancellation cannot be cancelled; record the entry again instead': 'Cancel ko cancel nahi kar sakte; line dobara darj karein',
  'an adjustment needs a note explaining it': 'Durusti ki wajah likhein',
  'adjustment amount cannot be zero': 'Raqam zero nahi ho sakti',
  'Not signed in': 'Pehle sign in karein',
  'settle the khata before archiving this party': 'Pehle hisaab barabar karein, phir party archive hogi',
  'stock must be zero before archiving this cloth type': 'Pehle stock zero karein, phir archive hoga',
  'stock adjustment not found or already cancelled': 'Stock ki line nahi mili ya pehle hi cancel hai',
};

String _capitalise(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(errorText(error)), backgroundColor: KColors.of(context).dena));
}

void showDone(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// "Aaj", "Kal" or the date, for grouping lists by day.
String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Aaj';
  if (diff == 1) return 'Kal';
  return formatDate(day);
}

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

/// Loads data with [load] and shows it with [builder].
///
/// With a [cacheKey] the last result is remembered: opening the screen again
/// shows it at once while fresh data loads quietly. The view also refreshes
/// by itself after any change to the khata (see [LedgerRepository.changes]);
/// a view that is not on screen waits until it is shown.
/// Call [AsyncViewState.reload] (via a GlobalKey) to refresh by hand.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder, this.cacheKey, this.skeleton});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final String? cacheKey;

  /// Shown on the very first load; grey placeholder rows by default.
  final Widget? skeleton;

  @override
  State<AsyncView<T>> createState() => AsyncViewState<T>();
}

class AsyncViewState<T> extends State<AsyncView<T>> {
  late final LedgerRepository _repo;
  T? _data;
  bool _hasData = false;
  Object? _error;
  int _ticket = 0;
  bool _visible = true;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    _repo = Repo.of(context);
    _takeCached();
    _repo.changes.addListener(_onChanged);
    _fetch();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.of(context);
    if (_visible && _stale) _fetch();
  }

  @override
  void didUpdateWidget(AsyncView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) {
      _hasData = false;
      _takeCached();
      _fetch();
    }
  }

  @override
  void dispose() {
    _repo.changes.removeListener(_onChanged);
    super.dispose();
  }

  void _takeCached() {
    final key = widget.cacheKey;
    if (key == null) return;
    final cached = _repo.cache[key];
    if (cached is T) {
      _data = cached;
      _hasData = true;
    }
  }

  void _onChanged() {
    if (!mounted) return;
    if (_visible) {
      _fetch();
    } else {
      _stale = true;
    }
  }

  Future<void> reload() => _fetch();

  Future<void> _fetch() async {
    final ticket = ++_ticket;
    _stale = false;
    try {
      final value = await widget.load();
      if (!mounted || ticket != _ticket) return;
      if (widget.cacheKey != null) _repo.cache[widget.cacheKey!] = value;
      setState(() {
        _data = value;
        _hasData = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted || ticket != _ticket) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      if (_error != null) return ErrorRetry(message: errorText(_error!), onRetry: reload);
      return widget.skeleton ?? const SkeletonList();
    }
    final content = widget.builder(context, _data as T, reload);
    if (_error == null) return content;
    // Fresh data failed to load: keep showing what we have, and say so.
    return Stack(
      children: [
        content,
        Positioned(left: 16, right: 16, bottom: 16, child: SafeArea(child: _OfflineBar(onRetry: reload))),
      ],
    );
  }
}

class _OfflineBar extends StatelessWidget {
  const _OfflineBar({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1C2033),
      borderRadius: BorderRadius.circular(14),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.white70, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Internet nahi. Purana hisaab dikh raha hai.',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            TextButton(onPressed: onRetry, child: const Text('Dobara', style: TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }
}

/// Grey placeholder rows shown while a screen loads for the first time.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.header = false, this.rows = 7});

  /// A big block on top, like the dashboard summary.
  final bool header;
  final int rows;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: k.line, borderRadius: BorderRadius.circular(6)),
        );
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_pulse),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          if (widget.header) ...[
            Container(height: 168, decoration: BoxDecoration(color: k.line, borderRadius: BorderRadius.circular(22))),
            const SizedBox(height: 24),
          ],
          Container(
            decoration: BoxDecoration(color: k.surface, borderRadius: BorderRadius.circular(18)),
            child: Column(
              children: [
                for (var i = 0; i < widget.rows; i++)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(width: 40, height: 40, decoration: BoxDecoration(color: k.line, shape: BoxShape.circle)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [bar(130, 13), const SizedBox(height: 8), bar(80, 10)],
                          ),
                        ),
                        bar(64, 15),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A whole-page placeholder, for detail screens whose app bar needs the data.
class SkeletonPage extends StatelessWidget {
  const SkeletonPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(), body: const SkeletonList(header: true, rows: 5));
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: KColors.of(context).muted),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 20),
            SizedBox(width: 200, child: FilledButton.tonal(onPressed: onRetry, child: const Text('Dobara koshish'))),
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
    final k = KColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: k.surface, shape: BoxShape.circle),
            child: Icon(icon, size: 32, color: k.muted),
          ),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: k.muted, height: 1.4)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

/// Rupees with equal-width digits, so columns of amounts line up.
class Amount extends StatelessWidget {
  const Amount(this.value, {super.key, this.color, this.size = 16, this.weight = FontWeight.w700, this.signed = false});

  final num value;
  final Color? color;
  final double size;
  final FontWeight weight;

  /// "+ 40,000" / "− 40,000" instead of "Rs 40,000".
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final text = signed ? '${value >= 0 ? '+' : '−'} ${plainNumber(value.abs())}' : money(value);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? KColors.of(context).text,
        fontFeatures: tabular,
        letterSpacing: size > 22 ? -0.8 : -0.2,
      ),
    );
  }
}

/// A balance with its meaning: "Rs 40,000" over "Dena hai".
class BalanceText extends StatelessWidget {
  const BalanceText(this.balance, {super.key, this.large = false});

  final num balance;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = KColors.of(context).forBalance(balance);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Amount(balance, color: color, size: large ? 30 : 16, weight: large ? FontWeight.w800 : FontWeight.w700),
        Text(balanceLabel(balance), style: TextStyle(fontSize: large ? 14 : 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

/// "Kul lena" and "Kul dena" side by side: what all parties owe us and what we owe them.
class TotalsRow extends StatelessWidget {
  const TotalsRow({super.key, required this.toReceive, required this.toPay});

  final num toReceive;
  final num toPay;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    Widget half(String label, num amount, Color color) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                ]),
                const SizedBox(height: 2),
                Amount(amount, color: color, size: 19, weight: FontWeight.w800),
              ],
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      decoration: BoxDecoration(color: k.surface, borderRadius: BorderRadius.circular(18)),
      child: IntrinsicHeight(
        child: Row(children: [
          half('Kul lena', toReceive, k.lena),
          VerticalDivider(width: 1, indent: 14, endIndent: 14, color: k.line),
          half('Kul dena', toPay, k.dena),
        ]),
      ),
    );
  }
}

/// A round badge with a party's initials, tinted by which way the money goes.
class PartyAvatar extends StatelessWidget {
  const PartyAvatar({super.key, required this.name, this.balance = 0, this.size = 40});

  final String name;
  final num balance;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = switch (words.length) {
      0 => '?',
      1 => words[0].characters.first,
      _ => words[0].characters.first + words[1].characters.first,
    }
        .toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: k.softForBalance(balance), shape: BoxShape.circle),
      child: Text(initials,
          style: TextStyle(
            fontSize: size * 0.36,
            fontWeight: FontWeight.w800,
            color: k.forBalance(balance),
          )),
    );
  }
}

/// A round icon badge for a list row.
class RowIcon extends StatelessWidget {
  const RowIcon(this.icon, {super.key, required this.color, required this.background, this.size = 40});

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.5, color: color),
      );
}

/// A neutral round icon badge.
class RowIconPlain extends StatelessWidget {
  const RowIconPlain(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    return RowIcon(icon, color: k.muted, background: k.paper);
  }
}

/// A small rounded label, e.g. "Cancel" or "Udhaar".
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    final c = color ?? k.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

/// A titled group of rows on one white panel, with hairlines between rows.
class Section extends StatelessWidget {
  const Section({super.key, this.title, this.trailing, required this.children, this.dividerIndent = 72});

  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  /// Where the hairline between rows starts; lines up with the row text.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) SectionTitle(title!, trailing: trailing) else const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: k.surface, borderRadius: BorderRadius.circular(18)),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(indent: dividerIndent, height: 1),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
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
      padding: EdgeInsets.fromLTRB(20, 24, trailing == null ? 20 : 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 15.5, letterSpacing: -0.1)),
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
    final k = KColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: TextStyle(color: k.muted, fontSize: 15))),
          const SizedBox(width: 16),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: tabular, color: k.text)
                    .merge(valueStyle)),
          ),
        ],
      ),
    );
  }
}

/// A big two-up action button, e.g. "Paise mile" / "Paise diye".
class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
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
    this.saveLabel = 'Save karein',
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
    final k = KColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 14), child: c),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(color: k.paper, border: Border(top: BorderSide(color: k.line))),
              child: FilledButton(
                onPressed: saving ? null : onSave,
                child: saving
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                    : Text(saveLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

/// Asks a yes/no question. Returns true when confirmed.
Future<bool> confirm(BuildContext context, {required String title, String? message, String action = 'OK'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message, style: const TextStyle(height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Wapas')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Asks for an optional reason before cancelling something.
/// Returns null if the user backed out, or the reason (possibly empty).
Future<String?> askCancelReason(BuildContext context, {required String title, required String message}) {
  final controller = TextEditingController();
  final k = KColors.of(context);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 16),
          TextField(controller: controller, decoration: const InputDecoration(labelText: 'Wajah (agar ho)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Wapas')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: k.dena, foregroundColor: Colors.white, minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Cancel karein'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Form fields
// ---------------------------------------------------------------------------

/// A form field showing a date that opens a date picker.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.value, required this.onChanged, this.label = 'Tareekh'});

  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final day = dayLabel(value);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
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
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_month_rounded, size: 20)),
        child: Text(day == formatDate(value) ? day : '$day · ${formatDate(value)}'),
      ),
    );
  }
}

/// A number input with equal-width digits.
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
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, fontFeatures: tabular),
      decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: helper, helperMaxLines: 3),
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
    this.noneLabel = 'Koi nahi',
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
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await showModalBottomSheet<_Pick>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _PartyPicker(parties: parties, allowNone: allowNone, noneLabel: noneLabel),
        );
        if (picked != null) onChanged(picked.id);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.expand_more_rounded)),
        child: Text(selected?.name ?? (allowNone ? noneLabel : 'Chunein…'),
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Party talaash karein'),
                onChanged: (s) => setState(() => _search = s),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (widget.allowNone)
                    ListTile(
                      leading: const RowIconPlain(Icons.payments_outlined),
                      title: Text(widget.noneLabel),
                      onTap: () => Navigator.pop(context, const _Pick(null)),
                    ),
                  for (final p in list)
                    ListTile(
                      leading: PartyAvatar(name: p.name),
                      title: Text(p.name),
                      subtitle: Text([p.type.label, ?p.city].join(' · ')),
                      onTap: () => Navigator.pop(context, _Pick(p.id)),
                    ),
                  if (list.isEmpty)
                    const EmptyState(
                      icon: Icons.person_search_rounded,
                      message: 'Koi party nahi mili. Pehle Khata tab se party banayein.',
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
  const ItemField({super.key, required this.items, required this.value, required this.onChanged, this.label = 'Kapre ki qisam'});

  final List<Item> items;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: items.any((i) => i.id == value) ? value : null,
      borderRadius: BorderRadius.circular(14),
      icon: const Icon(Icons.expand_more_rounded),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: items.isEmpty ? 'Pehle Stock tab mein kapre ki qisam banayein' : null,
      ),
      items: [for (final i in items) DropdownMenuItem(value: i.id, child: Text(i.displayName, overflow: TextOverflow.ellipsis))],
      onChanged: onChanged,
    );
  }
}

// ---------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------

/// A party in a list: initials, name, type and city, and its balance.
class PartyTile extends StatelessWidget {
  const PartyTile({super.key, required this.party, required this.onTap, this.showLastEntry = false});

  final PartyBalance party;
  final VoidCallback onTap;
  final bool showLastEntry;

  static String _lastEntry(DateTime d) {
    final day = dayLabel(d);
    return day == formatDate(d) ? 'akhri ${formatShortDate(d)}' : day.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    final p = party;
    return ListTile(
      leading: PartyAvatar(name: p.name, balance: p.balance),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          [
            p.type.label,
            ?p.city,
            if (p.archived) 'Archived',
            if (showLastEntry && p.lastEntryDate != null) _lastEntry(p.lastEntryDate!),
          ].join(' · '),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: p.balance == 0
          ? Text('Barabar', style: TextStyle(color: k.muted, fontWeight: FontWeight.w600))
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Amount(p.balance, color: k.forBalance(p.balance)),
                Text(balanceLabel(p.balance),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: k.forBalance(p.balance))),
              ],
            ),
      onTap: onTap,
    );
  }
}

/// The icon for a khata line, by what kind of entry it is, tinted by which
/// way it moved the balance.
class LineIcon extends StatelessWidget {
  const LineIcon({super.key, required this.kind, required this.amount, this.cancelled = false});

  final String? kind;
  final num amount;
  final bool cancelled;

  static IconData iconFor(String? kind) => switch (kind) {
        'purchase' => Icons.move_to_inbox_rounded,
        'sale' => Icons.local_shipping_outlined,
        'commission' => Icons.handshake_outlined,
        'payment_in' => Icons.south_west_rounded,
        'payment_out' => Icons.north_east_rounded,
        'expense' || 'deal_cost' => Icons.receipt_long_outlined,
        'adjustment' => Icons.tune_rounded,
        'reversal' => Icons.undo_rounded,
        _ => Icons.history_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    if (cancelled) return RowIcon(iconFor(kind), color: k.muted, background: k.paper);
    return RowIcon(iconFor(kind), color: k.forBalance(amount), background: k.softForBalance(amount));
  }
}

/// One row of a white grouped panel, for long lists built lazily
/// (ListView.builder): the first and last rows round the panel's corners.
class GroupedRow extends StatelessWidget {
  const GroupedRow({super.key, required this.first, required this.last, required this.child, this.dividerIndent = 72});

  final bool first;
  final bool last;
  final Widget child;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    const r = Radius.circular(18);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: k.surface,
        borderRadius: BorderRadius.vertical(top: first ? r : Radius.zero, bottom: last ? r : Radius.zero),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [if (!first) Divider(indent: dividerIndent, height: 1), child],
        ),
      ),
    );
  }
}

/// A row of filter chips that scrolls sideways when it does not fit.
class FilterChips<T> extends StatelessWidget {
  const FilterChips({super.key, required this.options, required this.selected, required this.onSelected});

  /// Value and label for each chip.
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final (value, label) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: value == selected,
                onSelected: (_) => onSelected(value),
              ),
            ),
        ],
      ),
    );
  }
}

/// A list split into days, newest first: each day's label ("Aaj", "Kal",
/// "3 Oct 2026") followed by its items, ready for a lazy ListView.builder.
class DayGroups<T> {
  DayGroups(List<T> items, DateTime Function(T) dateOf) {
    String? last;
    for (final item in items) {
      final label = dayLabel(dateOf(item));
      if (label != last) {
        rows.add(label);
        last = label;
      }
      rows.add(item);
    }
  }

  /// Day labels (String) and items (T), in order.
  final rows = <Object?>[];

  bool isFirst(int i) => i == 0 || rows[i - 1] is String;
  bool isLast(int i) => i == rows.length - 1 || rows[i + 1] is String;

  /// The day label or the item at [i], laid out as a grouped panel row.
  Widget build(int i, Widget Function(T item) tile) {
    final row = rows[i];
    if (row is String) return _DayLabel(row);
    return GroupedRow(first: isFirst(i), last: isLast(i), child: tile(row as T));
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text(text,
          style: TextStyle(
              color: KColors.of(context).muted, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
    );
  }
}

/// A short explanation on a screen or form, quieter than the content around it.
class FormHint extends StatelessWidget {
  const FormHint(this.text, {super.key, this.warn = false, this.margin = EdgeInsets.zero});

  final String text;
  final bool warn;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final k = KColors.of(context);
    final color = warn ? k.dena : k.muted;
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: warn ? k.denaSoft : k.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(warn ? Icons.error_outline_rounded : Icons.info_outline_rounded, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, height: 1.4, fontSize: 14))),
        ],
      ),
    );
  }
}

/// A small label above a group of form controls.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: KColors.of(context).muted)),
      );
}
