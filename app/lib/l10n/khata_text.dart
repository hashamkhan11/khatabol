import '../data/models.dart';
import '../util/format.dart';
import 'lang.dart';

// Words every khata line in the chosen language, from the facts the database keeps
// (entry kind, deal, cloth, kg, rate, other party, expense category).
// The WhatsApp bot words the same facts in the language it is spoken to.

/// The main text of a khata line: "Khareed · Used cloth · 500 kg @ 120".
String lineTitle(KhataLine l) {
  if (l.isBroughtForward) return tr('Pichla baqaya', 'Brought forward');
  if (l.isReversal) return '${tr('Cancel', 'Cancelled')}: ${_describe(l.reversedKind, l)}';
  return _describe(l.kind, l);
}

/// Date, payment method and what the user typed: "3 Oct 2026 · Cash · by hand".
String lineDetails(KhataLine l) => [
      formatDate(l.date),
      ?l.method?.label,
      // A deal cost's note is its description, already in the title.
      if (l.kind != 'deal_cost') ?l.note,
    ].join(' · ');

/// "+ 40,000" when the party owes more, "− 40,000" when we owe more.
String signedAmount(num amount) => '${amount >= 0 ? '+' : '−'} ${plainNumber(amount.abs())}';

String _describe(String? kind, KhataLine l) {
  final withParty = l.counterpartyName == null
      ? null
      : tr('${l.counterpartyName} wala sauda', 'deal with ${l.counterpartyName}');
  final dealCost = tr('sauday ka', 'deal');
  return switch (kind) {
    'opening' => tr('Purana hisaab', 'Opening balance'),
    'purchase' => [tr('Khareed', 'Purchase'), ..._goods(l), ?withParty].join(' · '),
    'sale' => [tr('Farokht', 'Sale'), ..._goods(l), ?withParty].join(' · '),
    'commission' => ['Commission', ?withParty, if (l.weightKg != null) kg(l.weightKg!)].join(' · '),
    'deal_cost' => ['${tr('Kharcha', 'Cost')}: ${l.isReversal ? dealCost : (l.note ?? dealCost)}', ?withParty].join(' · '),
    'payment_in' => l.dealId == null ? tr('Paise mile', 'Money received') : tr('Sauday par paise mile', 'Received on deal'),
    'payment_out' => l.dealId == null ? tr('Paise diye', 'Money paid') : tr('Sauday par paise diye', 'Paid on deal'),
    'expense' => '${tr('Kharcha', 'Expense')}: ${l.expenseCategory ?? ''}'.trim(),
    'adjustment' => tr('Durusti', 'Correction'),
    'reversal' => tr('Cancel', 'Cancelled'),
    _ => kind ?? '',
  };
}

/// "Used cloth", "500 kg @ 120"
List<String> _goods(KhataLine l) => [
      ?l.itemName,
      if (l.weightKg != null) kg(l.weightKg!) + (l.rate != null ? ' @ ${plainNumber(l.rate!)}' : ''),
    ];
