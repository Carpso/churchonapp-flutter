import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:church_on_app/core/services/search_history_service.dart';
import 'package:church_on_app/core/services/search_suggestion_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late SearchHistoryService history;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    history = SearchHistoryService(prefs);
  });

  group('normalizeQuery', () {
    test('trims and collapses internal whitespace', () {
      expect(SearchHistoryService.normalizeQuery('  Bible   Study '),
          'Bible Study');
    });

    test('is idempotent', () {
      const raw = '  a   b  ';
      final once = SearchHistoryService.normalizeQuery(raw);
      expect(SearchHistoryService.normalizeQuery(once), once);
    });
  });

  group('record', () {
    test('ignores empty and single-character queries', () async {
      await history.record('bible', '');
      await history.record('bible', '   ');
      await history.record('bible', 'a');
      expect(history.entriesFor('bible'), isEmpty);
    });

    test('persists a first query with count 1', () async {
      await history.record('bible', 'Faith');
      final entries = history.entriesFor('bible');
      expect(entries, hasLength(1));
      expect(entries.single.query, 'Faith');
      expect(entries.single.count, 1);
    });

    test('bumps count rather than duplicating on a repeat', () async {
      await history.record('bible', 'Faith');
      await history.record('bible', 'Faith');
      final entries = history.entriesFor('bible');
      expect(entries, hasLength(1));
      expect(entries.single.count, 2);
    });

    test('treats case and whitespace variants as one entry', () async {
      await history.record('bible', 'Faith');
      await history.record('bible', '  FAITH  ');
      final entries = history.entriesFor('bible');
      expect(entries, hasLength(1));
      expect(entries.single.count, 2);
    });

    test('scopes are independent', () async {
      await history.record('bible', 'Faith');
      await history.record('members', 'Faith');
      expect(history.entriesFor('bible'), hasLength(1));
      expect(history.entriesFor('members'), hasLength(1));
      expect(history.allScopedEntries(), hasLength(2));
    });

    test('caps the list per scope, dropping the oldest', () async {
      for (var i = 0; i < SearchHistoryService.maxPerScope + 5; i++) {
        await history.record('bible', 'query $i');
      }
      final entries = history.entriesFor('bible');
      expect(entries.length, SearchHistoryService.maxPerScope);
      // Most recent kept.
      expect(entries.first.query, contains('${SearchHistoryService.maxPerScope + 4}'));
    });
  });

  group('remove and clear', () {
    test('remove drops only the matching entry', () async {
      await history.record('bible', 'Faith');
      await history.record('bible', 'Grace');
      await history.remove('bible', 'faith');
      final entries = history.entriesFor('bible');
      expect(entries, hasLength(1));
      expect(entries.single.query, 'Grace');
    });

    test('removing the last entry drops the scope entirely', () async {
      await history.record('bible', 'Faith');
      await history.remove('bible', 'Faith');
      expect(history.entriesFor('bible'), isEmpty);
      expect(history.allScopedEntries(), isEmpty);
    });

    test('clear with a scope leaves other scopes intact', () async {
      await history.record('bible', 'Faith');
      await history.record('members', 'Grace');
      await history.clear(scope: 'bible');
      expect(history.entriesFor('bible'), isEmpty);
      expect(history.entriesFor('members'), hasLength(1));
    });

    test('clear with no scope empties everything', () async {
      await history.record('bible', 'Faith');
      await history.record('members', 'Grace');
      await history.clear();
      expect(history.allScopedEntries(), isEmpty);
    });
  });

  group('score', () {
    SearchHistoryEntry entry(String q, {int count = 1, int hoursAgo = 0}) =>
        SearchHistoryEntry(
          query: q,
          count: count,
          lastUsedAt: DateTime.now().subtract(Duration(hours: hoursAgo)),
        );

    test('exact match outranks prefix, which outranks substring', () {
      final exact = SearchHistoryService.score(entry('faith'), 'faith');
      final prefix = SearchHistoryService.score(entry('faith'), 'faith');
      final substring = SearchHistoryService.score(entry('living faith'), 'faith');
      expect(exact, greaterThanOrEqualTo(prefix));
      expect(prefix, greaterThan(substring));
    });

    test('a word-prefix match beats a mid-word match', () {
      final wordStart = SearchHistoryService.score(entry('Amazing grace'), 'grace');
      final midWord = SearchHistoryService.score(entry('Disgrace'), 'grace');
      expect(wordStart, greaterThan(midWord));
    });

    test('a shorter prefix beats a longer one', () {
      final short = SearchHistoryService.score(entry('Faith'), 'faith');
      final long = SearchHistoryService.score(entry('Faith Declarations'), 'faith');
      expect(short, greaterThan(long));
    });

    test('more uses outrank fewer at equal relevance', () {
      final once = SearchHistoryService.score(entry('faith', count: 1), 'faith');
      final often = SearchHistoryService.score(entry('faith', count: 5), 'faith');
      expect(often, greaterThan(once));
    });

    test('recency breaks ties', () {
      final old = SearchHistoryService.score(entry('faith', hoursAgo: 72), 'faith');
      final fresh = SearchHistoryService.score(entry('faith', hoursAgo: 0), 'faith');
      expect(fresh, greaterThan(old));
    });

    test('non-matching text scores low but not negative', () {
      expect(SearchHistoryService.score(entry('zzzz', hoursAgo: 1000), 'faith'),
          greaterThanOrEqualTo(0));
    });
  });

  group('wordPrefix', () {
    test('matches at a word boundary', () {
      expect(SearchHistoryService.wordPrefix('amazing grace today', 'grace'), isTrue);
    });
    test('does not match mid-word', () {
      expect(SearchHistoryService.wordPrefix('disgraceful', 'grace'), isFalse);
    });
    test('empty needle is false', () {
      expect(SearchHistoryService.wordPrefix('anything', ''), isFalse);
    });
  });

  group('corrupt store', () {
    test('is ignored rather than throwing', () async {
      await prefs.setString('search_history_v2', 'not json at all');
      final fresh = SearchHistoryService(prefs);
      expect(fresh.entriesFor('bible'), isEmpty);
      expect(fresh.allScopedEntries(), isEmpty);
    });

    test('a record over a corrupt store recovers', () async {
      await prefs.setString('search_history_v2', '{{{');
      final fresh = SearchHistoryService(prefs);
      await fresh.record('bible', 'Faith');
      expect(fresh.entriesFor('bible'), hasLength(1));
    });
  });

  group('SearchSuggestionService', () {
    late SearchSuggestionService service;

    setUp(() {
      service = SearchSuggestionService(history);
    });

    test('idle suggestions on a cold surface surface curated terms', () {
      final rows = service.idleSuggestions(SearchScope.bible);
      expect(rows, isNotEmpty);
      expect(
        rows.any((r) => r.kind == SearchSuggestionKind.popular),
        isTrue,
      );
    });

    test('the universal scope has curated terms, not an empty cold state', () {
      final rows = service.idleSuggestions(SearchScope.universal);
      expect(rows, isNotEmpty);
    });

    test('own-surface history outranks curated terms', () async {
      await history.record('bible', 'Zephaniah');
      final rows = service.idleSuggestions(SearchScope.bible);
      expect(rows.first.kind, SearchSuggestionKind.history);
      expect(rows.first.text, 'Zephaniah');
    });

    test('history from another surface is offered and labelled', () async {
      await history.record('members', 'Choir');
      final rows = service.idleSuggestions(SearchScope.bible);
      final cross = rows.firstWhere(
        (r) => r.kind == SearchSuggestionKind.crossHistory,
      );
      expect(cross.text, 'Choir');
      expect(cross.contextLabel, 'Members');
    });

    test('no duplicates when the same text exists in two scopes', () async {
      await history.record('bible', 'Faith');
      await history.record('members', 'Faith');
      final rows = service.idleSuggestions(SearchScope.bible);
      final faithRows = rows.where((r) => r.text.toLowerCase() == 'faith');
      expect(faithRows, hasLength(1));
    });

    test('query suggestions only include matching text', () {
      final rows = service.querySuggestions(SearchScope.bible, 'gra');
      expect(rows, isNotEmpty);
      expect(rows.every((r) => r.text.toLowerCase().contains('gra')), isTrue);
    });

    test('caller-supplied entities appear as entity rows', () {
      final rows = service.idleSuggestions(
        SearchScope.members,
        entities: ['Alice Mwamba', 'Bob Chirwa'],
      );
      final entity = rows.firstWhere((r) => r.kind == SearchSuggestionKind.entity);
      expect(entity.text, 'Alice Mwamba');
    });

    test('limit is respected', () {
      final rows = service.idleSuggestions(SearchScope.bible, limit: 3);
      expect(rows.length, lessThanOrEqualTo(3));
    });

    test('every scope has a label and a unique id', () {
      final ids = SearchScope.values.map((s) => s.id).toSet();
      expect(ids.length, SearchScope.values.length);
      for (final scope in SearchScope.values) {
        expect(scope.label, isNotEmpty);
      }
    });

    test('labelForScope degrades gracefully for an unknown scope', () {
      expect(
        SearchSuggestionService.labelForScope('a_scope_from_a_future_build'),
        'Recent',
      );
    });
  });
}