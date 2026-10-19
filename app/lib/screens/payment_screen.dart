import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../util/format.dart';
import '../l10n/lang.dart';

enum PaymentMode { received, paid, adjustment }

/// Money received from or paid to a party, or a manual correction.
/// Payments go against the party's running khata, not a single bill.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.party, required this.mode});

  final Party party;
  final PaymentMode mode;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  num? _amount;
  DateTime _date = DateTime.now();
  PaymentMethod _method = PaymentMethod.cash;
  final _note = TextEditingController();
  bool _owesMore = true; // adjustment direction
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_amount == null || _amount! <= 0) return showError(context, tr('Raqam likhein', 'Enter the amount'));
    if (widget.mode == PaymentMode.adjustment && _note.text.trim().isEmpty) {
      return showError(context, tr('Durusti ki wajah likhein', 'Write the reason for the correction'));
    }
    setState(() => _saving = true);
    final repo = Repo.of(context);
    try {
      if (widget.mode == PaymentMode.adjustment) {
        await repo.recordAdjustment(
          partyId: widget.party.id,
          amount: _owesMore ? _amount! : -_amount!,
          note: _note.text.trim(),
          date: _date,
        );
      } else {
        await repo.recordPayment(
          partyId: widget.party.id,
          received: widget.mode == PaymentMode.received,
          amount: _amount!,
          date: _date,
          method: _method,
          note: _note.text,
        );
      }
      if (mounted) {
        showDone(context, tr('${money(_amount!)} save ho gaye', '${money(_amount!)} saved'));
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
    final name = widget.party.name;
    final title = switch (widget.mode) {
      PaymentMode.received => tr('$name se paise mile', 'Received from $name'),
      PaymentMode.paid => tr('$name ko paise diye', 'Paid to $name'),
      PaymentMode.adjustment => tr('$name ke hisaab mein durusti', 'Correct $name\'s balance'),
    };
    return FormPage(
      title: title,
      saving: _saving,
      onSave: _save,
      children: [
        if (widget.mode == PaymentMode.adjustment)
          FormHint(tr(
              'Sirf hisaab ki ghalti theek karne ke liye; munafa par asar nahi hota. '
                  'Rate kam hua ya maal wapas aaya? Sauday mein ja kar "Badlein" karein, '
                  'taake munafa aur stock bhi sahi rahein.',
              'Only for fixing a mistake in the balance; it does not affect profit. '
                  'Rate dropped or goods returned? Open the deal and tap "Edit", '
                  'so profit and stock stay right too.')),
        if (widget.mode == PaymentMode.adjustment)
          Segments<bool>(
            options: [
              (true, tr('$name se lena barhe', 'More to receive from $name')),
              (false, tr('Mera dena barhe', 'More for me to pay')),
            ],
            selected: _owesMore,
            onChanged: (v) => setState(() => _owesMore = v),
          ),
        NumberField(label: tr('Raqam', 'Amount'), suffix: 'Rs', autofocus: true, onChanged: (v) => _amount = v),
        DateField(value: _date, onChanged: (d) => setState(() => _date = d)),
        if (widget.mode != PaymentMode.adjustment)
          Segments<PaymentMethod>(
            options: [for (final m in PaymentMethod.values) (m, m.label)],
            selected: _method,
            onChanged: (m) => setState(() => _method = m),
          ),
        TextField(
          controller: _note,
          decoration: InputDecoration(
            labelText: widget.mode == PaymentMode.adjustment ? tr('Wajah', 'Reason') : tr('Note (agar ho)', 'Note (optional)'),
          ),
        ),
      ],
    );
  }
}
