import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/widgets/branded_stream_poster.dart';
import '../../../core/widgets/shimmer_loader.dart';
import 'package:church_on_app/features/media/data/transcript_service.dart';
import '../data/sermon_service.dart';
import 'sermon_player_screen.dart';
import 'live_stream_screen.dart';

class SermonSearchScreen extends ConsumerStatefulWidget {
  const SermonSearchScreen({super.key});

  @override
  ConsumerState<SermonSearchScreen> createState() => _SermonSearchScreenState();
}

class _SermonSearchScreenState extends ConsumerState<SermonSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Sermon> _searchResults = [];
  List<MediaTranscriptSearchHit> _transcriptHits = [];
  bool _isLoading = false;

  void _performSearch(String query) async {
    if (query.isEmpty) return;
    setState(() => _isLoading = true);

    final service = ref.read(sermonServiceProvider);
    final results = await service.searchSermons(query);
    final hits = await ref.read(transcriptServiceProvider).searchTranscripts(query);

    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _transcriptHits = hits;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _searchResults.isNotEmpty || _transcriptHits.isNotEmpty;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
        ? const ListSkeleton(count: 5)
        : !hasResults
          ? _buildInitialState()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_transcriptHits.isNotEmpty) ...[
                  const Text(
                    'IN TRANSCRIPTS',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  ..._transcriptHits.map(_buildTranscriptTile),
                  const SizedBox(height: 20),
                ],
                if (_searchResults.isNotEmpty) ...[
                  const Text(
                    'SERMONS',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  ..._searchResults.map(_buildResultTile),
                ],
              ],
            ),
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.search, size: 80, color: Colors.grey.withValues(alpha: 0.2)),
          const SizedBox(height: 20),
          const Text("Enter a word, preacher, or topic", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          const Text("to retrieve apostolic insights.", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  /// Transcript hit — tap to open the sermon at the spoken timestamp.
  Widget _buildTranscriptTile(MediaTranscriptSearchHit hit) {
    return GestureDetector(
      onTap: () => _openTranscriptHit(hit),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(LucideIcons.subtitles, size: 18, color: Theme.of(context).primaryColor),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hit.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    hit.snippet.replaceAll('<<', '').replaceAll('>>', ''),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _mmss(hit.start),
                    style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTranscriptHit(MediaTranscriptSearchHit hit) async {
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
    if (hit.liveStreamId != null && hit.streamUrl.isNotEmpty && mounted) {
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
    }
  }

  static String _mmss(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _buildResultTile(Sermon sermon) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SermonPlayerScreen(sermon: sermon))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SmartStreamPoster(url: sermon.thumbnailUrl, seed: sermon.id, width: 80, height: 60, fit: BoxFit.cover),
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
