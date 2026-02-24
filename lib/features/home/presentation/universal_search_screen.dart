import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class UniversalSearchScreen extends StatefulWidget {
  const UniversalSearchScreen({super.key});

  @override
  State<UniversalSearchScreen> createState() => _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends State<UniversalSearchScreen> {
  final _searchController = TextEditingController();
  final List<Map<String, dynamic>> _allData = [
    {"type": "Sermon", "title": "Walking in the Spirit", "subtitle": "Bishop John Mwansa", "icon": LucideIcons.mic},
    {"type": "Event", "title": "Youth Explosion 2026", "subtitle": "Main Sanctuary • Mar 12", "icon": LucideIcons.calendar},
    {"type": "Member", "title": "John Doe", "subtitle": "Deacon • Calvary Branch", "icon": LucideIcons.user},
    {"type": "Community", "title": "Bible Study Group", "subtitle": "45 Members • Thursday 6PM", "icon": LucideIcons.users},
    {"type": "Market", "title": "King James Bible", "subtitle": "₵ 120.00 • In Stock", "icon": LucideIcons.shoppingBag},
  ];

  List<Map<String, dynamic>> _results = [];

  void _onSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _results = [];
      } else {
        _results = _allData.where((item) {
          return item['title'].toLowerCase().contains(query.toLowerCase()) ||
                 item['type'].toLowerCase().contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
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
      body: _results.isEmpty && _searchController.text.isNotEmpty
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
          const Text("QUICK SUGGESTIONS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2, color: Colors.grey)),
          const SizedBox(height: 15),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildSuggestionChip("Sunday Service", LucideIcons.video),
              _buildSuggestionChip("Giving", LucideIcons.heart),
              _buildSuggestionChip("Prayer Request", LucideIcons.flame),
              _buildSuggestionChip("Kingdom Klips", LucideIcons.play),
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
        return Container(
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
                child: Text(item['type'].toUpperCase(), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
            ],
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
          Text("No matches found in the Kingdom", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ],
      ),
    );
  }
}
