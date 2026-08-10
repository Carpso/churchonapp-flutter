import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/lyric_service.dart';

class SongLyricsScreen extends ConsumerWidget {
  const SongLyricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricAsync = ref.watch(currentLyricProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text("Praise & Worship", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: lyricAsync.when(
        data: (lyric) => SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              const Text("CURRENT SONG", style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
              Text(lyric.title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              Text(lyric.artist, style: const TextStyle(color: Colors.white54, fontSize: 14)),
              const SizedBox(height: 50),
              ...lyric.sections.entries.map((entry) => _buildLyricSection(entry.key, entry.value)),
              const SizedBox(height: 50),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
                child: const Row(
                  children: [
                    Icon(LucideIcons.music, color: Colors.orange),
                    SizedBox(width: 15),
                    Text("Worship along with the COA family!", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.orange)),
        error: (e, s) => Center(child: Text("Offline: Load cached lyrics?", style: TextStyle(color: Colors.white))),
      ),
    );
  }

  Widget _buildLyricSection(String title, String lyrics) {
    return Column(
      children: [
        const SizedBox(height: 30),
        Text(title, style: const TextStyle(color: Colors.white24, fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 15),
        Text(
          lyrics,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.8),
        ),
      ],
    );
  }
}

