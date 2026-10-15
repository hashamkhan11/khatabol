import '../data/models.dart';
import '../util/format.dart';

// Words every khata line in Roman Urdu, from the facts the database keeps
// (entry kind, deal, cloth, kg, rate, other party, expense category).
// The WhatsApp bot words the same facts in the language it is spoken to.

/// The main text of a khata line: "Khareed · Used cloth · 500 kg @ 120".
String lineTitle(KhataLine l) {
  if (l.isBroughtForward) return 'Pichla baqaya';
  if (l.isReversal) return 'Cancel: ${_describe(l.reversedKind, l)}';
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
  final withParty = l.counterpartyName == null ? null : '${l.counterpartyName} wala sauda';
  return switch (kind) {
    'opening' => 'Purana hisaab',
    'purchase' => ['Khareed', ..._goods(l), ?withParty].join(' · '),
    'sale' => ['Farokht', ..._goods(l), ?withParty].join(' · '),
    'commission' => ['Commission', ?withParty, if (l.weightKg != null) kg(l.weightKg!)].join(' · '),
    'deal_cost' => ['Kharcha: ${l.isReversal ? 'sauday ka' : (l.note ?? 'sauday ka')}', ?withParty].join(' · '),
    'payment_in' => l.dealId == null ? 'Paise mile' : 'Sauday par paise mile',
    'payment_out' => l.dealId == null ? 'Paise diye' : 'Sauday par paise diye',
    'expense' => 'Kharcha: ${l.expenseCategory ?? ''}'.trim(),
    'adjustment' => 'Durusti',
    'reversal' => 'Cancel',
    _ => kind ?? '',
  };
}

/// "Used cloth", "500 kg @ 120"
List<String> _goods(KhataLine l) => [
      ?l.itemName,
      if (l.weightKg != null) kg(l.weightKg!) + (l.rate != null ? ' @ ${plainNumber(l.rate!)}' : ''),
    ];
