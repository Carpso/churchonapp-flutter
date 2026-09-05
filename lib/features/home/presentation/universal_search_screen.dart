import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

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

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
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
    try {
      // Client access inside try: an uninitialized backend must fall into
      // the catch → empty state, never leave the spinner hanging.
      final client = Supabase.instance.client;
      final tenant = ref.read(currentTenantProvider);
      final tenantId = tenant?.id;
      final results = <Map<String, dynamic>>[];
      final like = '%$q%';

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
          'subtitle': '${e['location'] ?? ''} • ${e['date'] ?? ''}',
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
    return Padding(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("QUICK SUGGESTIONS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2, color: Colors.grey)),
          const SizedBox(height: 15),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildSuggestionChip("Sunday Service", LucideIcons.video),
              _buildSuggestionChip("Giving", LucideIcons.heart),
              _buildSuggestionChip("Prayer Request", LucideIcons.flame),
              _buildSuggestionChip("Klips", LucideIcons.play),
              _buildSuggestionChip("My Schedule", LucideIcons.calendar),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String label, IconData icon) {
    return ActionChip(
      avatar: Icon(icon, size: 14, color: Theme.of(context).primaryColor),
      label: Text(label),
      onPressed: () {
        _searchController.text = label;
        _onSearch(label);
      },
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildResultsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return InkWell(
          onTap: () {
            final route = item['route'] as String;
            context.push(route, extra: item['extra']);
          },
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