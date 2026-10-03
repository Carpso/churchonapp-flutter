import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:church_on_app/core/services/search_history_service.dart';
import 'package:church_on_app/core/services/search_suggestion_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/media/data/transcript_service.dart';
import '../data/sermon_service.dart';
import 'sermon_player_screen.dart';
import 'live_stream_screen.dart';

class UniversalSearchScreen extends ConsumerStatefulWidget {
  const UniversalSearchScreen({super.key});

  @override
  ConsumerState<UniversalSearchScreen> createState() => _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends ConsumerState<UniversalSearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<Map<String, dynamic>> _results = [];

  /// Shared search history, keyed by scope.
  ///
  /// Replaces the screen's own `universal_search_recent_v1` string list. That
  /// could not rank, had no per-query frequency, capped at 6, and was invisible
  /// to every other search surface in the app.
  SearchHistoryService? _history;
  SearchSuggestionService? _suggestions;
  List<SearchSuggestion> _suggestions_ = const [];

  @override
  void initState() {
    super.initState();
    _bootstrapSearch();
  }

  Future<void> _bootstrapSearch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _history = SearchHistoryService(prefs);
      _suggestions = SearchSuggestionService(_history!);
      _recomputeSuggestions();
    } catch (e) {
      debugPrint('[UniversalSearch] history unavailable: $e');
    }
  }

  /// Suggestions for the universal scope, which additionally borrows every
  /// other surface's history - this screen searches across the whole app, so
  /// what the user searched on the Bible or Members screens is exactly what
  /// should be offered here.
  List<SearchSuggestion> _universalSuggestions(String query) {
    final service = _suggestions;
    if (service == null) return const [];
    if (query.trim().isEmpty) {
      return service.idleSuggestions(
        SearchScope.universal,
        limit: 12,
      );
    }
    return service.querySuggestions(
      SearchScope.universal,
      query,
      limit: 8,
    );
  }

  void _recomputeSuggestions() {
    if (!mounted) return;
    setState(() {
      _suggestions_ = _universalSuggestions(_searchController.text);
    });
  }

  Future<void> _rememberQuery(String query) async {
    final service = _history;
    if (service == null) return;
    await service.record(SearchScope.universal.id, query);
    if (mounted) _recomputeSuggestions();
  }

  Future<void> _clearRecent() async {
    await _history?.clear();
    if (mounted) _recomputeSuggestions();
  }

  Future<void> _removeRecent(String query) async {
    await _history?.remove(SearchScope.universal.id, query);
    if (mounted) _recomputeSuggestions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    // Suggestions re-rank immediately on every keystroke; the remote search
    // stays debounced because it is the expensive half.
    _recomputeSuggestions();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _loading = false;
        _results = [];
      });
      return;
    }
    setState(() => _loading = true);
    _rememberQuery(q);
    try {
      // Client access inside try: an uninitialized backend must fall into
      // the catch â†’ empty state, never leave the spinner hanging.
      final client = Supabase.instance.client;
      final tenant = ref.read(currentTenantProvider);
      final tenantId = tenant?.id;
      final results = <Map<String, dynamic>>[];
      final like = '%$q%';

      // Transcript matches first â€” these can jump straight to the moment the
      // words were spoken.
      try {
        final hits = await ref.read(transcriptServiceProvider).searchTranscripts(q);
        for (final h in hits) {
          results.add({
            'type': 'Transcript',
            'title': h.title,
            'subtitle': h.snippet.replaceAll('<<', '').replaceAll('>>', ''),
            'icon': LucideIcons.subtitles,
            'route': '/sermons',
            'hit': h,
          });
        }
      } catch (e) {
        debugPrint('Transcript search skipped: $e');
      }

      final sermons = await client
          .from('sermons')
          .select('id,title,speaker,thumbnail_url')
          .ilike('title', like)
          .order('created_at', ascending: false)
          .limit(8);
      for (final s in sermons) {
        results.add({
          'type': 'Sermon',
          'title': s['title'] ?? '',
          'subtitle': s['speaker'] ?? '',
          'icon': LucideIcons.mic,
          'route': '/sermons',
          'extra': s,
        });
      }

      final events = await client
          .from('events')
          .select('id,title,location,date,church_id')
          .ilike('title', like)
          .order('date', ascending: true)
          .limit(8);
      for (final e in events) {
        results.add({
          'type': 'Event',
          'title': e['title'] ?? '',
          'subtitle': '${e['location'] ?? ''} â€¢ ${e['date'] ?? ''}',
          'icon': LucideIcons.calendar,
          'route': '/event/${e['id']}',
        });
      }

      final members = await client
          .from('profiles')
          .select('id,full_name,role,tenant_id')
          .ilike('full_name', like)
          .limit(8);
      for (final m in members) {
        if (tenantId != null && m['tenant_id'] != null && m['tenant_id'] != tenantId) continue;
        results.add({
          'type': 'Member',
          'title': m['full_name'] ?? '',
          'subtitle': m['role'] ?? '',
          'icon': LucideIcons.user,
          'route': '/profile-by-id/${m['id']}',
        });
      }

      final communities = await client
          .from('community_communities')
          .select('id,name,description')
          .ilike('name', like)
          .limit(8);
      for (final c in communities) {
        results.add({
          'type': 'Community',
          'title': c['name'] ?? '',
          'subtitle': c['description'] ?? '',
          'icon': LucideIcons.users,
          'route': '/communities',
        });
      }

      final items = await client
          .from('marketplace_items')
          .select('id,title,price_kwacha,seller_church_id')
          .ilike('title', like)
          .limit(8);
      for (final it in items) {
        results.add({
          'type': 'Market',
          'title': it['title'] ?? '',
          'subtitle': 'K${it['price_kwacha'] ?? 0}',
          'icon': LucideIcons.shoppingBag,
          'route': '/marketplace',
        });
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _results = results;
      });
    } catch (e) {
      debugPrint('UniversalSearch error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _results = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: _onSearch,
          decoration: const InputDecoration(
            hintText: "Search Sermons, Events, People...",
            border: InputBorder.none,
            hintStyle: TextStyle(fontSize: 16),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.x),
            onPressed: () {
              _searchController.clear();
              _onSearch("");
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty && _searchController.text.isNotEmpty
              ? _buildNoResults()
              : _results.isEmpty
                  ? _buildQuickSuggestions()
                  : _buildResultsList(),
    );
  }

  Widget _buildQuickSuggestions() {
    final theme = Theme.of(context);
    final history = _suggestions_
        .where((s) =>
            s.kind == SearchSuggestionKind.history ||
            s.kind == SearchSuggestionKind.crossHistory)
        .toList();
    final discover = _suggestions_
        .where((s) =>
            s.kind == SearchSuggestionKind.popular ||
            s.kind == SearchSuggestionKind.entity)
        .toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: ListView(
        children: [
          if (history.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    "RECENT SEARCHES",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: Colors.grey),
                  ),
                ),
                GestureDetector(
                  onTap: _clearRecent,
                  child: const Text('CLEAR',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...history.map((s) => _buildSuggestionRow(s, theme)),
            const SizedBox(height: 20),
          ],
          if (discover.isNotEmpty) ...[
            Text(
              _searchController.text.trim().isEmpty
                  ? "DISCOVER"
                  : "SUGGESTIONS",
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: Colors.grey),
            ),
            const SizedBox(height: 4),
            ...discover.map((s) => _buildSuggestionRow(s, theme)),
          ],
          if (history.isEmpty && discover.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'Type to search sermons, people, events and more',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One suggestion row. History rows can be dismissed individually;
  /// curated and entity rows cannot, because they were not the user's own.
  Widget _buildSuggestionRow(SearchSuggestion s, ThemeData theme) {
    final removable = s.kind == SearchSuggestionKind.history ||
        s.kind == SearchSuggestionKind.crossHistory;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(s.icon, size: 18, color: theme.primaryColor),
      title: Text(s.text,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: s.contextLabel == null
          ? null
          : Text(s.contextLabel!,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      trailing: removable
          ? IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Remove',
              onPressed: () => _removeRecent(s.text),
            )
          : const Icon(Icons.north_west, size: 14),
      onTap: () {
        _searchController.text = s.text;
        _searchController.selection =
            TextSelection.collapsed(offset: s.text.length);
        _search(s.text);
      },
    );
  }

  Widget _buildResultsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return InkWell(
          onTap: () => _openResult(item),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(item['icon'], color: Theme.of(context).primaryColor, size: 20),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(item['subtitle'], style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(5)),
                  child: Text(item['type'].toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Transcript hits jump to the timestamp; everything else uses its route.
  Future<void> _openResult(Map<String, dynamic> item) async {
    final hit = item['hit'];
    if (item['type'] == 'Transcript' && hit is MediaTranscriptSearchHit) {
      if (hit.sermonId != null) {
        final sermon =
            await ref.read(sermonServiceProvider).fetchSermonById(hit.sermonId!);
        if (sermon != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  SermonPlayerScreen(sermon: sermon, initialPosition: hit.start),
            ),
          );
        }
        return;
      }
      if (hit.liveStreamId != null && hit.streamUrl.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LiveStreamScreen(
              streamUrl: hit.streamUrl,
              title: hit.title,
              streamId: hit.liveStreamId,
            ),
          ),
        );
        return;
      }
    }
    final route = item['route'] as String?;
    if (route != null) context.push(route, extra: item['extra']);
  }

  Widget _buildNoResults() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.searchX, size: 60, color: Colors.grey),
          SizedBox(height: 20),
          Text("No matches found", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ],
      ),
    );
  }
}
