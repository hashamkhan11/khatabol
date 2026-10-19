import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/common.dart';
import '../l10n/lang.dart';

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
    if (_name.text.trim().isEmpty) return showError(context, tr('Naam likhein', 'Enter a name'));
    if (_opening != _Opening.none && (_openingAmount == null || _openingAmount! <= 0)) {
      return showError(context, tr('Purane hisaab ki raqam likhein', 'Enter the opening balance amount'));
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
      title: _editing ? tr('Party badlein', 'Edit party') : tr('Nayi party', 'New party'),
      saving: _saving,
      onSave: _save,
      children: [
        TextField(
          controller: _name,
          autofocus: !_editing,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: tr('Naam', 'Name')),
        ),
        ChoiceField<PartyType>(
          label: tr('Qisam', 'Type'),
          options: [for (final t in PartyType.values) (t, t.label)],
          value: _type,
          onChanged: (t) => setState(() => _type = t),
        ),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: tr('Phone (agar ho)', 'Phone (optional)')),
        ),
        TextField(
          controller: _whatsapp,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: tr('WhatsApp (agar ho)', 'WhatsApp (optional)'),
            helperText: tr('Is number par khata bheja jayega', 'The ledger is sent to this number'),
          ),
        ),
        TextField(
          controller: _city,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: tr('Shehar (agar ho)', 'City (optional)')),
        ),
        TextField(
          controller: _notes,
          maxLines: 2,
          decoration: InputDecoration(labelText: tr('Note (agar ho)', 'Note (optional)')),
        ),
        if (!_editing) ...[
          FieldLabel(tr('Purana hisaab (is app se pehle ka khata)', 'Opening balance (from before this app)')),
          Segments<_Opening>(
            options: [
              (_Opening.none, tr('Koi nahi', 'None')),
              (_Opening.owesYou, tr('Lena hai', 'To receive')),
              (_Opening.youOwe, tr('Dena hai', 'To pay')),
            ],
            selected: _opening,
            onChanged: (o) => setState(() => _opening = o),
          ),
          if (_opening != _Opening.none) ...[
            NumberField(label: tr('Raqam', 'Amount'), suffix: 'Rs', onChanged: (v) => _openingAmount = v),
            DateField(label: tr('Kis tareekh tak', 'As of date'), value: _openingDate, onChanged: (d) => setState(() => _openingDate = d)),
          ],
        ],
      ],
    );
  }
}
