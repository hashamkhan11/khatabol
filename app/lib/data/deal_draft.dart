import '../util/format.dart';
import 'models.dart';

class CostDraft {
  CostDraft({this.description = '', this.amount, this.chargedToId, this.paidToId});

  String description;
  num? amount;

  /// Party who bears the cost. Null = we bear it.
  String? chargedToId;

  /// Party we owe for it. Null = paid in cash now.
  String? paidToId;

  Map<String, dynamic> toJson() => {
        'description': description.trim(),
        'amount': amount,
        'charged_to_id': ?chargedToId,
        'paid_to_id': ?paidToId,
      };
}

class CommissionDraft {
  CommissionDraft({this.partyId, this.mode = CommissionMode.perKg, this.value});

  String? partyId;
  CommissionMode mode;
  num? value;

  Map<String, dynamic> toJson() => {'party_id': partyId, 'mode': mode.db, 'value': value};
}

/// Everything the deal form collects. [toJson] builds the payload for the
/// record_deal / replace_deal database functions; [khataEffects] previews what
/// each party's khata will show, so the user can check before saving.
///
/// The database is the source of truth. The preview only mirrors its rules.
class DealDraft {
  DealDraft({required this.kind, DateTime? date}) : date = date ?? DateTime.now();

  /// Starts an edit of an existing deal. [paidNow] is the money paid on the
  /// spot, read from the deal's khata lines.
  factory DealDraft.fromDeal(Deal d, {num? paidNow, PaymentMethod? paidMethod}) {
    return DealDraft(kind: d.kind, date: d.date)
      ..paidNow = paidNow
      ..paidMethod = paidMethod ?? PaymentMethod.cash
      ..partyId = d.partyId
      ..buyerId = d.buyerId
      ..itemId = d.itemId
      ..weightKg = d.weightKg
      ..rate = d.rate
      ..goodsThroughMe = d.goodsThroughMe
      ..notes = d.notes ?? ''
      ..costs = [
        for (final c in d.costs)
          CostDraft(description: c.description, amount: c.amount, chargedToId: c.chargedToId, paidToId: c.paidToId),
      ]
      ..commissions = [
        for (final c in d.commissions) CommissionDraft(partyId: c.partyId, mode: c.mode, value: c.value),
      ];
  }

  DealKind kind;
  DateTime date;
  String? partyId;
  String? buyerId;
  String? itemId;
  num? weightKg;
  num? rate;
  bool goodsThroughMe = false;
  num? paidNow;
  PaymentMethod paidMethod = PaymentMethod.cash;
  String notes = '';
  List<CostDraft> costs = [];
  List<CommissionDraft> commissions = [];

  bool get isCommission => kind == DealKind.commission;

  num? get goodsAmount => weightKg == null || rate == null ? null : roundMoney(weightKg! * rate!);

  num? commissionAmount(CommissionDraft c) {
    final v = c.value;
    if (v == null) return null;
    return switch (c.mode) {
      CommissionMode.fixed => roundMoney(v),
      CommissionMode.perKg => weightKg == null ? null : roundMoney(v * weightKg!),
      CommissionMode.percent => goodsAmount == null ? null : roundMoney(v * goodsAmount! / 100),
    };
  }

  /// A short reason the draft cannot be saved yet, or null when it looks valid.
  /// The database checks everything again.
  String? validate() {
    if (partyId == null) {
      return switch (kind) {
        DealKind.purchase => 'Supplier chunein',
        DealKind.sale => 'Gahak chunein',
        DealKind.commission => 'Bechne wala chunein',
      };
    }
    if (isCommission) {
      if (buyerId == null) return 'Khareedne wala chunein';
      if (buyerId == partyId) return 'Bechne wala aur khareedne wala alag hon';
      if (goodsThroughMe && (weightKg == null || rate == null)) {
        return 'Paise aap ke zariye hon to wazan aur rate likhein';
      }
      if (commissions.isEmpty) return 'Commission likhein';
    } else {
      if (itemId == null) return 'Kapre ki qisam chunein';
      if (weightKg == null) return 'Wazan likhein';
      if (rate == null) return 'Rate likhein';
    }
    if (weightKg != null && weightKg! <= 0) return 'Wazan zero se zyada ho';
    if (rate != null && rate! < 0) return 'Rate manfi nahi ho sakta';
    if (paidNow != null && paidNow! < 0) return 'Di gayi raqam manfi nahi ho sakti';
    for (final c in costs) {
      if (c.description.trim().isEmpty) return 'Har kharchay ka naam likhein';
      if (c.amount == null || c.amount! <= 0) return 'Har kharchay ki raqam likhein';
    }
    for (final c in commissions) {
      if (c.partyId == null) return 'Har commission ke liye chunein kis se hai';
      if (c.value == null || c.value! <= 0) return 'Har commission ki miqdar likhein';
      if (commissionAmount(c) == null) return '${c.mode.label} commission ke liye wazan aur rate likhein';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'deal_date': isoDate(date),
        'party_id': partyId,
        if (isCommission) 'buyer_id': buyerId,
        'item_id': ?itemId,
        'weight_kg': ?weightKg,
        'rate': ?rate,
        if (isCommission) 'goods_through_me': goodsThroughMe,
        if (!isCommission && (paidNow ?? 0) > 0) ...{'paid_now': paidNow, 'paid_method': paidMethod.name},
        'costs': [for (final c in costs) c.toJson()],
        if (isCommission) 'commissions': [for (final c in commissions) c.toJson()],
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
        'source': 'app',
      };

  /// How much each party's balance changes. Positive = they owe us more.
  Map<String, num> khataEffects() {
    final effects = <String, num>{};
    void add(String? party, num? amount) {
      if (party == null || amount == null || amount == 0) return;
      effects[party] = roundMoney((effects[party] ?? 0) + amount);
    }

    final goods = goodsAmount;
    switch (kind) {
      case DealKind.purchase:
        add(partyId, goods == null ? null : -goods);
        add(partyId, paidNow);
      case DealKind.sale:
        add(partyId, goods);
        add(partyId, paidNow == null ? null : -paidNow!);
      case DealKind.commission:
        if (goodsThroughMe && goods != null) {
          add(partyId, -goods);
          add(buyerId, goods);
        }
        for (final c in commissions) {
          add(c.partyId, commissionAmount(c));
        }
    }
    for (final c in costs) {
      add(c.chargedToId, c.amount);
      add(c.paidToId, c.amount == null ? null : -c.amount!);
    }
    effects.removeWhere((_, v) => v == 0);
    return effects;
  }
}
