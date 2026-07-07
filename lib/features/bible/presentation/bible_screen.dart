import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/bible_service.dart';
import '../data/bible_books.dart';
import '../../notebook/presentation/notebook_screen.dart';
import 'bible_podcast_screen.dart';
import 'study_plans_screen.dart';
import 'scripture_memory_screen.dart';

class BibleScreen extends ConsumerStatefulWidget {
  const BibleScreen({super.key});

  @override
  ConsumerState<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends ConsumerState<BibleScreen> {
  String selectedBook = "John";
  int selectedChapter = 1;
  String selectedTranslation = "web";
  bool isStudyPaneOpen = false;
  double fontSize = 18.0;
  bool isDarkTheme = false;
  int _activeBottomTab = 0; // 0=Highlight, 1=Notes, 2=Share, 3=Audio, 4=Study
  int _bookSelectorTab = 0; // 0=OT, 1=NT
  final Set<String> _highlightedVerses = {};

  /// Number of chapters per book (all 66 books)
  static const Map<String, int> _chapterCounts = {
    'Genesis': 50, 'Exodus': 40, 'Leviticus': 27, 'Numbers': 36, 'Deuteronomy': 34,
    'Joshua': 24, 'Judges': 21, 'Ruth': 4, '1 Samuel': 31, '2 Samuel': 24,
    '1 Kings': 22, '2 Kings': 25, '1 Chronicles': 29, '2 Chronicles': 36,
    'Ezra': 10, 'Nehemiah': 13, 'Esther': 10, 'Job': 42, 'Psalms': 150,
    'Proverbs': 31, 'Ecclesiastes': 12, 'Song of Solomon': 8, 'Isaiah': 66,
    'Jeremiah': 52, 'Lamentations': 5, 'Ezekiel': 48, 'Daniel': 12,
    'Hosea': 14, 'Joel': 3, 'Amos': 9, 'Obadiah': 1, 'Jonah': 4,
    'Micah': 7, 'Nahum': 3, 'Habakkuk': 3, 'Zephaniah': 3, 'Haggai': 2,
    'Zechariah': 14, 'Malachi': 4, 'Matthew': 28, 'Mark': 16, 'Luke': 24,
    'John': 21, 'Acts': 28, 'Romans': 16, '1 Corinthians': 16, '2 Corinthians': 13,
    'Galatians': 6, 'Ephesians': 6, 'Philippians': 4, 'Colossians': 4,
    '1 Thessalonians': 5, '2 Thessalonians': 3, '1 Timothy': 6, '2 Timothy': 4,
    'Titus': 3, 'Philemon': 1, 'Hebrews': 13, 'James': 5, '1 Peter': 5,
    '2 Peter': 3, '1 John': 5, '2 John': 1, '3 John': 1, 'Jude': 1,
    'Revelation': 22,
  };

  int get _maxChapter => _chapterCounts[selectedBook] ?? 150;

  final List<Map<String, String>> translations = [
    {"id": "web", "name": "World English Bible (WEB)"},
    {"id": "kjv", "name": "King James Version (KJV)"},
    {"id": "bbe", "name": "Bible in Basic English (BBE)"},
    {"id": "oeb-cw", "name": "Open English Bible (OEB)"},
    {"id": "almeida", "name": "João Ferreira de Almeida (Portuguese)"},
    {"id": "rvr1960", "name": "Reina-Valera 1960 (Spanish)"},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkTheme ? const Color(0xFF121212) : const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showBookSelector,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("$selectedBook $selectedChapter", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 5),
              const Icon(LucideIcons.chevronDown, size: 16),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.listTodo),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StudyPlansScreen())),
            tooltip: "Study Plans",
          ),
          IconButton(
            icon: const Icon(LucideIcons.brain),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScriptureMemoryScreen())),
            tooltip: "Scripture Memory",
          ),
          IconButton(icon: const Icon(LucideIcons.type), onPressed: _showAppearanceSettings),
          IconButton(icon: const Icon(LucideIcons.search), onPressed: _showSearchDialog),
        ],
      ),
      body: Row(
        children: [
          Expanded(child: _buildBibleContent()),
          if (isStudyPaneOpen) _buildStudyPane(),
        ],
      ),
      bottomNavigationBar: _buildBottomToolbar(),
    );
  }

  Widget _buildBibleContent() {
    return ref.watch(bibleChapterProvider({
      'translation': selectedTranslation,
      'book': selectedBook,
      'chapter': selectedChapter,
    })).when(
      data: (verses) {
        if (verses.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.bookOpen, size: 50, color: Colors.grey[300]),
                const SizedBox(height: 15),
                const Text("No content found", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text("$selectedBook $selectedChapter", style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 15),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                  child: const Text("RETRY", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
        return Column(
          children: [
            // Chapter navigator
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.chevronLeft, size: 20),
                    onPressed: selectedChapter > 1 ? () => setState(() => selectedChapter--) : null,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
                    child: Text("Chapter $selectedChapter", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.chevronRight, size: 20),
                    onPressed: selectedChapter < _maxChapter ? () => setState(() => selectedChapter++) : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                itemCount: verses.length,
                itemBuilder: (context, index) {
                  final v = verses[index];
                  final isHighlighted = _highlightedVerses.contains("${v.chapter}:${v.verse}");
                  return GestureDetector(
                    onTap: () {
                      if (_activeBottomTab == 0) {
                        // Highlight mode
                        setState(() {
                          final key = "${v.chapter}:${v.verse}";
                          if (_highlightedVerses.contains(key)) {
                            _highlightedVerses.remove(key);
                          } else {
                            _highlightedVerses.add(key);
                          }
                        });
                      } else if (_activeBottomTab == 4) {
                        setState(() => isStudyPaneOpen = !isStudyPaneOpen);
                      }
                    },
                    onLongPress: () => _showVerseActions(v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: isHighlighted ? BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ) : null,
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: "${v.verse} ",
                              style: TextStyle(color: Colors.amber.shade700, fontWeight: FontWeight.w900, fontSize: fontSize - 6),
                            ),
                            TextSpan(
                              text: v.text,
                              style: TextStyle(
                                color: isDarkTheme ? Colors.white : const Color(0xFF2D3436),
                                fontSize: fontSize,
                                height: 1.7,
                                fontFamily: 'Georgia',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
      error: (e, s) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.wifiOff, size: 40, color: Colors.grey),
            const SizedBox(height: 10),
            const Text("Failed to load chapter", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text("$e", style: const TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: () => ref.invalidate(bibleChapterProvider({'translation': selectedTranslation, 'book': selectedBook, 'chapter': selectedChapter})),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: const Text("RETRY", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showVerseActions(BibleVerse verse) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("$selectedBook ${verse.chapter}:${verse.verse}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 5),
            Text(verse.text, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _actionChip(LucideIcons.highlighter, "Highlight", Colors.amber),
                _actionChip(LucideIcons.copy, "Copy", Colors.blue),
                _actionChip(LucideIcons.share2, "Share", Colors.green),
                _actionChip(LucideIcons.bookmark, "Bookmark", Colors.purple),
                _actionChip(LucideIcons.pencil, "Note", Colors.orange),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, Color color) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$label applied!"), backgroundColor: color, duration: const Duration(seconds: 1)));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildStudyPane() {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
        border: const Border(left: BorderSide(color: Colors.black12)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("DEEP STUDY", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5)),
                IconButton(icon: const Icon(LucideIcons.x, size: 16), onPressed: () => setState(() => isStudyPaneOpen = false)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildStudySection("CROSS REFERENCES", ["Psalm 23:1", "Isaiah 40:11", "1 Peter 2:25"]),
                const SizedBox(height: 30),
                _buildStudySection("COMMENTARY", ["Matthew Henry: The Lord is my shepherd...", "Spurgeon: A song of holy confidence..."]),
                const SizedBox(height: 30),
                _buildStudySection("GREEK ANALYSIS", ["Strong's G4165 (Poimainō) - To act as a shepherd, to tend a flock."]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudySection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.amber)),
        const SizedBox(height: 10),
        ...items.map((i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(i, style: TextStyle(color: isDarkTheme ? Colors.white70 : Colors.black87, fontSize: 13, height: 1.4)),
        )),
      ],
    );
  }

  Widget _buildBottomToolbar() {
    final tabs = [
      {'icon': LucideIcons.highlighter, 'label': 'Highlight'},
      {'icon': LucideIcons.pencil, 'label': 'Notes'},
      {'icon': LucideIcons.share2, 'label': 'Share'},
      {'icon': LucideIcons.headphones, 'label': 'Audio'},
      {'icon': LucideIcons.bookOpen, 'label': 'Study'},
    ];

    return Container(
      padding: const EdgeInsets.only(bottom: 35, top: 12, left: 10, right: 10),
      decoration: BoxDecoration(
        color: isDarkTheme ? const Color(0xFF1A1A1A) : Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(tabs.length, (i) {
          final isActive = _activeBottomTab == i;
          return GestureDetector(
            onTap: () {
              setState(() => _activeBottomTab = i);
              switch (i) {
                case 1: // Notes
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const NotebookScreen()));
                case 2: // Share
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Share $selectedBook $selectedChapter"), backgroundColor: Colors.green, duration: const Duration(seconds: 1)),
                  );
                case 3: // Audio
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const BiblePodcastScreen()));
                case 4: // Study
                  setState(() => isStudyPaneOpen = !isStudyPaneOpen);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(horizontal: isActive ? 14 : 8, vertical: 6),
              decoration: isActive ? BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(15),
              ) : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tabs[i]['icon'] as IconData, color: isActive ? Colors.amber : (isDarkTheme ? Colors.white60 : Colors.grey), size: 20),
                  if (isActive) ...[
                    const SizedBox(width: 6),
                    Text(tabs[i]['label'] as String, style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  void _showBookSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.all(25),
          child: Column(
            children: [
              const Text("SELECT BOOK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 5),
              Text("${bibleBooks.length} books", style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const Divider(height: 20),
              // OT / NT tabs
              Row(
                children: [
                  Expanded(child: GestureDetector(
                    onTap: () => setModalState(() => _bookSelectorTab = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _bookSelectorTab == 0 ? Colors.amber.withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: _bookSelectorTab == 0 ? Border.all(color: Colors.amber, width: 1.5) : null,
                      ),
                      child: Center(child: Text("Old Testament", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _bookSelectorTab == 0 ? Colors.amber.shade800 : Colors.amber))),
                    ),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: GestureDetector(
                    onTap: () => setModalState(() => _bookSelectorTab = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _bookSelectorTab == 1 ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: _bookSelectorTab == 1 ? Border.all(color: Colors.blue, width: 1.5) : null,
                      ),
                      child: Center(child: Text("New Testament", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _bookSelectorTab == 1 ? Colors.blue : Colors.blue.withValues(alpha: 0.6)))),
                    ),
                  )),
                ],
              ),
              const SizedBox(height: 15),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 2.5),
                  itemCount: _bookSelectorTab == 0 ? 39 : 27,
                  itemBuilder: (context, index) {
                    final bookIndex = _bookSelectorTab == 0 ? index : index + 39;
                    final book = bibleBooks[bookIndex];
                    final isSelected = book == selectedBook;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedBook = book;
                          selectedChapter = 1;
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.amber : (isDarkTheme ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.08)),
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected ? Border.all(color: Colors.amber) : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          book,
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected
                              ? Colors.black
                              : (isDarkTheme ? Colors.white : const Color(0xFF1A1A2E)),
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAppearanceSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("READER SETTINGS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Translation"),
                DropdownButton<String>(
                  value: selectedTranslation,
                  items: translations.map((t) => DropdownMenuItem(value: t['id'], child: Text(t['name']!))).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => selectedTranslation = v);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(children: [
              const Text("Font Size"),
              Expanded(child: Slider(value: fontSize, min: 12, max: 32, activeColor: Colors.amber, onChanged: (v) => setState(() => fontSize = v))),
            ]),
            const SizedBox(height: 10),
            SwitchListTile(title: const Text("Dark Reader Mode"), value: isDarkTheme, activeThumbColor: Colors.amber, onChanged: (v) => setState(() => isDarkTheme = v)),
          ],
        ),
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (_) {
        final controller = TextEditingController();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: const Text("Search Scripture"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: "Enter a book name...", icon: Icon(LucideIcons.search)),
            onSubmitted: (value) {
              Navigator.pop(context);
              final match = bibleBooks.where((b) => b.toLowerCase().contains(value.toLowerCase())).firstOrNull;
              if (match != null) {
                setState(() { selectedBook = match; selectedChapter = 1; });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Book not found"), backgroundColor: Colors.red));
              }
            },
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL"))],
        );
      },
    );
  }

  void _showAudioPlaceholder(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Audio Bible playback coming soon"), backgroundColor: Colors.amber),
    );
  }

  // ignore: unused_element
  void _showAudioPlayer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 200,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            Row(children: [
              const Icon(LucideIcons.disc, color: Colors.white24, size: 50),
              const SizedBox(width: 20),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("AUDIO BIBLE: $selectedBook $selectedChapter", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const Text("Narration by Alexander Scourby", style: TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
              ),
            ]),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(LucideIcons.skipBack, color: Colors.white), onPressed: () => _showAudioPlaceholder(context)),
              const SizedBox(width: 20),
              CircleAvatar(radius: 30, backgroundColor: Colors.amber, child: IconButton(icon: const Icon(LucideIcons.play, color: Colors.black), onPressed: () => _showAudioPlaceholder(context))),
              const SizedBox(width: 20),
              IconButton(icon: const Icon(LucideIcons.skipForward, color: Colors.white), onPressed: () => _showAudioPlaceholder(context)),
            ]),
          ],
        ),
      ),
    );
  }
}

