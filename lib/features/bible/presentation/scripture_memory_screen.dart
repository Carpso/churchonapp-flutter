import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/bible/data/bible_service.dart';
import 'package:church_on_app/features/bible/data/bible_translations.dart';
import 'package:church_on_app/features/bible/data/study_settings_provider.dart';
import '../data/memory_verses_data.dart' as memory_data;

class ScriptureMemoryScreen extends ConsumerStatefulWidget {
  const ScriptureMemoryScreen({super.key});

  @override
  ConsumerState<ScriptureMemoryScreen> createState() => _ScriptureMemoryScreenState();
}

class _ScriptureMemoryScreenState extends ConsumerState<ScriptureMemoryScreen> {
  final List<memory_data.MemoryVerse> _verses = List.from(memory_data.memoryVerses);

  double _hideLevel = 0.0; // 0.0 to 1.0

  String _applyMask(String original, double level) {
    if (level == 0.0) return original;
    final words = original.split(' ');
    final toHideCount = (words.length * level).toInt();

    // Deterministic random generator based on level to mask words
    for (int i = 0; i < toHideCount; i++) {
      int index = (i * 7) % words.length;
      words[index] = "____";
    }
    return words.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Scripture Memory", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 30),
        child: PageView.builder(
          itemCount: _verses.length,
          itemBuilder: (context, index) => _buildVerseCard(_verses[index]),
        ),
      ),
    );
  }

  Widget _buildVerseCard(memory_data.MemoryVerse verse) {
    final liveText = ref
        .watch(bibleReferenceTextProvider(verse.reference))
        .value;
    final displayText =
        (liveText != null && liveText.isNotEmpty) ? liveText : verse.text;
    final translation = ref.watch(studySettingsProvider).preferredTranslation;
    final maskedText = _applyMask(displayText, _hideLevel);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.indigo.withValues(alpha: 0.04), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.brain, color: Colors.indigo, size: 50),
          const SizedBox(height: 25),
          Text(verse.reference, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.indigo)),
          const SizedBox(height: 4),
          Text(
            getTranslationShortName(translation),
            style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          const SizedBox(height: 25),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                maskedText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, height: 1.8, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic),
              ),
            ),
          ),
          const SizedBox(height: 30),
          const Text("Hide Words to Practice Recital", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Slider(
            value: _hideLevel,
            onChanged: (val) => setState(() => _hideLevel = val),
            activeColor: Colors.indigo,
            inactiveColor: const Color(0xFFF1F5F9),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text("Easy", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
              Text("By Heart", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
