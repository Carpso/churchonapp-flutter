import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full Strong's Hebrew + Greek lexicons (public domain: Open Scriptures
/// Hebrew Bible Project / Ulrik Petersen e-text of Strong's 1890
/// Concordance), bundled as JSON assets and searched client-side.
class StrongsEntry {
  final String id; // e.g. H3068, G26
  final String word; // original script (Hebrew / Greek)
  final String lemma; // vocalised lemma
  final String morph; // morphology code (Hebrew entries only)
  final String transliteration;
  final String xlit; // modern-style transliteration (Hebrew entries)
  final String definition; // numbered definitions
  final String derivation; // etymology / derivation note
  final String explanation; // combined explanation (Hebrew entries)
  final String kjvRenderings; // KJV translation renderings

  const StrongsEntry({
    required this.id,
    required this.word,
    required this.lemma,
    required this.morph,
    required this.transliteration,
    required this.definition,
    required this.derivation,
    required this.explanation,
    required this.kjvRenderings,
    this.xlit = '',
  });

  factory StrongsEntry.fromJson(Map<String, dynamic> j) => StrongsEntry(
        id: j['i']?.toString() ?? '',
        word: j['w']?.toString() ?? '',
        lemma: j['l']?.toString() ?? '',
        morph: j['m']?.toString() ?? '',
        transliteration: j['t']?.toString() ?? '',
        xlit: j['u']?.toString() ?? '',
        definition: j['d']?.toString() ?? '',
        derivation: j['x']?.toString() ?? '',
        explanation: j['e']?.toString() ?? '',
        kjvRenderings: j['k']?.toString() ?? '',
      );

  bool get isHebrew => id.startsWith('H');

  int get number =>
      int.tryParse(id.replaceFirst(RegExp(r'^[HG]'), '')) ?? 0;

  /// Friendly part-of-speech label from the morphology code.
  String get morphLabel {
    switch (morph) {
      case 'n':
        return 'Noun';
      case 'n-m':
        return 'Noun (masculine)';
      case 'n-f':
        return 'Noun (feminine)';
      case 'n-pr':
        return 'Proper noun';
      case 'n-abs':
        return 'Noun (absolute)';
      case 'v':
        return 'Verb';
      case 'v-ptc':
        return 'Verb (participle)';
      case 'adj':
        return 'Adjective';
      case 'adv':
        return 'Adverb';
      case 'prep':
        return 'Preposition';
      case 'conj':
        return 'Conjunction';
      case 'pron':
        return 'Pronoun';
      case 'p':
        return 'Particle';
      case 'intj':
        return 'Interjection';
      case 'num':
        return 'Numeral';
      case 'art':
        return 'Article';
      default:
        return morph;
    }
  }
}

class StrongsLexicon {
  Map<String, StrongsEntry>? _hebrew;
  Map<String, StrongsEntry>? _greek;

  Future<Map<String, StrongsEntry>> get hebrew async =>
      _hebrew ??= await _load('assets/strongs/hebrew.json');

  Future<Map<String, StrongsEntry>> get greek async =>
      _greek ??= await _load('assets/strongs/greek.json');

  Future<Map<String, StrongsEntry>> _load(String assetPath) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final List<dynamic> list = json.decode(raw);
      return {
        for (final e in list)
          (e as Map<String, dynamic>)['i'].toString(): StrongsEntry.fromJson(e),
      };
    } catch (e) {
      debugPrint('StrongsLexicon load failed for $assetPath: $e');
      return const {};
    }
  }

  /// Lookup by Strong's number, tolerating prefixes and leading zeros:
  /// '3068', 'H3068', 'h 3068', 'G0026' → matching entry.
  Future<StrongsEntry?> byNumber(String input) async {
    var code = input.trim().toUpperCase().replaceAll(' ', '');
    var lang = '';
    if (code.startsWith('H')) {
      lang = 'H';
      code = code.substring(1);
    } else if (code.startsWith('G')) {
      lang = 'G';
      code = code.substring(1);
    }
    final num = int.tryParse(code);
    if (num == null) return null;
    if (lang != 'G') {
      final h = await hebrew;
      final hit = h['H$num'];
      if (hit != null) return hit;
    }
    if (lang != 'H') {
      final g = await greek;
      return g['G$num'];
    }
    return null;
  }

  /// Case/diacritic-insensitive search across word, transliteration,
  /// definition and KJV renderings. Returns best matches first.
  Future<List<StrongsEntry>> search(String query, {int limit = 40}) async {
    final q = _normalize(query);
    if (q.isEmpty) return const [];
    final results = <_Scored>[];
    final h = await hebrew;
    final g = await greek;
    final all = <String, StrongsEntry>{...h, ...g};
    for (final e in all.values) {
      final score = _score(e, q);
      if (score > 0) results.add(_Scored(e, score));
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(limit).map((s) => s.entry).toList();
  }

  /// Curated "popular word studies" (Strong's numbers).
  Future<List<StrongsEntry>> popular() async {
    const ids = [
      'G26', 'G3056', 'G4151', 'G5485', 'G4102', 'G2962', // agape, logos, pneuma, charis, pistis, kurios
      'H7965', 'H2617', 'H157', 'H3519', 'H6944', 'H3068', // shalom, chesed, ahab, kabod, qodesh, YHWH
    ];
    final h = await hebrew;
    final g = await greek;
    return [
      for (final id in ids)
        if (id.startsWith('H') && h[id] != null) h[id]! else if (g[id] != null) g[id]!,
    ];
  }

  static int _score(StrongsEntry e, String q) {
    final t = _normalize(e.transliteration);
    final x = _normalize(e.xlit);
    final w = _normalize(e.word);
    final d = _normalize(e.definition);
    final k = _normalize(e.kjvRenderings);
    if (t == q || x == q || w == q) return 100;
    if (t.startsWith(q) || x.startsWith(q)) return 80;
    if (w.startsWith(q)) return 75;
    if (t.contains(q) || x.contains(q)) return 60;
    if (w.contains(q)) return 55;
    if (d.contains(q)) return 40;
    if (k.contains(q)) return 25;
    return 0;
  }
}

/// Strip diacritics/accents + punctuation so 'agape' matches 'agápē',
/// 'shalom' matches 'shālôm', 'chesed' matches 'ḥeseḏ'.
String _normalize(String s) {
  return _fold(s)
      .split(RegExp(r"[\s\-—:;.,'()·’‘“”+*/]"))
      .join('')
      .replaceAll(RegExp(r'wm\b'), 'm'); // final-mem orthography: shâlôwm → shalom
}

const Map<String, String> _diacriticFold = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'ā': 'a', 'ă': 'a',
  'ą': 'a', 'å': 'a', 'ǎ': 'a', 'æ': 'ae',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ĕ': 'e', 'ė': 'e',
  'ę': 'e', 'ě': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ĭ': 'i', 'į': 'i',
  'ǐ': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ō': 'o', 'ŏ': 'o',
  'ő': 'o', 'ǒ': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ŭ': 'u', 'ů': 'u',
  'ű': 'u', 'ǔ': 'u',
  'ý': 'y', 'ÿ': 'y', 'ŷ': 'y',
  'ç': 's', 'ć': 'c', 'ĉ': 'c', 'ċ': 'c', 'č': 'c',
  'š': 's', 'ś': 's', 'ş': 's', 'ș': 's', 'ṣ': 's',
  'ž': 'z', 'ź': 'z', 'ż': 'z', 'ẓ': 'z',
  'ğ': 'g', 'ǧ': 'g',
  'ñ': 'n', 'ń': 'n', 'ņ': 'n', 'ň': 'n',
  'ḳ': 'k', 'ǩ': 'k',
  'ṭ': 't', 'ť': 't', 'ț': 't', 'ṯ': 't',
  'ḍ': 'd', 'ď': 'd', 'ḏ': 'd',
  'ḥ': 'h', 'ħ': 'h', 'ẖ': 'h',
  'ṛ': 'r', 'ř': 'r', 'ṟ': 'r',
  'ļ': 'l', 'ľ': 'l', 'ł': 'l',
  'ṃ': 'm',
  'ẇ': 'w',
  'ʼ': '', 'ʿ': '', "'": '', '’': '',
  'ᵃ': 'a', 'ᵉ': 'e', 'ᵢ': 'i', 'ᵒ': 'o', 'ᵘ': 'u', 'ᵤ': 'u', 'ᵇ': 'b',
  'ᵈ': 'd', 'ᵍ': 'g', 'ᵏ': 'k', 'ᵐ': 'm', 'ⁿ': 'n', 'ᵖ': 'p', 'ˢ': 's',
  'ᵗ': 't', 'ᵥ': 'v', 'ᵧ': 'y', 'ₐ': 'a', 'ₑ': 'e', 'ₒ': 'o', 'ₓ': 'x',
};

String _fold(String s) {
  final out = StringBuffer();
  for (final c in s.split('')) {
    final folded = _diacriticFold[c];
    if (folded != null) {
      out.write(folded);
    } else {
      out.write(c);
    }
  }
  return out.toString();
}

class _Scored {
  final StrongsEntry entry;
  final int score;
  _Scored(this.entry, this.score);
}

final strongsLexiconProvider = Provider((ref) => StrongsLexicon());

final strongsHebrewProvider = FutureProvider<Map<String, StrongsEntry>>(
  (ref) => ref.watch(strongsLexiconProvider).hebrew,
);

final strongsGreekProvider = FutureProvider<Map<String, StrongsEntry>>(
  (ref) => ref.watch(strongsLexiconProvider).greek,
);

final strongsPopularProvider = FutureProvider<List<StrongsEntry>>(
  (ref) => ref.watch(strongsLexiconProvider).popular(),
);

final strongsSearchProvider =
    FutureProvider.family<List<StrongsEntry>, String>((ref, query) {
  return ref.watch(strongsLexiconProvider).search(query);
});

/// Lookup a Strong's number like 'H3068', 'G26' or '3068'.
final strongsNumberProvider =
    FutureProvider.family<List<StrongsEntry>, String>((ref, input) async {
  final hit = await ref.watch(strongsLexiconProvider).byNumber(input);
  return hit == null ? const [] : [hit];
});