import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the app locale and persists the user's choice to SharedPreferences.
///
/// A `null` locale means "use the system default".
class LocaleController extends ChangeNotifier {
  static const _key = 'app_locale';

  Locale? _locale;

  /// The current locale, or `null` (= follow system).
  Locale? get locale => _locale;

  /// Loads the saved locale from disk. Call once before [runApp].
  Future<void> loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    if (code != null && code.isNotEmpty) {
      _locale = Locale(code);
    }
    notifyListeners();
  }

  /// Sets the app locale and persists it. Pass `null` to follow system.
  Future<void> setLocale(Locale? newLocale) async {
    if (_locale == newLocale) return;
    _locale = newLocale;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (newLocale != null) {
      await prefs.setString(_key, newLocale.languageCode);
    } else {
      await prefs.remove(_key);
    }
  }

  /// Removes the persisted locale (revert to system default).
  Future<void> clearLocale() async => setLocale(null);
}
