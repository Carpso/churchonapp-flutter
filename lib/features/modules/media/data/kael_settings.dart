import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How long Kael's answers should be.
enum KaelAnswerLength {
  short('Short'),
  balanced('Balanced'),
  detailed('Detailed');

  const KaelAnswerLength(this.label);
  final String label;

  static KaelAnswerLength fromName(String? name) {
    for (final v in KaelAnswerLength.values) {
      if (v.name == name) return v;
    }
    return KaelAnswerLength.balanced;
  }
}

/// The voice Kael should use.
enum KaelTone {
  pastoral('Pastoral'),
  concise('Concise'),
  teacher('Teacher');

  const KaelTone(this.label);
  final String label;

  static KaelTone fromName(String? name) {
    for (final v in KaelTone.values) {
      if (v.name == name) return v;
    }
    return KaelTone.pastoral;
  }
}

/// Translations offered as a *preference* Kael should quote from. This is a
/// model directive, not a resolver — it does not need to be locally available.
const Map<String, String> kKaelTranslations = {
  'kjv': 'King James Version (KJV)',
  'nkjv': 'New King James Version (NKJV)',
  'niv': 'New International Version (NIV)',
  'esv': 'English Standard Version (ESV)',
  'nlt': 'New Living Translation (NLT)',
  'web': 'World English Bible (WEB)',
  'asv': 'American Standard Version (ASV)',
  'bbe': 'Bible in Basic English (BBE)',
};

/// User-tunable Kael preferences, persisted locally in SharedPreferences.
class KaelSettings {
  final KaelAnswerLength answerLength;
  final KaelTone tone;
  final String preferredTranslation;
  final bool includeReferences;

  const KaelSettings({
    required this.answerLength,
    required this.tone,
    required this.preferredTranslation,
    required this.includeReferences,
  });

  static const KaelSettings defaults = KaelSettings(
    answerLength: KaelAnswerLength.balanced,
    tone: KaelTone.pastoral,
    preferredTranslation: 'kjv',
    includeReferences: true,
  );

  KaelSettings copyWith({
    KaelAnswerLength? answerLength,
    KaelTone? tone,
    String? preferredTranslation,
    bool? includeReferences,
  }) {
    return KaelSettings(
      answerLength: answerLength ?? this.answerLength,
      tone: tone ?? this.tone,
      preferredTranslation: preferredTranslation ?? this.preferredTranslation,
      includeReferences: includeReferences ?? this.includeReferences,
    );
  }

  String get translationLabel =>
      kKaelTranslations[preferredTranslation] ?? preferredTranslation.toUpperCase();

  /// Extra fields merged into the `userContext` object of the kael-ai payload.
  /// Unknown keys are tolerated by the Edge Function, so this is safe to send
  /// even before server-side support lands.
  Map<String, dynamic> toRequestOptions() => {
        'kael_answer_length': answerLength.name,
        'kael_tone': tone.name,
        'kael_preferred_translation': preferredTranslation,
        'kael_include_references': includeReferences,
      };

  /// Human-readable directive sent as the optional top-level `system` field.
  /// The Edge Function currently ignores unknown top-level fields.
  String toSystemDirective() {
    final buffer = StringBuffer()
      ..write('User preferences — keep replies ${answerLength.label.toLowerCase()}.')
      ..write(' Use a ${tone.label.toLowerCase()} tone.')
      ..write(' Prefer quoting the $translationLabel translation.');
    if (includeReferences) {
      buffer.write(' Always include scripture references.');
    } else {
      buffer.write(' Do not include scripture references unless asked.');
    }
    return buffer.toString();
  }
}

class _Prefs {
  static const answerLength = 'kael_answer_length';
  static const tone = 'kael_tone';
  static const translation = 'kael_preferred_translation';
  static const references = 'kael_include_references';
}

class KaelSettingsNotifier extends Notifier<KaelSettings> {
  @override
  KaelSettings build() => KaelSettings.defaults;

  /// Hydrates from SharedPreferences. Safe to call on screen init.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = KaelSettings(
        answerLength: KaelAnswerLength.fromName(prefs.getString(_Prefs.answerLength)),
        tone: KaelTone.fromName(prefs.getString(_Prefs.tone)),
        preferredTranslation:
            prefs.getString(_Prefs.translation) ?? KaelSettings.defaults.preferredTranslation,
        includeReferences:
            prefs.getBool(_Prefs.references) ?? KaelSettings.defaults.includeReferences,
      );
    } catch (_) {
      // Keep defaults — a broken prefs store must never break chat.
    }
  }

  Future<void> setAnswerLength(KaelAnswerLength value) async {
    state = state.copyWith(answerLength: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_Prefs.answerLength, value.name);
  }

  Future<void> setTone(KaelTone value) async {
    state = state.copyWith(tone: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_Prefs.tone, value.name);
  }

  Future<void> setPreferredTranslation(String code) async {
    state = state.copyWith(preferredTranslation: code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_Prefs.translation, code);
  }

  Future<void> setIncludeReferences(bool value) async {
    state = state.copyWith(includeReferences: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_Prefs.references, value);
  }
}

final kaelSettingsProvider =
    NotifierProvider<KaelSettingsNotifier, KaelSettings>(KaelSettingsNotifier.new);
