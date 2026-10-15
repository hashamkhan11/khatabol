import '../util/format.dart';

enum PartyType {
  supplier('Supplier'),
  factory('Factory'),
  buyer('Buyer'),
  transporter('Transporter'),
  other('Other');

  const PartyType(this.label);
  final String label;

  static PartyType parse(String s) => PartyType.values.byName(s);
}

enum DealKind {
  purchase('Purchase'),
  sale('Sale'),
  commission('Commission');

  const DealKind(this.label);
  final String label;

  static DealKind parse(String s) => DealKind.values.byName(s);
}

enum PaymentMethod {
  cash('Cash'),
  bank('Bank'),
  other('Other');

  const PaymentMethod(this.label);
  final String label;

  static PaymentMethod? parse(String? s) => s == null ? null : PaymentMethod.values.byName(s);
}

enum CommissionMode {
  perKg('per_kg', 'Per kg'),
  percent('percent', 'Percent'),
  fixed('fixed', 'Fixed amount');

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

/// One line of a party's khata, with the running balance after it.
class StatementLine {
  StatementLine({
    required this.entryId,
    required this.date,
    required this.kind,
    required this.note,
    required this.amount,
    required this.balance,
    this.method,
  });

  factory StatementLine.fromJson(Map<String, dynamic> j) => StatementLine(
        entryId: j['entry_id'] as String?,
        date: parseDate(j['entry_date'] as String),
        kind: j['kind'] as String?,
        note: (j['note'] as String?) ?? '',
        method: PaymentMethod.parse(j['method'] as String?),
        amount: toNum(j['amount']),
        balance: toNum(j['balance']),
      );

  /// Null for the "Balance brought forward" line.
  final String? entryId;
  final DateTime date;
  final String? kind;
  final String note;
  final PaymentMethod? method;
  final num amount;
  final num balance;

  bool get isBroughtForward => entryId == null;
  bool get isReversal => kind == 'reversal';
}

/// A raw khata line, used to find which deal or expense it belongs to.
class KhataEntry {
  KhataEntry({
    required this.id,
    required this.partyId,
    required this.date,
    required this.amount,
    required this.kind,
    this.partyName,
    this.note,
    this.method,
    this.dealId,
    this.expenseId,
    this.reversesId,
  });

  factory KhataEntry.fromJson(Map<String, dynamic> j) => KhataEntry(
        id: j['id'] as String,
        partyId: j['party_id'] as String,
        partyName: (j['party'] as Map<String, dynamic>?)?['name'] as String?,
        date: parseDate(j['entry_date'] as String),
        amount: toNum(j['amount']),
        kind: j['kind'] as String,
        note: j['note'] as String?,
        method: PaymentMethod.parse(j['method'] as String?),
        dealId: j['deal_id'] as String?,
        expenseId: j['expense_id'] as String?,
        reversesId: j['reverses_id'] as String?,
      );

  final String id;
  final String partyId;
  final String? partyName;
  final DateTime date;
  final num amount;
  final String kind;
  final String? note;
  final PaymentMethod? method;
  final String? dealId;
  final String? expenseId;
  final String? reversesId;
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
