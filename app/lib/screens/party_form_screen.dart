import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';

/// Adds a new party (with an optional opening balance) or edits one.
class PartyFormScreen extends StatefulWidget {
  const PartyFormScreen({super.key, this.party});

  final Party? party;

  @override
  State<PartyFormScreen> createState() => _PartyFormScreenState();
}

enum _Opening { none, owesYou, youOwe }

class _PartyFormScreenState extends State<PartyFormScreen> {
  late final _name = TextEditingController(text: widget.party?.name);
  late final _phone = TextEditingController(text: widget.party?.phone);
  late final _whatsapp = TextEditingController(text: widget.party?.whatsapp);
  late final _city = TextEditingController(text: widget.party?.city);
  late final _notes = TextEditingController(text: widget.party?.notes);
  late PartyType _type = widget.party?.type ?? PartyType.supplier;
  _Opening _opening = _Opening.none;
  num? _openingAmount;
  DateTime _openingDate = DateTime.now();
  bool _saving = false;

  bool get _editing => widget.party != null;

  @override
  void dispose() {
    for (final c in [_name, _phone, _whatsapp, _city, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return showError(context, 'Naam likhein');
    if (_opening != _Opening.none && (_openingAmount == null || _openingAmount! <= 0)) {
      return showError(context, 'Purane hisaab ki raqam likhein');
    }
    setState(() => _saving = true);
    final repo = Repo.of(context);
    try {
      if (_editing) {
        await repo.updateParty(widget.party!,
            name: _name.text,
            type: _type,
            phone: _phone.text,
            whatsapp: _whatsapp.text,
            city: _city.text,
            notes: _notes.text);
      } else {
        await repo.createParty(
          name: _name.text,
          type: _type,
          phone: _phone.text,
          whatsapp: _whatsapp.text,
          city: _city.text,
          notes: _notes.text,
          openingBalance: switch (_opening) {
            _Opening.none => 0,
            _Opening.owesYou => _openingAmount!,
            _Opening.youOwe => -_openingAmount!,
          },
          openingDate: _openingDate,
        );
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
      title: _editing ? 'Party badlein' : 'Nayi party',
      saving: _saving,
      onSave: _save,
      children: [
        TextField(
          controller: _name,
          autofocus: !_editing,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Naam'),
        ),
        DropdownButtonFormField<PartyType>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Qisam'),
          items: [for (final t in PartyType.values) DropdownMenuItem(value: t, child: Text(t.label))],
          onChanged: (t) => setState(() => _type = t!),
        ),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone (agar ho)'),
        ),
        TextField(
          controller: _whatsapp,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'WhatsApp (agar ho)',
            helperText: 'Is number par khata bheja jayega',
          ),
        ),
        TextField(
          controller: _city,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Shehar (agar ho)'),
        ),
        TextField(
          controller: _notes,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Note (agar ho)'),
        ),
        if (!_editing) ...[
          const Text('Purana hisaab (is app se pehle ka khata)'),
          SegmentedButton<_Opening>(
            segments: const [
              ButtonSegment(value: _Opening.none, label: Text('Koi nahi')),
              ButtonSegment(value: _Opening.owesYou, label: Text('Lena hai')),
              ButtonSegment(value: _Opening.youOwe, label: Text('Dena hai')),
            ],
            selected: {_opening},
            onSelectionChanged: (s) => setState(() => _opening = s.first),
          ),
          if (_opening != _Opening.none) ...[
            NumberField(label: 'Raqam', suffix: 'Rs', onChanged: (v) => _openingAmount = v),
            DateField(label: 'Kis tareekh tak', value: _openingDate, onChanged: (d) => setState(() => _openingDate = d)),
          ],
        ],
      ],
    );
  }
}
