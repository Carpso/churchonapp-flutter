import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App languages. English is the default; Zambian local languages are
/// first-pass curated dictionaries (untranslated strings fall back to
/// English via [tr]).
enum AppLanguage {
  english('en', 'English', 'English'),
  bemba('bem', 'Bemba', 'Icibemba'),
  nyanja('nya', 'Nyanja', 'Chinyanja'),
  lozi('loz', 'Lozi', 'Silozi'),
  tonga('tog', 'Tonga', 'Chitonga');

  const AppLanguage(this.code, this.name, this.nativeName);

  final String code;
  final String name;
  final String nativeName;

  static AppLanguage fromCode(String? code) {
    for (final l in AppLanguage.values) {
      if (l.code == code) return l;
    }
    return AppLanguage.english;
  }
}

const _prefsKey = 'app_language';

class AppLanguageNotifier extends Notifier<AppLanguage> {
  @override
  AppLanguage build() {
    return AppLanguage.english;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppLanguage.fromCode(prefs.getString(_prefsKey));
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, language.code);
  }
}

final appLanguageProvider =
    NotifierProvider<AppLanguageNotifier, AppLanguage>(AppLanguageNotifier.new);