import '../util/format.dart';

// Labels are Roman Urdu, the way the trader speaks. The enum names match the
// database values, which stay English so the WhatsApp bot and the app share them.

enum PartyType {
  supplier('Supplier'),
  factory('Factory'),
  buyer('Gahak'),
  transporter('Transporter'),
  other('Deegar');

  const PartyType(this.label);
  final String label;

  static PartyType parse(String s) => PartyType.values.byName(s);
}

enum DealKind {
  purchase('Khareed'),
  sale('Farokht'),
  commission('Commission');

  const DealKind(this.label);
  final String label;

  static DealKind parse(String s) => DealKind.values.byName(s);
}

enum PaymentMethod {
  cash('Cash'),
  bank('Bank'),
  other('Deegar');

  const PaymentMethod(this.label);
  final String label;

  static PaymentMethod? parse(String? s) => s == null ? null : PaymentMethod.values.byName(s);
}

enum CommissionMode {
  perKg('per_kg', 'Fi kg'),
  percent('percent', 'Feesad'),
  fixed('fixed', 'Pakki raqam');

  const CommissionMode(this.db, this.label);
  final String db;
  final String label;

  static CommissionMode parse(String s) => CommissionMode.values.firstWhere((m) => m.db == s);
}

/// A party with its live balance (from the party_balances view).
class PartyBalance {
  PartyBalance({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    this.city,
    this.lastEntryDate,
    this.archived = false,
  });

  factory PartyBalance.fromJson(Map<String, dynamic> j) => PartyBalance(
        id: j['party_id'] as String,
        name: j['name'] as String,
        type: PartyType.parse(j['type'] as String),
        city: j['city'] as String?,
        balance: toNum(j['balance']),
        lastEntryDate: j['last_entry_date'] == null ? null : parseDate(j['last_entry_date'] as String),
        archived: j['archived_at'] != null,
      );

  final String id;
  final String name;
  final PartyType type;
  final String? city;

  /// Positive = they owe us. Negative = we owe them.
  final num balance;
  final DateTime? lastEntryDate;
  final bool archived;
}

class Party {
  Party({
    required this.id,
    required this.name,
    required this.type,
    this.phone,
    this.whatsapp,
    this.city,
    this.notes,
    this.archived = false,
  });

  factory Party.fromJson(Map<String, dynamic> j) => Party(
        id: j['id'] as String,
        name: j['name'] as String,
        type: PartyType.parse(j['type'] as String),
        phone: j['phone'] as String?,
        whatsapp: j['whatsapp'] as String?,
        city: j['city'] as String?,
        notes: j['notes'] as String?,
        archived: j['archived_at'] != null,
      );

  final String id;
  final String name;
  final PartyType type;
  final String? phone;
  final String? whatsapp;
  final String? city;
  final String? notes;
  final bool archived;
}

/// A cloth type.
class Item {
  Item({required this.id, required this.nameEn, this.nameUr, this.archived = false});

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        nameEn: j['name_en'] as String,
        nameUr: j['name_ur'] as String?,
        archived: j['archived_at'] != null,
      );

  final String id;
  final String nameEn;
  final String? nameUr;
  final bool archived;

  String get displayName => nameUr == null ? nameEn : '$nameEn · $nameUr';
}

/// Why stock changed outside a deal. The first three bring stock in.
enum StockAdjustmentKind {
  opening('Shuru ka stock', true),
  found('Ginti mein zyada nikla', true),
  otherIn('Deegar (aamad)', true),
  wastage('Kharab / zaya', false),
  shortage('Ginti mein kam nikla', false),
  ownUse('Apna istemal', false),
  sample('Namoona', false),
  otherOut('Deegar (nikasi)', false);

  const StockAdjustmentKind(this.label, this.isIn);
  final String label;

  /// True when this kind adds stock.
  final bool isIn;

  /// The database value: 'other_in', 'own_use', ...
  String get db => name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

  static StockAdjustmentKind? tryParse(String? s) => StockAdjustmentKind.values.where((k) => k.db == s).firstOrNull;
}

/// One khata line with the facts needed to describe it in any language
/// (see khata_text.dart). Comes from the khata_lines view, or from
/// party_statement, which adds the running [balance].
///
/// The database stores no sentences: [note] is only what a person typed.
class KhataLine {
  KhataLine({
    required this.entryId,
    required this.date,
    required this.kind,
    required this.amount,
    this.note,
    this.method,
    this.balance,
    this.partyId,
    this.partyName,
    this.dealId,
    this.dealKind,
    this.itemName,
    this.weightKg,
    this.rate,
    this.counterpartyName,
    this.expenseId,
    this.expenseCategory,
    this.reversesId,
    this.reversedKind,
    this.cancelled = false,
  });

  factory KhataLine.fromJson(Map<String, dynamic> j) => KhataLine(
        entryId: (j['entry_id'] ?? j['id']) as String?,
        date: parseDate(j['entry_date'] as String),
        kind: j['kind'] as String?,
        note: j['note'] as String?,
        method: PaymentMethod.parse(j['method'] as String?),
        amount: toNum(j['amount']),
        balance: toNumOrNull(j['balance']),
        partyId: j['party_id'] as String?,
        partyName: j['party_name'] as String?,
        dealId: j['deal_id'] as String?,
        dealKind: j['deal_kind'] == null ? null : DealKind.parse(j['deal_kind'] as String),
        itemName: j['item_name'] as String?,
        weightKg: toNumOrNull(j['weight_kg']),
        rate: toNumOrNull(j['rate']),
        counterpartyName: j['counterparty_name'] as String?,
        expenseId: j['expense_id'] as String?,
        expenseCategory: j['expense_category'] as String?,
        reversesId: j['reverses_id'] as String?,
        reversedKind: j['reversed_kind'] as String?,
        cancelled: (j['cancelled'] as bool?) ?? false,
      );

  /// Null only for the brought-forward line of a statement.
  final String? entryId;
  final DateTime date;

  /// The entry kind: 'opening', 'purchase', 'payment_in', ... Null when brought forward.
  final String? kind;
  final String? note;
  final PaymentMethod? method;

  /// Positive = the party owes us more.
  final num amount;

  /// Balance after this line (statements only).
  final num? balance;
  final String? partyId;
  final String? partyName;
  final String? dealId;
  final DealKind? dealKind;
  final String? itemName;
  final num? weightKg;
  final num? rate;

  /// The other side of the deal, when it is not this line's party.
  final String? counterpartyName;
  final String? expenseId;
  final String? expenseCategory;
  final String? reversesId;

  /// For a cancelling line: the kind of line it cancelled.
  final String? reversedKind;

  /// A cancelling line, or a line that has been cancelled.
  final bool cancelled;

  bool get isBroughtForward => entryId == null;
  bool get isReversal => kind == 'reversal';
}

/// One move in a cloth type's stock register, with the kg in hand after it.
class StockMove {
  StockMove({
    required this.date,
    required this.kind,
    required this.weightKg,
    required this.qtyAfter,
    this.dealId,
    this.adjustmentId,
    this.partyName,
    this.rate,
    this.reason,
    this.avgCostAfter,
  });

  factory StockMove.fromJson(Map<String, dynamic> j) => StockMove(
        date: parseDate(j['move_date'] as String),
        kind: j['kind'] as String,
        weightKg: toNum(j['weight_kg']),
        qtyAfter: toNum(j['qty_after']),
        dealId: j['deal_id'] as String?,
        adjustmentId: j['adjustment_id'] as String?,
        partyName: j['party_name'] as String?,
        rate: toNumOrNull(j['rate']),
        reason: j['reason'] as String?,
        avgCostAfter: toNumOrNull(j['avg_cost_after']),
      );

  final DateTime date;

  /// 'purchase' or 'sale' for deals, otherwise a stock adjustment kind.
  final String kind;

  /// Positive = stock came in.
  final num weightKg;
  final num qtyAfter;
  final String? dealId;
  final String? adjustmentId;
  final String? partyName;

  /// Deal rate, or cost per kg of stock that came in.
  final num? rate;
  final String? reason;
  final num? avgCostAfter;
}

class DealCost {
  DealCost({
    required this.description,
    required this.amount,
    this.chargedToId,
    this.paidToId,
    this.paidToName,
  });

  factory DealCost.fromJson(Map<String, dynamic> j) => DealCost(
        description: j['description'] as String,
        amount: toNum(j['amount']),
        chargedToId: j['charged_to_id'] as String?,
        paidToId: j['paid_to_id'] as String?,
        paidToName: (j['paid_to'] as Map<String, dynamic>?)?['name'] as String?,
      );

  final String description;
  final num amount;

  /// Party who bears the cost. Null = we bear it.
  final String? chargedToId;

  /// Party we owe for it (e.g. a transporter). Null = paid in cash.
  final String? paidToId;
  final String? paidToName;
}

class DealCommission {
  DealCommission({required this.partyId, required this.mode, required this.value, this.amount});

  factory DealCommission.fromJson(Map<String, dynamic> j) => DealCommission(
        partyId: j['party_id'] as String,
        mode: CommissionMode.parse(j['mode'] as String),
        value: toNum(j['value']),
        amount: toNumOrNull(j['amount']),
      );

  final String partyId;
  final CommissionMode mode;
  final num value;
  final num? amount;
}

class Deal {
  Deal({
    required this.id,
    required this.kind,
    required this.date,
    required this.partyId,
    required this.partyName,
    this.buyerId,
    this.buyerName,
    this.itemId,
    this.itemName,
    this.weightKg,
    this.rate,
    this.goodsAmount,
    this.goodsThroughMe = false,
    this.notes,
    this.source = 'app',
    this.cancelled = false,
    this.cancelReason,
    this.replacesId,
    this.costs = const [],
    this.commissions = const [],
  });

  factory Deal.fromJson(Map<String, dynamic> j) => Deal(
        id: j['id'] as String,
        kind: DealKind.parse(j['kind'] as String),
        date: parseDate(j['deal_date'] as String),
        partyId: j['party_id'] as String,
        partyName: (j['party'] as Map<String, dynamic>)['name'] as String,
        buyerId: j['buyer_id'] as String?,
        buyerName: (j['buyer'] as Map<String, dynamic>?)?['name'] as String?,
        itemId: j['item_id'] as String?,
        itemName: (j['item'] as Map<String, dynamic>?)?['name_en'] as String?,
        weightKg: toNumOrNull(j['weight_kg']),
        rate: toNumOrNull(j['rate']),
        goodsAmount: toNumOrNull(j['goods_amount']),
        goodsThroughMe: (j['goods_through_me'] as bool?) ?? false,
        notes: j['notes'] as String?,
        source: (j['source'] as String?) ?? 'app',
        cancelled: j['cancelled_at'] != null,
        cancelReason: j['cancel_reason'] as String?,
        replacesId: j['replaces_id'] as String?,
        costs: [
          for (final c in (j['deal_costs'] as List?) ?? const []) DealCost.fromJson(c as Map<String, dynamic>),
        ],
        commissions: [
          for (final c in (j['deal_commissions'] as List?) ?? const [])
            DealCommission.fromJson(c as Map<String, dynamic>),
        ],
      );

  final String id;
  final DealKind kind;
  final DateTime date;
  final String partyId;
  final String partyName;
  final String? buyerId;
  final String? buyerName;
  final String? itemId;
  final String? itemName;
  final num? weightKg;
  final num? rate;
  final num? goodsAmount;
  final bool goodsThroughMe;
  final String? notes;
  final String source;
  final bool cancelled;
  final String? cancelReason;
  final String? replacesId;
  final List<DealCost> costs;
  final List<DealCommission> commissions;

  num get commissionTotal => commissions.fold<num>(0, (sum, c) => sum + (c.amount ?? 0));

  /// "Rashid → Akram" for commission deals, otherwise the party name.
  String get title => kind == DealKind.commission ? '$partyName → $buyerName' : partyName;

  /// "Used cloth · 500 kg @ 120"
  String get summary => [
        ?itemName,
        if (weightKg != null) kg(weightKg!) + (rate != null ? ' @ ${plainNumber(rate!)}' : ''),
      ].join(' · ');
}

class Expense {
  Expense({
    required this.id,
    required this.date,
    required this.category,
    required this.amount,
    this.paidToId,
    this.paidToName,
    this.notes,
    this.cancelled = false,
  });

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] as String,
        date: parseDate(j['expense_date'] as String),
        category: j['category'] as String,
        amount: toNum(j['amount']),
        paidToId: j['paid_to_id'] as String?,
        paidToName: (j['paid_to'] as Map<String, dynamic>?)?['name'] as String?,
        notes: j['notes'] as String?,
        cancelled: j['cancelled_at'] != null,
      );

  final String id;
  final DateTime date;
  final String category;
  final num amount;
  final String? paidToId;
  final String? paidToName;
  final String? notes;
  final bool cancelled;
}

class StockRow {
  StockRow({
    required this.itemId,
    required this.nameEn,
    required this.weightKg,
    required this.stockValue,
    this.nameUr,
    this.avgCost,
    this.archived = false,
  });

  factory StockRow.fromJson(Map<String, dynamic> j) => StockRow(
        itemId: j['item_id'] as String,
        nameEn: j['name_en'] as String,
        nameUr: j['name_ur'] as String?,
        archived: (j['archived'] as bool?) ?? false,
        weightKg: toNum(j['weight_kg']),
        avgCost: toNumOrNull(j['avg_cost']),
        stockValue: toNum(j['stock_value']),
      );

  final String itemId;
  final String nameEn;
  final String? nameUr;
  final bool archived;
  final num weightKg;
  final num? avgCost;
  final num stockValue;

  Item get item => Item(id: itemId, nameEn: nameEn, nameUr: nameUr, archived: archived);
}

class ProfitReport {
  ProfitReport({
    required this.salesAmount,
    required this.costOfGoodsSold,
    required this.saleCosts,
    required this.tradingProfit,
    required this.commissionIncome,
    required this.commissionCosts,
    required this.stockLosses,
    required this.expenses,
    required this.netProfit,
    required this.hasEstimates,
  });

  factory ProfitReport.fromJson(Map<String, dynamic> j) => ProfitReport(
        salesAmount: toNum(j['sales_amount']),
        costOfGoodsSold: toNum(j['cost_of_goods_sold']),
        saleCosts: toNum(j['sale_costs']),
        tradingProfit: toNum(j['trading_profit']),
        commissionIncome: toNum(j['commission_income']),
        commissionCosts: toNum(j['commission_costs']),
        stockLosses: toNum(j['stock_losses']),
        expenses: toNum(j['expenses']),
        netProfit: toNum(j['net_profit']),
        hasEstimates: (j['has_estimates'] as bool?) ?? false,
      );

  final num salesAmount;
  final num costOfGoodsSold;
  final num saleCosts;
  final num tradingProfit;
  final num commissionIncome;
  final num commissionCosts;
  final num stockLosses;
  final num expenses;
  final num netProfit;
  final bool hasEstimates;
}
