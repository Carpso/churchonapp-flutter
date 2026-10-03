import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One recorded search.
@immutable
class SearchHistoryEntry {
  final String query;

  /// How many times the user has run this exact query. Used to rank a query the
  /// user relies on above one they tried once.
  final int count;
  final DateTime lastUsedAt;

  const SearchHistoryEntry({
    required this.query,
    required this.count,
    required this.lastUsedAt,
  });

  Map<String, dynamic> toJson() => {
        'q': query,
        'c': count,
        't': lastUsedAt.millisecondsSinceEpoch,
      };

  static SearchHistoryEntry? fromJson(Map<String, dynamic> json) {
    final q = json['q'];
    if (q is! String || q.trim().isEmpty) return null;
    return SearchHistoryEntry(
      query: q,
      count: (json['c'] as num?)?.toInt() ?? 1,
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['t'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Case/whitespace-insensitive equality, so "Bible", " bible " and "BIBLE" are
  /// one entry rather than three near-duplicates in the list.
  String get normalized => SearchHistoryService.normalizeQuery(query);

  /// The value dedup compares on. [normalized] deliberately preserves the
  /// user's casing for display, so it must not be compared directly -
  /// doing so made every repeat of a mixed-case query append a new entry.
  String get dedupeKey => normalized.toLowerCase();
}

/// Persists per-surface search history and ranks it.
///
/// ## Why a shared store
///
/// Every search surface used to keep its own list (the universal screen had
/// one, most others had none), so moving between screens lost the history and
/// each surface re-implemented dedup differently. History here is keyed by
/// [scope] - a stable string such as `bible` or `members` - so each surface
/// sees its own list while still being able to borrow the global one for
/// suggestions.
///
/// ## Ranking
///
/// [score] is deliberately a pure static function so the ordering can be unit
/// tested without touching [SharedPreferences].
class SearchHistoryService {
  static const _prefsKey = 'search_history_v2';

  /// Per-surface cap. Beyond this the lowest-ranked entry is dropped, which
  /// keeps the sheet usable on a small screen.
  static const maxPerScope = 12;

  /// Shortest query worth remembering. One or two character searches are almost
  /// always a prefix typo, and storing them floods the list with noise.
  static const minQueryLength = 2;

  /// Cap on the number of scopes retained, least-recently-used evicted first.
  static const maxScopes = 24;

  final SharedPreferences? _prefs;

  SearchHistoryService([SharedPreferences? prefs]) : _prefs = prefs;

  /// Collapses whitespace and trims. Display form is preserved; comparisons
  /// use the lowercased result.
  static String normalizeQuery(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Records a query against a surface, creating or bumping the entry.
  ///
  /// No-ops on empty or too-short input so a stray keystroke submit never
  /// pollutes the list.
  Future<void> record(String scope, String raw) async {
    final query = normalizeQuery(raw);
    if (query.length < minQueryLength) return;

    final prefs = _prefs;
    if (prefs == null) return;

    final all = _readAll(prefs);
    final list = all[scope] ?? <SearchHistoryEntry>[];

    final index = list.indexWhere((e) => e.dedupeKey == query.toLowerCase());
    if (index >= 0) {
      final existing = list[index];
      list[index] = SearchHistoryEntry(
        query: existing.query,
        count: existing.count + 1,
        lastUsedAt: DateTime.now(),
      );
    } else {
      list.add(SearchHistoryEntry(
        query: query,
        count: 1,
        lastUsedAt: DateTime.now(),
      ));
    }

    list.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    all[scope] = list.length > maxPerScope
        ? list.sublist(0, maxPerScope)
        : list;

    _evictScopes(all);
    await _writeAll(prefs, all);
  }

  /// Entries for one surface, most recent first.
  List<SearchHistoryEntry> entriesFor(String scope) {
    final prefs = _prefs;
    if (prefs == null) return const [];
    final list = _readAll(prefs)[scope];
    if (list == null) return const [];
    final sorted = [...list]..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return sorted;
  }

  /// Every entry across every surface, most recent first, paired with the
  /// surface it was recorded on.
  ///
  /// The pairing matters for suggestions: a query run on "Bible" should be
  /// offered on "Sermons" labelled as coming from Bible, which is what makes
  /// cross-surface suggestions intelligible rather than mysterious.
  List<({String scope, SearchHistoryEntry entry})> allScopedEntries() {
    final prefs = _prefs;
    if (prefs == null) return const [];
    final out = <({String scope, SearchHistoryEntry entry})>[];
    _readAll(prefs).forEach((scope, list) {
      for (final e in list) {
        out.add((scope: scope, entry: e));
      }
    });
    out.sort((a, b) => b.entry.lastUsedAt.compareTo(a.entry.lastUsedAt));
    return out;
  }

  /// Every entry across every surface, most recent first.
  List<SearchHistoryEntry> allEntries() =>
      [for (final e in allScopedEntries()) e.entry];

  /// Entries whose text matches [query], best match first.
  List<SearchHistoryEntry> matches(String query, {String? scope, int limit = 6}) {
    final needle = normalizeQuery(query).toLowerCase();
    if (needle.isEmpty) return const [];
    final source = scope == null ? allEntries() : entriesFor(scope);
    final hit = source.where((e) => e.dedupeKey.contains(needle)).toList()
      ..sort((a, b) => score(b, needle).compareTo(score(a, needle)));
    return hit.take(limit).toList();
  }

  /// Like [matches], but keeps the originating scope.
  List<({String scope, SearchHistoryEntry entry})> matchesScoped(
    String query, {
    String? scope,
    int limit = 6,
  }) {
    final needle = normalizeQuery(query).toLowerCase();
    if (needle.isEmpty) return const [];
    final source = scope == null ? allScopedEntries() : null;
    final scoped = source ??
        [
          for (final e in entriesFor(scope!))
            (scope: scope, entry: e)
        ];
    final hit = scoped
        .where((e) => e.entry.dedupeKey.contains(needle))
        .toList()
      ..sort((a, b) => score(b.entry, needle).compareTo(score(a.entry, needle)));
    return hit.take(limit).toList();
  }

  /// Removes one entry from one surface.
  Future<void> remove(String scope, String query) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final all = _readAll(prefs);
    final list = all[scope];
    if (list == null) return;
    final target = normalizeQuery(query).toLowerCase();
    list.removeWhere((e) => e.dedupeKey == target);
    if (list.isEmpty) {
      all.remove(scope);
    } else {
      all[scope] = list;
    }
    await _writeAll(prefs, all);
  }

  /// Clears one surface, or everything when [scope] is null.
  Future<void> clear({String? scope}) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final all = _readAll(prefs);
    if (scope == null) {
      all.clear();
    } else {
      all.remove(scope);
    }
    await _writeAll(prefs, all);
  }

  /// Relevance score for [entry] against lowercased [needle]. Higher is better.
  ///
  /// Prefix matches beat mid-word matches, a prefix beats a plain substring,
  /// repeat usage beats a one-off, and recency breaks ties. Pure so the
  /// ordering is testable without a plugin.
  static int score(SearchHistoryEntry entry, String needle) {
    final text = entry.normalized.toLowerCase();
    var value = 0;

    if (text == needle) {
      value += 1000;
    } else if (text.startsWith(needle)) {
      // Shorter candidate wins: typing "faith" should favour "Faith" over
      // "Faith Declarations".
      value += 500 - text.length.clamp(0, 60);
    } else if (wordPrefix(text, needle)) {
      value += 250;
    } else if (text.contains(needle)) {
      value += 100;
    }

    value += entry.count.clamp(0, 25) * 8;

    final ageDays = DateTime.now().difference(entry.lastUsedAt).inHours / 24;
    value += (30 - ageDays).clamp(0, 30).toInt();

    return value;
  }

  /// True when [needle] starts any whitespace-delimited word in [text], so
  /// "grace" matches "Amazing Grace".
  static bool wordPrefix(String text, String needle) {
    if (needle.isEmpty) return false;
    for (final word in text.split(' ')) {
      if (word.startsWith(needle)) return true;
    }
    return false;
  }

  Map<String, List<SearchHistoryEntry>> _readAll(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, List<SearchHistoryEntry>>{};
      decoded.forEach((key, value) {
        if (value is! List) return;
        final list = <SearchHistoryEntry>[];
        for (final item in value) {
          if (item is Map) {
            final entry = SearchHistoryEntry.fromJson(
              Map<String, dynamic>.from(item),
            );
            if (entry != null) list.add(entry);
          }
        }
        if (list.isNotEmpty) out[key.toString()] = list;
      });
      return out;
    } catch (e) {
      debugPrint('[SearchHistory] corrupt store ignored: $e');
      return {};
    }
  }

  Future<void> _writeAll(
    SharedPreferences prefs,
    Map<String, List<SearchHistoryEntry>> all,
  ) async {
    try {
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          for (final entry in all.entries)
            entry.key: [for (final e in entry.value) e.toJson()],
        }),
      );
    } catch (e) {
      debugPrint('[SearchHistory] write failed (non-fatal): $e');
    }
  }

  /// Drops the least recently used scopes once [maxScopes] is exceeded.
  void _evictScopes(Map<String, List<SearchHistoryEntry>> all) {
    if (all.length <= maxScopes) return;
    final keys = all.keys.toList()
      ..sort((a, b) {
        final aAt = all[a]!.first.lastUsedAt;
        final bAt = all[b]!.first.lastUsedAt;
        return bAt.compareTo(aAt);
      });
    for (final key in keys.sublist(maxScopes)) {
      all.remove(key);
    }
  }
}