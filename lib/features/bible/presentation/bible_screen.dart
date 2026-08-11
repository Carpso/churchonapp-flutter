import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/bible_service.dart';
import '../data/bible_books_service.dart';
import '../data/bible_book_model.dart';
import '../data/bible_translations.dart';
import '../data/biblical_atlas_data.dart';
import '../data/audio_bible_service.dart';
import '../data/bible_verse_service.dart';
import '../data/streak_service.dart';
import '../../notebook/presentation/notebook_screen.dart';
import 'bible_audio_player.dart';
import 'study_plans_screen.dart';
import '../../bible_study/presentation/bible_study_list_screen.dart';
import 'scripture_memory_screen.dart';

class BibleScreen extends ConsumerStatefulWidget {
  final String? initialBook;
  final int? initialChapter;
  final int? initialVerse;

  const BibleScreen({
    super.key,
    this.initialBook,
    this.initialChapter,
    this.initialVerse,
  });

  @override
  ConsumerState<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends ConsumerState<BibleScreen> {
  String selectedBook = "John";
  int selectedChapter = 1;
  int? selectedVerse;
  String selectedTranslation = "web";
  List<BibleBook> _allBooks = [];
  final ScrollController _verseScrollController = ScrollController();
  bool _hasScrolledToVerse = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(audioBibleServiceProvider).initialize();
      _loadBooks();
    });
  }

  @override
  void dispose() {
    _verseScrollController.dispose();
    super.dispose();
  }

  void _loadBooks() async {
    final books = await ref.read(bibleBooksProvider.future);
    if (mounted) {
      setState(() {
        _allBooks = books;
        if (widget.initialBook != null) {
          selectedBook = widget.initialBook!;
          selectedChapter = widget.initialChapter ?? 1;
          selectedVerse = widget.initialVerse;
        }
      });
    }
  }

  void _scrollToVerse(int verse) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_verseScrollController.hasClients) return;
      const double estimatedItemHeight = 60.0;
      final double offset = (verse - 1) * estimatedItemHeight;
      final double maxScroll = _verseScrollController.position.maxScrollExtent;
      _verseScrollController.animateTo(
        offset.clamp(0, maxScroll),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  bool isStudyPaneOpen = false;
  double fontSize = 18.0;
  bool isDarkTheme = false;
  int _activeBottomTab = 0;
  int _bookSelectorTab = 0;
  bool _showAudioPlayer = false;
  final Set<String> _highlightedVerses = {};

  int get _maxChapter {
    try {
      return _allBooks.firstWhere((b) => b.name == selectedBook).chapters;
    } catch (_) {
      return 150;
    }
  }

  final List<Map<String, String>> translations = kEnglishTranslations.map((t) => {
    "id": t.code,
    "name": t.name,
  }).toList();

  @override
  Widget build(BuildContext context) {
    // Wire audio bible + streak services into bible feature lifecycle
    ref.watch(audioBibleServiceProvider);
    ref.watch(streakServiceProvider);

    return Scaffold(
      backgroundColor: isDarkTheme ? const Color(0xFF121212) : Theme.of(context).scaffoldBackgroundColor,
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
            onPressed: _showStudyHub,
            tooltip: "Study Plans",
          ),
          IconButton(
            icon: const Icon(LucideIcons.brain),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScriptureMemoryScreen())),
            tooltip: "Scripture Memory",
          ),
          IconButton(icon: const Icon(LucideIcons.map), onPressed: _showBiblicalAtlas, tooltip: "Biblical Atlas"),
          IconButton(icon: const Icon(LucideIcons.type), onPressed: _showAppearanceSettings),
          IconButton(icon: const Icon(LucideIcons.search), onPressed: _showSearchDialog),
          IconButton(icon: const Icon(LucideIcons.mic, color: Colors.amber), onPressed: _voiceSearch, tooltip: 'Voice Search'),
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
                  onPressed: () => ref.invalidate(bibleChapterProvider({
                    'translation': selectedTranslation,
                    'book': selectedBook,
                    'chapter': selectedChapter,
                  })),
                  child: const Text("RETRY"),
                ),
              ],
            ),
          );
        }
        if (widget.initialVerse != null && !_hasScrolledToVerse) {
          _hasScrolledToVerse = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToVerse(widget.initialVerse!));
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
            // Audio player — toggled from Audio tab
            if (_showAudioPlayer)
              BibleAudioPlayer(
                bookName: selectedBook,
                bookAbbrev: kjvBookAbbrevs[selectedBook] ?? selectedBook.toLowerCase(),
                chapter: selectedChapter,
                totalChapters: _maxChapter,
                onChapterChange: (ch) => setState(() => selectedChapter = ch),
              ),
            Expanded(
              child: ListView.builder(
                controller: _verseScrollController,
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
    final reference = "$selectedBook ${verse.chapter}:${verse.verse}";
    final fullText = "${verse.text}\n— $reference";

    void saveNote(String label, {bool isBookmark = false, bool isFavorite = false, String? noteText}) async {
      final messenger = ScaffoldMessenger.of(context);
      final bookOrder = _bookOrderFor(selectedBook);
      if (bookOrder == null) {
        messenger.showSnackBar(SnackBar(content: Text("$label saved locally"), backgroundColor: Colors.orange, duration: const Duration(seconds: 1)));
        return;
      }
      final service = ref.read(bibleVerseServiceProvider);
      await service.addVerseNote(
        bookId: bookOrder,
        chapter: verse.chapter,
        verse: verse.verse,
        note: noteText ?? '',
        isBookmark: isBookmark,
        isFavorite: isFavorite,
      );
      messenger.showSnackBar(SnackBar(content: Text("$label saved"), backgroundColor: Colors.green, duration: const Duration(seconds: 1)));
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reference, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 5),
            Text(verse.text, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _actionChip(LucideIcons.highlighter, "Highlight", Colors.amber, onTap: () {
                  saveNote("Highlight", isBookmark: true);
                }),
                _actionChip(LucideIcons.copy, "Copy", Colors.blue, onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: fullText));
                  messenger.showSnackBar(const SnackBar(content: Text("Verse copied")));
                }),
                _actionChip(LucideIcons.share2, "Share", Colors.green, onTap: () {
                  SharePlus.instance.share(ShareParams(text: fullText));
                }),
                _actionChip(LucideIcons.bookmark, "Bookmark", Colors.purple, onTap: () {
                  saveNote("Bookmark", isBookmark: true);
                }),
                _actionChip(LucideIcons.pencil, "Note", Colors.orange, onTap: () {
                  _showNoteDialog(reference, verse.text, saveNote);
                }),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  int? _bookOrderFor(String bookName) {
    try {
      return _allBooks.firstWhere((b) => b.name == bookName).bookOrder;
    } catch (_) {
      return null;
    }
  }

  void _showNoteDialog(String reference, String verseText, void Function(String label, {bool isBookmark, bool isFavorite, String? noteText}) saveNote) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Add Note — $reference"),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: "Your note..."),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(context);
              Navigator.pop(context);
              saveNote("Note", noteText: text);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, Color color, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        Future.microtask(onTap);
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
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: 5,
              itemBuilder: (context, index) {
                switch (index) {
                  case 0: return _buildStudySection("READING", ["$selectedBook $selectedChapter", "Tap verses to highlight, long-press to copy, share or take notes."]);
                  case 1: return const SizedBox(height: 30);
                  case 2: return _buildStudySection("STUDY TOOLS", ["Deep Study Suite: word studies, atlas & verse memory", "Cross-references, chapter summaries & reading plans"]);
                  case 3: return const SizedBox(height: 30);
                  case 4: return _buildStudySection("OPEN DEEP STUDY", ["Open the Deep Study Suite for exegesis, atlas, memory verses and more."]);
                  default: return const SizedBox.shrink();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _shareCurrentChapter() {
    final state = ref.read(bibleChapterProvider({
      'translation': selectedTranslation,
      'book': selectedBook,
      'chapter': selectedChapter,
    }));
    final verses = state.value;
    if (verses == null) return;
    final text = verses.map((v) => "${v.verse} ${v.text}").join('\n');
    final reference = "$selectedBook $selectedChapter ($selectedTranslation)";
    SharePlus.instance.share(ShareParams(text: "$reference\n\n$text"));
  }

  Widget _buildStudySection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.amber)),
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
                  _shareCurrentChapter();
                case 3: // Audio — inline chapter player
                  setState(() => _showAudioPlayer = !_showAudioPlayer);
                  break;
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

  void _showBiblicalAtlas() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Biblical Atlas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(LucideIcons.x), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Explore biblical locations', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const Divider(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: biblicalLocations.length,
                itemBuilder: (_, i) {
                  final loc = biblicalLocations[i];
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.mapPin, color: Colors.amber, size: 18),
                    ),
                    title: Text(loc.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(loc.era, style: const TextStyle(fontSize: 12)),
                    trailing: Text('${loc.latitude.toStringAsFixed(2)}, ${loc.longitude.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  );
                },
              ),
            ),
          ],
        ),
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
              Text("${_allBooks.length} books", style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
                  itemCount: _bookSelectorTab == 0
                      ? _allBooks.where((b) => b.testament == Testament.old).length
                      : _allBooks.where((b) => b.testament == Testament.nt).length,
                  itemBuilder: (context, index) {
                    final booksInTestament = _bookSelectorTab == 0
                        ? _allBooks.where((b) => b.testament == Testament.old).toList()
                        : _allBooks.where((b) => b.testament == Testament.nt).toList();
                    final book = booksInTestament[index].name;
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
                            fontSize: 11,
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
    double localFontSize = fontSize;
    bool localDarkTheme = isDarkTheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            decoration: BoxDecoration(
              color: localDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
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
                      items: kEnglishTranslations.map((t) => DropdownMenuItem<String>(
                        value: t.code,
                        enabled: t.remoteSupported || t.code == 'nkjv' || t.code == 'nlt',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t.name),
                            if (!(t.remoteSupported || t.code == 'nkjv' || t.code == 'nlt'))
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Text('(soon)', style: TextStyle(color: Colors.grey, fontSize: 10)),
                              ),
                          ],
                        ),
                      )).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => selectedTranslation = v);
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(children: [
                  const Text("Font Size"),
                  Expanded(child: Slider(
                    value: localFontSize,
                    min: 12,
                    max: 32,
                    activeColor: Colors.amber,
                    onChanged: (v) => setModalState(() => localFontSize = v),
                    onChangeEnd: (v) => setState(() => fontSize = v),
                  )),
                ]),
                const SizedBox(height: 10),
                SwitchListTile(
                  title: const Text("Dark Reader Mode"),
                  value: localDarkTheme,
                  activeThumbColor: Colors.amber,
                  onChanged: (v) {
                    setModalState(() => localDarkTheme = v);
                    setState(() => isDarkTheme = v);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (_) => _ScriptureSearchDialog(
        onSubmitted: (value) {
          final match = _allBooks.where((b) => b.name.toLowerCase().contains(value.toLowerCase())).firstOrNull;
          if (match != null) {
            setState(() { selectedBook = match.name; selectedChapter = 1; });
          } else {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Book not found"), backgroundColor: Colors.red));
          }
        },
      ),
    );
  }

  void _showStudyHub() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: BoxDecoration(
          color: isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            const Text("BIBLE STUDY HUB", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)),
            const SizedBox(height: 5),
            const Text("Reading plans, church studies & memory tools", style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 25),
            _buildStudyHubTile(
              icon: LucideIcons.calendarCheck,
              title: "My Reading Plans",
              subtitle: "Daily scripture journeys with progress tracking",
              color: Colors.indigo,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const StudyPlansScreen()));
              },
            ),
            const SizedBox(height: 12),
            _buildStudyHubTile(
              icon: LucideIcons.users,
              title: "Church Bible Studies",
              subtitle: "Join group study sessions with your church",
              color: Colors.teal,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const BibleStudyListScreen()));
              },
            ),
            const SizedBox(height: 12),
            _buildStudyHubTile(
              icon: LucideIcons.brain,
              title: "Scripture Memory",
              subtitle: "Memorize verses with spaced repetition",
              color: Colors.amber,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ScriptureMemoryScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudyHubTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: color.withValues(alpha: 0.5), size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _voiceSearch() async {
    final query = await showDialog<String>(context: context, builder: (ctx) {
      final ctrl = TextEditingController();
      return AlertDialog(
        title: const Text('Bible Voice Search'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. play the story of Joseph, Genesis 1')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Search')),
        ],
      );
    });
    if (query == null || query.isEmpty) return;
    try {
      final res = await Supabase.instance.client.functions.invoke('kael-ai', body: {'action': 'voice_search', 'prompt': query});
      final text = (res.data as Map?)?['response']?.toString() ?? '';
      final json = _tryParseJson(text);
      if (json == null) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not understand.'))); return; }
      final book = json['book'] as String?;
      final chapter = json['chapter'] as int?;
      if (book != null && chapter != null && mounted) {
        setState(() { selectedBook = book; selectedChapter = chapter; });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(json['suggestion'] ?? 'No matching passage.')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Search failed. Try again.')));
    }
  }

  Map<String, dynamic>? _tryParseJson(String text) {
    try {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start >= 0 && end > start) return Map<String, dynamic>.from(jsonDecode(text.substring(start, end + 1)));
      return jsonDecode(text);
    } catch (_) { return null; }
  }

}

class _ScriptureSearchDialog extends StatefulWidget {
  final ValueChanged<String> onSubmitted;
  const _ScriptureSearchDialog({required this.onSubmitted});

  @override
  State<_ScriptureSearchDialog> createState() => _ScriptureSearchDialogState();
}

class _ScriptureSearchDialogState extends State<_ScriptureSearchDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      title: const Text("Search Scripture"),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(hintText: "Enter a book name...", icon: Icon(LucideIcons.search)),
        onSubmitted: (value) {
          Navigator.pop(context);
          widget.onSubmitted(value);
        },
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL"))],
    );
  }
}

