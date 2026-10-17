import 'package:flutter_test/flutter_test.dart';
import 'package:khatabol/data/models.dart';
import 'package:khatabol/l10n/khata_text.dart';
import 'package:khatabol/l10n/lang.dart';

KhataLine line(Map<String, dynamic> facts) => KhataLine.fromJson({
      'entry_id': 'e1',
      'entry_date': '2026-10-03',
      'amount': 0,
      ...facts,
    });

void main() {
  group('lineTitle words the facts in Roman Urdu', () {
    test('purchase with cloth, weight and rate', () {
      final l = line({
        'kind': 'purchase',
        'deal_id': 'd1',
        'item_name': 'Used cloth',
        'weight_kg': 500,
        'rate': 120,
        'amount': -60000,
      });
      expect(lineTitle(l), 'Khareed · Used cloth · 500 kg @ 120');
    });

    test('commission names the other side of the deal', () {
      final l = line({'kind': 'commission', 'deal_id': 'd1', 'counterparty_name': 'Akram', 'weight_kg': 1000});
      expect(lineTitle(l), 'Commission · Akram wala sauda · 1,000 kg');
    });

    test('payments, with and without a deal', () {
      expect(lineTitle(line({'kind': 'payment_in'})), 'Paise mile');
      expect(lineTitle(line({'kind': 'payment_out', 'deal_id': 'd1'})), 'Sauday par paise diye');
    });

    test('deal cost uses the typed description', () {
      expect(lineTitle(line({'kind': 'deal_cost', 'note': 'Freight'})), 'Kharcha: Freight');
    });

    test('expense shows its category', () {
      expect(lineTitle(line({'kind': 'expense', 'expense_category': 'Rent'})), 'Kharcha: Rent');
    });

    test('reversal describes what it cancels', () {
      final l = line({'kind': 'reversal', 'reverses_id': 'e0', 'reversed_kind': 'payment_in'});
      expect(lineTitle(l), 'Cancel: Paise mile');
    });

    test('brought-forward line', () {
      final l = KhataLine.fromJson({'entry_id': null, 'entry_date': '2026-10-01', 'amount': -10000, 'balance': -10000});
      expect(lineTitle(l), 'Pichla baqaya');
    });
  });

  group('in English', () {
    setUp(() => appLang.value = AppLang.english);
    tearDown(() => appLang.value = AppLang.romanUrdu);

    test('deal lines', () {
      final l = line({'kind': 'sale', 'deal_id': 'd1', 'item_name': 'Used cloth', 'weight_kg': 200, 'rate': 150});
      expect(lineTitle(l), 'Sale · Used cloth · 200 kg @ 150');
      final c = line({'kind': 'commission', 'deal_id': 'd1', 'counterparty_name': 'Akram'});
      expect(lineTitle(c), 'Commission · deal with Akram');
    });

    test('payments, costs and cancellations', () {
      expect(lineTitle(line({'kind': 'payment_in'})), 'Money received');
      expect(lineTitle(line({'kind': 'payment_out', 'deal_id': 'd1'})), 'Paid on deal');
      expect(lineTitle(line({'kind': 'expense', 'expense_category': 'Rent'})), 'Expense: Rent');
      final r = line({'kind': 'reversal', 'reverses_id': 'e0', 'reversed_kind': 'payment_in'});
      expect(lineTitle(r), 'Cancelled: Money received');
    });

    test('enum labels follow the language', () {
      expect(DealKind.purchase.label, 'Purchase');
      expect(PartyType.buyer.label, 'Buyer');
      expect(StockAdjustmentKind.wastage.label, 'Damaged / wasted');
    });
  });

  test('lineDetails skips a deal cost note already in the title', () {
    final l = line({'kind': 'deal_cost', 'note': 'Freight'});
    expect(lineDetails(l), isNot(contains('Freight')));
    final p = line({'kind': 'payment_in', 'method': 'cash', 'note': 'by hand'});
    expect(lineDetails(p), endsWith('· Cash · by hand'));
  });

  test('signedAmount', () {
    expect(signedAmount(40000), '+ 40,000');
    expect(signedAmount(-1500.5), '− 1,500.5');
  });

  test('stock adjustment kinds map to database names', () {
    expect(StockAdjustmentKind.ownUse.db, 'own_use');
    expect(StockAdjustmentKind.tryParse('other_out'), StockAdjustmentKind.otherOut);
    expect(StockAdjustmentKind.wastage.isIn, isFalse);
    expect(StockAdjustmentKind.opening.isIn, isTrue);
  });
}
