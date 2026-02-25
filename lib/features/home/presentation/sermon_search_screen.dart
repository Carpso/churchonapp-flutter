import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/sermon_service.dart';
import 'sermon_player_screen.dart';

class SermonSearchScreen extends ConsumerStatefulWidget {
  const SermonSearchScreen({super.key});

  @override
  ConsumerState<SermonSearchScreen> createState() => _SermonSearchScreenState();
}

class _SermonSearchScreenState extends ConsumerState<SermonSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Sermon> _searchResults = [];
  bool _isLoading = false;

  void _performSearch(String query) async {
    if (query.isEmpty) return;
    setState(() => _isLoading = true);
    
    final results = await ref.read(sermonServiceProvider).searchSermons(query);
    
    setState(() {
      _searchResults = results;
      _isLoading = false;
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
          onSubmitted: _performSearch,
          decoration: const InputDecoration(
            hintText: "Search Prophetic Archive...",
            border: InputBorder.none,
          ),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.x),
            onPressed: () => _searchController.clear(),
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.amber))
        : _searchResults.isEmpty 
          ? _buildInitialState()
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _searchResults.length,
              itemBuilder: (context, index) => _buildResultTile(_searchResults[index]),
            ),
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.search, size: 80, color: Colors.grey.withOpacity(0.2)),
          const SizedBox(height: 20),
          const Text("Enter a word, preacher, or topic", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          const Text("to retrieve apostolic insights.", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildResultTile(Sermon sermon) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SermonPlayerScreen(sermon: sermon))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(sermon.thumbnailUrl, width: 80, height: 60, fit: BoxFit.cover),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sermon.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(sermon.preacher, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}

