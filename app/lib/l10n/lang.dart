import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The languages the app is shown in. The ledger itself stores no sentences
/// (see khata_text.dart), so switching changes every line's wording too.
enum AppLang {
  romanUrdu('ru', 'Roman Urdu'),
  english('en', 'English');

  const AppLang(this.code, this.label);
  final String code;

  /// The language's own name, the same in either language.
  final String label;
}

/// The language in use. The app rebuilds from the top when it changes.
final appLang = ValueNotifier<AppLang>(AppLang.romanUrdu);

const _prefKey = 'lang';

/// Reads the saved choice; Roman Urdu when nothing is saved yet.
Future<void> loadLang() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefKey);
    appLang.value = AppLang.values.firstWhere((l) => l.code == code, orElse: () => AppLang.romanUrdu);
  } catch (_) {
    // No storage (tests, private mode): keep the default.
  }
}

Future<void> setLang(AppLang lang) async {
  appLang.value = lang;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, lang.code);
  } catch (_) {}
}

bool get isEnglish => appLang.value == AppLang.english;

/// Picks the text for the current language: `tr('Paise mile', 'Money received')`.
/// Both wordings sit side by side so neither can drift or go missing.
String tr(String romanUrdu, String english) => isEnglish ? english : romanUrdu;
