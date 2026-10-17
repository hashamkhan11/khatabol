import 'package:flutter_test/flutter_test.dart';
import 'package:khatabol/data/models.dart';
import 'package:khatabol/l10n/lang.dart';
import 'package:khatabol/util/format.dart';

void main() {
  test('money shows rupees with separators and no sign', () {
    expect(money(120000), 'Rs 120,000');
    expect(money(-40000.5), 'Rs 40,000.5');
    expect(money(0), 'Rs 0');
  });

  test('kg', () {
    expect(kg(1500), '1,500 kg');
    expect(kg(12.345), '12.345 kg');
  });

  test('parseNumber reads what people type', () {
    expect(parseNumber('1,20,000'), 120000);
    expect(parseNumber(' 2.5 '), 2.5);
    expect(parseNumber(''), isNull);
    expect(parseNumber('abc'), isNull);
    expect(parseNumber(null), isNull);
  });

  test('isoDate pads month and day', () {
    expect(isoDate(DateTime(2026, 3, 7)), '2026-03-07');
  });

  test('toNum accepts numbers and numeric strings from the database', () {
    expect(toNum(5), 5);
    expect(toNum('123456789012.34'), 123456789012.34);
    expect(toNum(null), 0);
  });

  test('balance labels', () {
    expect(balanceLabel(100), 'Lena hai');
    expect(balanceLabel(-100), 'Dena hai');
    expect(balanceLabel(0), 'Hisaab barabar');
    appLang.value = AppLang.english;
    addTearDown(() => appLang.value = AppLang.romanUrdu);
    expect(balanceLabel(100), 'To receive');
    expect(balanceLabel(-100), 'To pay');
    expect(balanceLabel(0), 'Settled');
  });

  group('models parse database rows', () {
    test('party balance', () {
      final p = PartyBalance.fromJson({
        'party_id': 'p1',
        'name': 'Rashid',
        'type': 'supplier',
        'city': null,
        'archived_at': null,
        'balance': -40000,
        'last_entry_date': '2026-10-01',
      });
      expect(p.balance, -40000);
      expect(p.type, PartyType.supplier);
      expect(p.lastEntryDate, DateTime(2026, 10, 1));
      expect(p.archived, isFalse);
    });

    test('deal with joined names, costs and commissions', () {
      final d = Deal.fromJson({
        'id': 'd1',
        'kind': 'commission',
        'deal_date': '2026-10-01',
        'party_id': 'p1',
        'party': {'name': 'Rashid'},
        'buyer_id': 'p2',
        'buyer': {'name': 'Akram'},
        'item_id': null,
        'item': null,
        'weight_kg': 1000,
        'rate': 100,
        'goods_amount': 100000,
        'goods_through_me': false,
        'cancelled_at': null,
        'deal_costs': [
          {'description': 'Freight', 'amount': 500, 'charged_to_id': null, 'paid_to_id': null},
        ],
        'deal_commissions': [
          {'party_id': 'p1', 'mode': 'per_kg', 'value': 2, 'amount': 2000},
          {'party_id': 'p2', 'mode': 'percent', 'value': 1, 'amount': 1000},
        ],
      });
      expect(d.title, 'Rashid → Akram');
      expect(d.commissionTotal, 3000);
      expect(d.summary, '1,000 kg @ 100');
      expect(d.commissions.first.mode, CommissionMode.perKg);
      expect(d.costs.single.description, 'Freight');
    });

    test('statement brought-forward line has no entry id', () {
      final line = KhataLine.fromJson({
        'entry_id': null,
        'entry_date': '2026-10-01',
        'kind': null,
        'note': null,
        'method': null,
        'amount': -10000,
        'balance': -10000,
      });
      expect(line.isBroughtForward, isTrue);
    });
  });
}
