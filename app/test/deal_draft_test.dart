import 'package:flutter_test/flutter_test.dart';
import 'package:khatabol/data/deal_draft.dart';
import 'package:khatabol/data/models.dart';

// The preview must match what the database writes. These cases mirror the
// database tests in supabase/tests/ledger.test.mjs.
void main() {
  DealDraft purchase() => DealDraft(kind: DealKind.purchase, date: DateTime(2026, 10, 1))
    ..partyId = 'rashid'
    ..itemId = 'cloth'
    ..weightKg = 500
    ..rate = 120;

  DealDraft commission() => DealDraft(kind: DealKind.commission, date: DateTime(2026, 10, 1))
    ..partyId = 'rashid'
    ..buyerId = 'akram'
    ..weightKg = 1000
    ..rate = 100;

  group('khata preview', () {
    test('purchase on credit: we owe the full amount', () {
      expect(purchase().khataEffects(), {'rashid': -60000});
    });

    test('purchase with part paid: we owe the rest', () {
      final d = purchase()..paidNow = 20000;
      expect(d.khataEffects(), {'rashid': -40000});
    });

    test('sale with part received: buyer owes the rest', () {
      final d = DealDraft(kind: DealKind.sale)
        ..partyId = 'akram'
        ..itemId = 'cloth'
        ..weightKg = 600
        ..rate = 150
        ..paidNow = 50000;
      expect(d.khataEffects(), {'akram': 40000});
    });

    test('fully paid purchase leaves no balance', () {
      final d = purchase()..paidNow = 60000;
      expect(d.khataEffects(), isEmpty);
    });

    test('commission from both sides, goods paid directly', () {
      final d = commission()
        ..commissions = [
          CommissionDraft(partyId: 'rashid', mode: CommissionMode.perKg, value: 2),
          CommissionDraft(partyId: 'akram', mode: CommissionMode.percent, value: 1),
        ];
      expect(d.khataEffects(), {'rashid': 2000, 'akram': 1000});
    });

    test('commission with goods money through me', () {
      final d = commission()
        ..goodsThroughMe = true
        ..commissions = [CommissionDraft(partyId: 'rashid', mode: CommissionMode.perKg, value: 2)];
      expect(d.khataEffects(), {'rashid': -98000, 'akram': 100000});
    });

    test('costs: charged to a party and owed to a transporter', () {
      final d = purchase()
        ..costs = [
          CostDraft(description: 'Freight', amount: 5000, paidToId: 'bilal'),
          CostDraft(description: 'Loading', amount: 1000, chargedToId: 'rashid'),
        ];
      expect(d.khataEffects(), {'rashid': -59000, 'bilal': -5000});
    });

    test('cost we bear and pay in cash changes no khata', () {
      final d = purchase()..costs = [CostDraft(description: 'Labour', amount: 800)];
      expect(d.khataEffects(), {'rashid': -60000});
    });
  });

  group('amounts', () {
    test('goods amount is weight × rate, rounded to paisa', () {
      final d = purchase()
        ..weightKg = 12.345
        ..rate = 10.01;
      expect(d.goodsAmount, 123.57);
    });

    test('commission modes', () {
      final d = commission();
      expect(d.commissionAmount(CommissionDraft(mode: CommissionMode.perKg, value: 1.5)), 1500);
      expect(d.commissionAmount(CommissionDraft(mode: CommissionMode.percent, value: 2)), 2000);
      expect(d.commissionAmount(CommissionDraft(mode: CommissionMode.fixed, value: 750)), 750);
    });

    test('per kg commission without weight cannot be worked out', () {
      final d = commission()..weightKg = null;
      expect(d.commissionAmount(CommissionDraft(mode: CommissionMode.perKg, value: 2)), isNull);
      expect(d.commissionAmount(CommissionDraft(mode: CommissionMode.fixed, value: 500)), 500);
    });
  });

  group('validate', () {
    test('a complete purchase is valid', () {
      expect(purchase().validate(), isNull);
    });

    test('names the first missing field', () {
      expect(DealDraft(kind: DealKind.purchase).validate(), 'Choose the supplier');
      expect((purchase()..itemId = null).validate(), 'Choose the cloth type');
      expect((purchase()..rate = null).validate(), 'Enter the rate');
    });

    test('commission needs a different buyer and a commission line', () {
      expect((commission()..buyerId = 'rashid').validate(), 'Seller and buyer must be different');
      expect(commission().validate(), 'Add the commission');
    });

    test('money through me needs weight and rate', () {
      final d = commission()
        ..goodsThroughMe = true
        ..rate = null
        ..commissions = [CommissionDraft(partyId: 'rashid', mode: CommissionMode.fixed, value: 500)];
      expect(d.validate(), 'Enter weight and rate when the money goes through you');
    });

    test('costs need a description and an amount', () {
      expect((purchase()..costs = [CostDraft(amount: 100)]).validate(), 'Every cost needs a description');
      expect((purchase()..costs = [CostDraft(description: 'Freight')]).validate(), 'Every cost needs an amount');
    });
  });

  group('payload for record_deal', () {
    test('purchase', () {
      final d = purchase()
        ..paidNow = 20000
        ..paidMethod = PaymentMethod.bank
        ..notes = '  first lot  ';
      expect(d.toJson(), {
        'kind': 'purchase',
        'deal_date': '2026-10-01',
        'party_id': 'rashid',
        'item_id': 'cloth',
        'weight_kg': 500,
        'rate': 120,
        'paid_now': 20000,
        'paid_method': 'bank',
        'costs': [],
        'notes': 'first lot',
        'source': 'app',
      });
    });

    test('commission sends buyer, goods flag and commission lines; never paid_now', () {
      final d = commission()
        ..paidNow = 999
        ..commissions = [CommissionDraft(partyId: 'akram', mode: CommissionMode.percent, value: 1)];
      final json = d.toJson();
      expect(json['buyer_id'], 'akram');
      expect(json['goods_through_me'], false);
      expect(json['commissions'], [
        {'party_id': 'akram', 'mode': 'percent', 'value': 1},
      ]);
      expect(json.containsKey('paid_now'), isFalse);
    });

    test('empty optional cost fields are left out', () {
      final cost = CostDraft(description: ' Freight ', amount: 500).toJson();
      expect(cost, {'description': 'Freight', 'amount': 500});
    });
  });
}
