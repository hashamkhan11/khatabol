import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../util/format.dart';

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
    if (_amount == null || _amount! <= 0) return showError(context, 'Raqam likhein');
    if (widget.mode == PaymentMode.adjustment && _note.text.trim().isEmpty) {
      return showError(context, 'Durusti ki wajah likhein');
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
        showDone(context, '${money(_amount!)} save ho gaye');
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
      PaymentMode.received => '$name se paise mile',
      PaymentMode.paid => '$name ko paise diye',
      PaymentMode.adjustment => '$name ke hisaab mein durusti',
    };
    return FormPage(
      title: title,
      saving: _saving,
      onSave: _save,
      children: [
        if (widget.mode == PaymentMode.adjustment)
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text('$name se lena barhe')),
              const ButtonSegment(value: false, label: Text('Mera dena barhe')),
            ],
            selected: {_owesMore},
            onSelectionChanged: (s) => setState(() => _owesMore = s.first),
          ),
        NumberField(label: 'Raqam', suffix: 'Rs', autofocus: true, onChanged: (v) => _amount = v),
        DateField(value: _date, onChanged: (d) => setState(() => _date = d)),
        if (widget.mode != PaymentMode.adjustment)
          SegmentedButton<PaymentMethod>(
            segments: [for (final m in PaymentMethod.values) ButtonSegment(value: m, label: Text(m.label))],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
        TextField(
          controller: _note,
          decoration: InputDecoration(
            labelText: widget.mode == PaymentMode.adjustment ? 'Wajah' : 'Note (agar ho)',
          ),
        ),
      ],
    );
  }
}
