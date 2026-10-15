import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0.##', 'en_US');
final _weight = NumberFormat('#,##0.###', 'en_US');
final _date = DateFormat('d MMM yyyy');
final _shortDate = DateFormat('d MMM');

/// 120000 -> "Rs 120,000". Always positive; the caller shows the direction.
String money(num value) => 'Rs ${_money.format(value.abs())}';

/// 120000 -> "120,000", keeping the sign.
String plainNumber(num value) => _money.format(value);

String kg(num value) => '${_weight.format(value)} kg';

String formatDate(DateTime d) => _date.format(d);

String formatShortDate(DateTime d) => _shortDate.format(d);

/// Dates go to the database as 'YYYY-MM-DD' (no time, no timezone).
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDate(String s) => DateTime.parse(s);

/// Reads a number typed by the user. Accepts "1,20,000", " 500 ", "2.5".
/// Returns null for empty or invalid input.
num? parseNumber(String? input) {
  if (input == null) return null;
  final cleaned = input.replaceAll(',', '').trim();
  if (cleaned.isEmpty) return null;
  return num.tryParse(cleaned);
}

/// Numeric columns arrive from PostgREST as JSON numbers, or as strings for
/// very large values. Both become a num here.
num toNum(Object? value) {
  if (value == null) return 0;
  if (value is num) return value;
  return num.parse(value.toString());
}

num? toNumOrNull(Object? value) => value == null ? null : toNum(value);

/// Rounds to paisa the same way the database does (half away from zero).
num roundMoney(num value) => (value * 100).round() / 100;

/// What a balance means, in the trader's words.
///   positive: the party owes us   -> "Lena hai" (we will receive)
///   negative: we owe the party    -> "Dena hai" (we will pay)
String balanceLabel(num balance) {
  if (balance > 0) return 'Lena hai';
  if (balance < 0) return 'Dena hai';
  return 'Hisaab barabar';
}
