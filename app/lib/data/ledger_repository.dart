import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../util/format.dart';
import 'deal_draft.dart';
import 'models.dart';

/// The only place the app talks to Supabase.
///
/// Reads come straight from tables (row-level security limits them to the
/// signed-in user). Every write is a call to a database function, which holds
/// the bookkeeping rules; the app never inserts or updates rows itself.
class LedgerRepository {
  LedgerRepository(this._db);

  final SupabaseClient _db;

  /// The last result of each screen's load, so a screen opened again shows
  /// it at once and refreshes in the background.
  final cache = <String, Object?>{};

  /// Ticks after every change to the khata: a save in the app, or one from
  /// the WhatsApp bot that arrives live. Screens listen and refresh.
  final changes = ValueNotifier<int>(0);

  void markChanged() => changes.value++;

  /// Forgets everything loaded, e.g. on sign out.
  void clearCache() => cache.clear();

  Future<dynamic> _write(String fn, {Map<String, dynamic>? params}) async {
    final result = await _db.rpc(fn, params: params);
    markChanged();
    return result;
  }

  // ---------------- Live changes ----------------

  RealtimeChannel? _live;
  Timer? _liveDebounce;

  /// Listens for rows changed outside the app (the WhatsApp bot), so open
  /// screens update by themselves. Row-level security limits the events to
  /// the signed-in user's own rows.
  void startLive() {
    if (_live != null) return;
    final channel = _db.channel('khata-live');
    for (final table in const ['khata_entries', 'deals', 'expenses', 'stock_adjustments', 'parties', 'items']) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        // One save touches several tables; refresh once for all of them.
        callback: (_) {
          _liveDebounce?.cancel();
          _liveDebounce = Timer(const Duration(milliseconds: 500), markChanged);
        },
      );
    }
    _live = channel..subscribe();
  }

  Future<void> stopLive() async {
    _liveDebounce?.cancel();
    final channel = _live;
    _live = null;
    if (channel != null) await _db.removeChannel(channel);
  }

  static const _dealSelect = '*, '
      'party:parties!deals_party_id_fkey(name), '
      'buyer:parties!deals_buyer_id_fkey(name), '
      'item:items(name_en)';

  // ---------------- Parties ----------------

  Future<List<PartyBalance>> partyBalances() async {
    final rows = await _db.from('party_balances').select().order('name');
    return [for (final r in rows) PartyBalance.fromJson(r)];
  }

  Future<Party> party(String id) async {
    final row = await _db.from('parties').select().eq('id', id).single();
    return Party.fromJson(row);
  }

  /// Active parties, for pickers.
  Future<List<Party>> activeParties() async {
    final rows = await _db.from('parties').select().isFilter('archived_at', null).order('name');
    return [for (final r in rows) Party.fromJson(r)];
  }

  Future<String> createParty({
    required String name,
    required PartyType type,
    String? phone,
    String? whatsapp,
    String? city,
    String? notes,
    num openingBalance = 0,
    DateTime? openingDate,
  }) async {
    final id = await _write('create_party', params: {
      'p_name': name,
      'p_type': type.name,
      'p_phone': _blankToNull(phone),
      'p_whatsapp': _blankToNull(whatsapp),
      'p_city': _blankToNull(city),
      'p_notes': _blankToNull(notes),
      'p_opening_balance': openingBalance,
      'p_opening_date': openingDate == null ? null : isoDate(openingDate),
    });
    return id as String;
  }

  Future<void> updateParty(Party p, {
    required String name,
    required PartyType type,
    String? phone,
    String? whatsapp,
    String? city,
    String? notes,
  }) =>
      _write('update_party', params: {
        'p_id': p.id,
        'p_name': name,
        'p_type': type.name,
        'p_phone': _blankToNull(phone),
        'p_whatsapp': _blankToNull(whatsapp),
        'p_city': _blankToNull(city),
        'p_notes': _blankToNull(notes),
      });

  Future<void> setPartyArchived(String id, bool archived) =>
      _write('set_party_archived', params: {'p_id': id, 'p_archived': archived});

  Future<List<KhataLine>> statement(String partyId, {DateTime? from, DateTime? to, bool includeCancelled = false}) async {
    final rows = await _db.rpc('party_statement', params: {
      'p_party_id': partyId,
      'p_from': from == null ? null : isoDate(from),
      'p_to': to == null ? null : isoDate(to),
      'p_include_cancelled': includeCancelled,
    }) as List;
    return [for (final r in rows) KhataLine.fromJson(r as Map<String, dynamic>)];
  }

  /// The latest khata lines across all parties, newest first. Cancelled lines are left out.
  Future<List<KhataLine>> recentLines({int limit = 10}) async {
    final rows = await _db
        .from('khata_lines')
        .select()
        .eq('cancelled', false)
        .order('created_at', ascending: false)
        .order('seq', ascending: false)
        .limit(limit);
    return [for (final r in rows) KhataLine.fromJson(r)];
  }

  // ---------------- Payments ----------------

  /// [received] true = the party paid us, false = we paid the party.
  Future<void> recordPayment({
    required String partyId,
    required bool received,
    required num amount,
    required DateTime date,
    required PaymentMethod method,
    String? note,
  }) =>
      _write('record_payment', params: {
        'p_party_id': partyId,
        'p_direction': received ? 'in' : 'out',
        'p_amount': amount,
        'p_date': isoDate(date),
        'p_method': method.name,
        'p_note': _blankToNull(note),
      });

  /// Positive [amount] = the party owes us more.
  Future<void> recordAdjustment({
    required String partyId,
    required num amount,
    required String note,
    required DateTime date,
  }) =>
      _write('record_adjustment', params: {
        'p_party_id': partyId,
        'p_amount': amount,
        'p_note': note,
        'p_date': isoDate(date),
      });

  Future<void> reverseEntry(String entryId, {String? reason}) =>
      _write('reverse_entry', params: {'p_entry_id': entryId, 'p_reason': _blankToNull(reason)});

  // ---------------- Cloth types & stock ----------------

  Future<List<Item>> activeItems() async {
    final rows = await _db.from('items').select().isFilter('archived_at', null).order('name_en');
    return [for (final r in rows) Item.fromJson(r)];
  }

  Future<String> createItem(String nameEn, String? nameUr) async =>
      await _write('create_item', params: {'p_name_en': nameEn, 'p_name_ur': _blankToNull(nameUr)}) as String;

  Future<void> updateItem(String id, String nameEn, String? nameUr) =>
      _write('update_item', params: {'p_id': id, 'p_name_en': nameEn, 'p_name_ur': _blankToNull(nameUr)});

  Future<void> setItemArchived(String id, bool archived) =>
      _write('set_item_archived', params: {'p_id': id, 'p_archived': archived});

  Future<List<StockRow>> stockSummary() async {
    final rows = await _db.rpc('stock_summary') as List;
    return [for (final r in rows) StockRow.fromJson(r as Map<String, dynamic>)];
  }

  /// [weightKg] is always positive; [kind] says whether stock came in or went out.
  /// Stock coming in needs [costPerKg].
  Future<void> recordStockAdjustment({
    required String itemId,
    required StockAdjustmentKind kind,
    required num weightKg,
    num? costPerKg,
    required DateTime date,
    String? reason,
  }) =>
      _write('record_stock_adjustment', params: {
        'p_item_id': itemId,
        'p_kind': kind.db,
        'p_weight_kg': weightKg,
        'p_cost_per_kg': costPerKg,
        'p_date': isoDate(date),
        'p_reason': _blankToNull(reason),
      });

  Future<void> cancelStockAdjustment(String id, {String? reason}) =>
      _write('cancel_stock_adjustment', params: {'p_id': id, 'p_reason': reason});

  /// One cloth type's stock register, oldest first.
  Future<List<StockMove>> stockHistory(String itemId) async {
    final rows = await _db.rpc('stock_history', params: {'p_item_id': itemId}) as List;
    return [for (final r in rows) StockMove.fromJson(r as Map<String, dynamic>)];
  }

  // ---------------- Deals ----------------

  Future<List<Deal>> deals({DealKind? kind, int limit = 200}) async {
    var query = _db.from('deals').select('$_dealSelect, deal_commissions(*)');
    if (kind != null) query = query.eq('kind', kind.name);
    final rows = await query
        .order('deal_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return [for (final r in rows) Deal.fromJson(r)];
  }

  Future<Deal> deal(String id) async {
    final row = await _db
        .from('deals')
        .select('$_dealSelect, deal_costs(*, paid_to:parties!deal_costs_paid_to_id_fkey(name)), deal_commissions(*)')
        .eq('id', id)
        .single();
    return Deal.fromJson(row);
  }

  /// Khata lines written by a deal, in the order they were written.
  Future<List<KhataLine>> dealLines(String dealId) async {
    final rows = await _db.from('khata_lines').select().eq('deal_id', dealId).order('seq');
    return [for (final r in rows) KhataLine.fromJson(r)];
  }

  Future<String> recordDeal(DealDraft draft) async =>
      await _write('record_deal', params: {'p': draft.toJson()}) as String;

  /// Edits a deal: the old one is cancelled and the corrected one recorded.
  Future<String> replaceDeal(String dealId, DealDraft draft) async =>
      await _write('replace_deal', params: {'p_deal_id': dealId, 'p': draft.toJson()}) as String;

  Future<void> cancelDeal(String dealId, {String? reason}) =>
      _write('cancel_deal', params: {'p_deal_id': dealId, 'p_reason': _blankToNull(reason)});

  // ---------------- Expenses ----------------

  Future<List<Expense>> expenses({int limit = 200}) async {
    final rows = await _db
        .from('expenses')
        .select('*, paid_to:parties(name)')
        .order('expense_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return [for (final r in rows) Expense.fromJson(r)];
  }

  /// [paidToId] set = owed to that party on credit; null = paid in cash.
  Future<void> recordExpense({
    required String category,
    required num amount,
    required DateTime date,
    String? paidToId,
    String? notes,
  }) =>
      _write('record_expense', params: {
        'p_category': category,
        'p_amount': amount,
        'p_date': isoDate(date),
        'p_paid_to_id': paidToId,
        'p_notes': _blankToNull(notes),
      });

  Future<void> cancelExpense(String id, {String? reason}) =>
      _write('cancel_expense', params: {'p_expense_id': id, 'p_reason': _blankToNull(reason)});

  /// Categories used before, most recent first, to suggest while typing.
  Future<List<String>> expenseCategories() async {
    final rows = await _db.from('expenses').select('category').order('created_at', ascending: false).limit(300);
    return {for (final r in rows) r['category'] as String}.toList();
  }

  // ---------------- Reports ----------------

  Future<ProfitReport> profit(DateTime from, DateTime to) async {
    final rows = await _db.rpc('profit_report', params: {'p_from': isoDate(from), 'p_to': isoDate(to)}) as List;
    return ProfitReport.fromJson(rows.single as Map<String, dynamic>);
  }

  static String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
}
