import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/bible_service.dart';
// Theme imported via context

class BibleScreen extends ConsumerStatefulWidget {
  const BibleScreen({super.key});

  @override
  ConsumerState<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends ConsumerState<BibleScreen> {
  String selectedBook = "John";
  int selectedChapter = 1;
  String selectedTranslation = "web";

  final List<String> translations = ["web", "kjv", "bbe"];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("$selectedBook $selectedChapter", style: const TextStyle(fontWeight: FontWeight.bold)),
            const Icon(LucideIcons.chevronDown, size: 16),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(LucideIcons.search), onPressed: () {}),
          IconButton(icon: const Icon(LucideIcons.settings), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          _buildTranslationSelector(),
          Expanded(
            child: ref.watch(bibleChapterProvider({
              'translation': selectedTranslation,
              'book': selectedBook,
              'chapter': selectedChapter,
            })).when(
              data: (verses) => ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: verses.length,
                itemBuilder: (context, index) {
                  final verse = verses[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 15.0),
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: "${verse.verse} ",
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          TextSpan(
                            text: verse.text,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.secondary,
                              fontSize: 18,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text("Error: $err")),
            ),
          ),
          _buildLowerControls(),
        ],
      ),
    );
  }

  Widget _buildTranslationSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      height: 50,
      color: Theme.of(context).primaryColor.withOpacity(0.05),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: translations.map((t) => GestureDetector(
          onTap: () => setState(() => selectedTranslation = t),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              t.toUpperCase(),
              style: TextStyle(
                fontWeight: selectedTranslation == t ? FontWeight.bold : FontWeight.normal,
                color: selectedTranslation == t ? Theme.of(context).primaryColor : Colors.grey.shade400,
              ),
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildLowerControls() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildMiniAction(LucideIcons.highlighter, "Highlight"),
          _buildMiniAction(LucideIcons.pencil, "Notes"),
          _buildMiniAction(LucideIcons.share, "Share"),
          _buildMiniAction(LucideIcons.volume2, "Listen"),
        ],
      ),
    );
  }

  Widget _buildMiniAction(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.secondary.withOpacity(0.6)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
