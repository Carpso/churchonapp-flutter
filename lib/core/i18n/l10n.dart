import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_languages.dart';
import 'translations.dart';

/// Localization helper. Usage: `context.tr('Home')`.
///
/// Reads the active [AppLanguage] from the nearest [ProviderScope] and
/// falls back to English when a key has no translation yet.
extension AppL10n on BuildContext {
  AppLanguage get appLanguage =>
      ProviderScope.containerOf(this, listen: false).read(appLanguageProvider);

  String tr(String key) => trFor(appLanguage, key);
}

String trFor(AppLanguage language, String key) => tr(language, key);