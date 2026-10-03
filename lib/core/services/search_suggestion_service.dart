import 'package:flutter/material.dart';

import 'search_history_service.dart';

/// Where a search is being run.
///
/// The scope drives which popular terms and which other surfaces' history are
/// offered, which is what makes suggestions feel like they belong to the
/// screen you are actually on.
enum SearchScope {
  universal('universal', 'Search', Icons.search),
  bible('bible', 'Bible', Icons.menu_book),
  sermons('sermons', 'Sermons', Icons.headphones),
  members('members', 'Members', Icons.people),
  marketplace('marketplace', 'Marketplace', Icons.shopping_bag),
  events('events', 'Events', Icons.calendar_month),
  prayer('prayer', 'Prayer', Icons.volunteer_activism),
  testimonies('testimonies', 'Testimonies', Icons.auto_awesome),
  quiz('quiz', 'Bible Quiz', Icons.emoji_events),
  giving('giving', 'Giving', Icons.favorite),
  rides('rides', 'Carpso Ride', Icons.directions_car),
  places('places', 'Places', Icons.place),
  church('church', 'Church', Icons.church),
  worship('worship', 'Worship', Icons.music_note),
  jobs('jobs', 'Jobs', Icons.work),
  social('social', 'Church Social', Icons.people_alt),
  groups('groups', 'Groups', Icons.groups),
  notify('notify', 'Notifications', Icons.notifications);

  const SearchScope(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

/// Why a suggestion is being offered. Drives the row's icon and grouping.
enum SearchSuggestionKind {
  /// Previously run by this user, on this surface.
  history,

  /// Previously run by this user, but on a different surface.
  crossHistory,

  /// A curated term for this surface.
  popular,

  /// A live record matched from the surface's own dataset, e.g. a member or
  /// product name.
  entity,

  /// A navigation shortcut rather than text to search for.
  action,
}

@immutable
class SearchSuggestion {
  final String text;

  /// Sub-label such as "Members", shown for cross-surface history.
  final String? contextLabel;
  final SearchSuggestionKind kind;
  final int score;

  const SearchSuggestion({
    required this.text,
    required this.kind,
    this.contextLabel,
    this.score = 0,
  });

  IconData get icon => switch (kind) {
        SearchSuggestionKind.history => Icons.history,
        SearchSuggestionKind.crossHistory => Icons.north_east,
        SearchSuggestionKind.popular => Icons.trending_up,
        SearchSuggestionKind.entity => Icons.person_search,
        SearchSuggestionKind.action => Icons.arrow_forward,
      };
}

/// Builds the suggestion list for a search surface.
///
/// Pure and synchronous: the caller supplies live candidates (member names,
/// product titles, saved places) so this stays unit testable and never has to
/// know about Supabase.
class SearchSuggestionService {
  final SearchHistoryService history;

  const SearchSuggestionService(this.history);

  /// Curated starting points per surface, used when the user has not typed
  /// anything yet. These are the equivalent of Instagram's suggested
  /// accounts: a cold list that teaches the surface what can be searched.
  static const Map<SearchScope, List<String>> popularByScope = {
    /// The universal screen searches the whole app, so its curated list spans
    /// every major domain. It previously had none, which left the app's main
    /// search screen with an empty cold state.
    SearchScope.universal: [
      'Sunday Service',
      'Prayer Request',
      'Bible Study',
      'Klips',
      'Giving',
      'Events',
      'Bible Quiz',
      'Marketplace',
      'Jobs',
      'Testimonies',
      'Live Stream',
      'Church Social',
    ],
    SearchScope.bible: [
      'Faith',
      'Grace',
      'Love',
      'Prayer',
      'Salvation',
      'Jeremiah 29:11',
      'Psalm 23',
      'John 3:16',
      'Romans 8:28',
      'Proverbs 3:5',
    ],
    SearchScope.sermons: [
      'Sunday Service',
      'Midnight Cry',
      'Faith',
      'Testimony',
      'Worship',
      'Breaking Bread',
      'Prophecy',
      'Evangelism',
    ],
    SearchScope.members: [
      'Pastor',
      'Leadership',
      'Youth',
      'Women',
      'Men',
      'Choir',
      'Ushers',
      'Treasurer',
    ],
    SearchScope.marketplace: [
      'Bible',
      'Books',
      'Groceries',
      'Phone Accessories',
      'Church Merchandise',
      'Bibles and Study Guides',
    ],
    SearchScope.events: [
      'Sunday Service',
      'Bible Study',
      'Prayer Meeting',
      'Youth Service',
      'Revival Night',
      'Special Guest',
      'Communion',
    ],
    SearchScope.prayer: [
      'Healing',
      'Family',
      'Financial',
      'Deliverance',
      'Salvation',
      'Thanksgiving',
      'Travelling',
    ],
    SearchScope.testimonies: [
      'Healing',
      'Salvation',
      'Deliverance',
      'Family',
      'Business',
      'Thanksgiving',
    ],
    SearchScope.quiz: [
      'Genesis',
      'Psalms',
      'John',
      'Romans',
      'Revelation',
      'Tournaments',
      'Church Coins',
    ],
    SearchScope.giving: [
      'Tithe',
      'Offering',
      'Missions',
      'Building Fund',
      'Welfare',
      'First Fruits',
    ],
    SearchScope.rides: [
      'Lusaka',
      'Airport',
      'Kabwata',
      'Chilenje',
      'Downtown',
      'University',
    ],
    SearchScope.places: [
      'Lusaka',
      'Kitwe',
      'Ndola',
      'Harare',
      'Bulawayo',
      'Main Gate',
    ],
    SearchScope.church: [
      'Rock of Ages',
      'Verified',
      'Nearest',
      'Online',
    ],
    SearchScope.worship: [
      'Amazing Grace',
      'What a Friend We Have in Jesus',
      'Baba Yetu',
      'How Great Thou Art',
      'Raise Your Hands',
    ],
    SearchScope.jobs: [
      'Driver',
      'Teacher',
      'Nurse',
      'Cleaner',
      'Security',
      'Internship',
    ],
    SearchScope.social: ['Testimony', 'Prayer', 'Blessing', 'Announcement'],
    SearchScope.groups: ['Youth', 'Choir', 'Marriage', 'Men', 'Women'],
  };

  /// Suggestions for an empty query: this surface's history, then the
  /// user's most-used queries from elsewhere, then curated terms.
  List<SearchSuggestion> idleSuggestions(
    SearchScope scope, {
    List<String> entities = const [],
    int limit = 10,
  }) {
    final out = <SearchSuggestion>[];
    final seen = <String>{};

    void add(String text, SearchSuggestionKind kind, String? label, int score) {
      final key = SearchHistoryService.normalizeQuery(text).toLowerCase();
      if (key.isEmpty || !seen.add(key)) return;
      out.add(SearchSuggestion(
        text: SearchHistoryService.normalizeQuery(text),
        contextLabel: label,
        kind: kind,
        score: score,
      ));
    }

    for (final e in history.entriesFor(scope.id)) {
      add(e.query, SearchSuggestionKind.history, null, 1000 - e.count);
    }
    for (final s in history.allScopedEntries()) {
      if (s.scope == scope.id) continue;
      add(s.entry.query, SearchSuggestionKind.crossHistory,
          labelForScope(s.scope), 400 - s.entry.count);
    }
    for (final term in popularByScope[scope] ?? const <String>[]) {
      add(term, SearchSuggestionKind.popular, null, 100);
    }
    for (final name in entities) {
      add(name, SearchSuggestionKind.entity, null, 50);
    }

    out.sort((a, b) => b.score.compareTo(a.score));
    return out.take(limit).toList();
  }

  /// Suggestions once the user has typed: prefix matches first, then
  /// mid-word matches, then curated terms and live entities.
  List<SearchSuggestion> querySuggestions(
    SearchScope scope,
    String query, {
    List<String> entities = const [],
    int limit = 8,
  }) {
    final needle = SearchHistoryService.normalizeQuery(query).toLowerCase();
    if (needle.isEmpty) return idleSuggestions(scope, entities: entities, limit: limit);

    final out = <SearchSuggestion>[];
    final seen = <String>{};

    void add(String text, SearchSuggestionKind kind, String? label, int score) {
      final norm = SearchHistoryService.normalizeQuery(text);
      if (norm.isEmpty) return;
      if (!norm.toLowerCase().contains(needle)) return;
      if (!seen.add(norm.toLowerCase())) return;
      out.add(SearchSuggestion(
        text: norm,
        contextLabel: label,
        kind: kind,
        score: score,
      ));
    }

    // This surface's own history is the strongest signal.
    for (final e in history.matches(query, scope: scope.id, limit: 6)) {
      add(e.query, SearchSuggestionKind.history, null,
          SearchHistoryService.score(e, needle));
    }
    for (final s in history.matchesScoped(query, limit: 4)) {
      if (s.scope == scope.id) continue;
      add(s.entry.query, SearchSuggestionKind.crossHistory, labelForScope(s.scope),
          SearchHistoryService.score(s.entry, needle) - 50);
    }
    for (final term in popularByScope[scope] ?? const <String>[]) {
      add(term, SearchSuggestionKind.popular, null,
          term.toLowerCase().startsWith(needle) ? 200 : 50);
    }
    for (final name in entities) {
      add(name, SearchSuggestionKind.entity, null,
          name.toLowerCase().startsWith(needle) ? 180 : 40);
    }

    out.sort((a, b) => b.score.compareTo(a.score));
    return out.take(limit).toList();
  }

  /// Human label for a stored scope id.
  ///
  /// Resolves the known [SearchScope] ids and degrades gracefully for scopes
  /// written by an older build that no longer has an enum entry, so a stale
  /// stored scope degrades to a neutral chip instead of crashing.
  static String labelForScope(String scopeId) {
    for (final scope in SearchScope.values) {
      if (scope.id == scopeId) return scope.label;
    }
    return 'Recent';
  }
}