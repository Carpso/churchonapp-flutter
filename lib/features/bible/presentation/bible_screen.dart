import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/bible_service.dart';
import '../data/bible_books_service.dart';
import '../data/bible_book_model.dart';
import '../data/bible_translations.dart';
import '../data/study_settings_provider.dart';
import '../data/biblical_atlas_data.dart';
import '../data/audio_bible_service.dart';
import '../data/bible_verse_service.dart';
import '../data/streak_service.dart';
import '../../notebook/presentation/notebook_screen.dart';
import 'bible_audio_player.dart';
import 'scripture_audio_button.dart';
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
  String selectedTranslation = "kjv";
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

  Future<void> _loadBooks() async {
    try {
      var books = await ref.read(bibleBooksProvider.future);
      // Self-heal the "only 2 books" corruption (stale cache with Genesis/John)
      // — the hardened BibleBooksService now rejects any non-66 cache and
      // repopulates from built-ins, but existing installs already have the bad
      // cache in SharedPreferences. Force a refresh when we detect it.
      if (books.length != 66) {
        debugPrint('BibleScreen: Detected ${books.length} books (expected 66) — force refreshing');
        try {
          books = await ref.read(bibleBooksRefreshProvider(true).future);
        } catch (_) {
          // refresh provider also self-heals — if even that fails, the service
          // returns its 66 built-ins, so we will have a full canon anyway.
        }
      }
      if (!mounted) return;
      setState(() {
        _allBooks = books.length == 66 ? books : books; // always set what we have
        if (widget.initialBook != null) {
          selectedBook = widget.initialBook!;
          selectedChapter = widget.initialChapter ?? 1;
          selectedVerse = widget.initialVerse;
        } else {
          _restoreReadingPosition();
        }
      });
      if (books.length != 66 && mounted) {
        debugPrint('BibleScreen: Still ${books.length} books after refresh — showing built-in fallback will apply on next load');
      }
    } catch (e) {
      debugPrint('BibleScreen _loadBooks failed: $e');
      if (!mounted) return;
      // Last resort: the service's built-ins are 66 and never fail — surface
      // an empty state that lets the user retry.
      setState(() => _allBooks = []);
    }
  }

  Future<void> _restoreReadingPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedBook = prefs.getString('bible_last_book');
      final savedChapter = prefs.getInt('bible_last_chapter') ?? 1;
      final savedTranslation = prefs.getString('bible_last_translation');
      if (!mounted) return;
      setState(() {
        if (savedBook != null && _allBooks.any((b) => b.name == savedBook)) {
          selectedBook = savedBook;
          selectedChapter = savedChapter;
        }
        if (savedTranslation != null) {
          // A translation that can no longer be resolved (e.g. a stale NKJV/NLT
          // selection before those were DB-seeded, or a removed R2 folder) would
          // leave the reader stuck on "No content found" — force KJV instead.
          selectedTranslation = BibleService.canResolve(savedTranslation)
              ? savedTranslation
              : BibleService.fallbackTranslation;
        }
      });
    } catch (e) {
      debugPrint('Bible restore position failed: $e');
    }
  }

  Future<void> _persistReadingPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bible_last_book', selectedBook);
      await prefs.setInt('bible_last_chapter', selectedChapter);
      await prefs.setString('bible_last_translation', selectedTranslation);
    } catch (e) {
      debugPrint('Bible persist position failed: $e');
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

  @override
  Widget build(BuildContext context) {
    // Wire audio bible + streak services into bible feature lifecycle
    ref.watch(audioBibleServiceProvider);
    ref.watch(streakServiceProvider);

    return Scaffold(
      backgroundColor: isDarkTheme
          ? const Color(0xFF121212)
          : Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showBookSelector,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.bookOpen, size: 14, color: Theme.of(context).primaryColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    "$selectedBook $selectedChapter",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).primaryColor, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(LucideIcons.chevronDown, size: 14, color: Theme.of(context).primaryColor),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.listTodo),
            onPressed: _showStudyHub,
            tooltip: "Study Plans",
            constraints: const BoxConstraints(minWidth: 34, minHeight: 40),
          ),
          IconButton(
            icon: const Icon(LucideIcons.brain),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScriptureMemoryScreen()),
            ),
            tooltip: "Scripture Memory",
            constraints: const BoxConstraints(minWidth: 34, minHeight: 40),
          ),
          IconButton(
            icon: const Icon(LucideIcons.map),
            onPressed: _showBiblicalAtlas,
            tooltip: "Biblical Atlas",
            constraints: const BoxConstraints(minWidth: 34, minHeight: 40),
          ),
          IconButton(
            icon: const Icon(LucideIcons.type),
            onPressed: _showAppearanceSettings,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 40),
          ),
          IconButton(
            icon: const Icon(LucideIcons.search),
            onPressed: _showSearchDialog,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 40),
          ),
          IconButton(
            icon: const Icon(LucideIcons.mic, color: Colors.amber),
            onPressed: _voiceSearch,
            tooltip: 'Voice Search',
            constraints: const BoxConstraints(minWidth: 34, minHeight: 40),
          ),
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
    return ref
        .watch(
          bibleChapterProvider(
            '$selectedTranslation|$selectedBook|$selectedChapter',
          ),
        )
        .when(
          data: (verses) {
            if (verses.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.bookOpen,
                      size: 50,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      "No content found",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "$selectedBook $selectedChapter",
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      BibleService.canResolve(selectedTranslation)
                          ? "Check your connection and retry."
                          : "This translation is not available yet — try KJV.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 15),
                    if (selectedTranslation != BibleService.fallbackTranslation)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ElevatedButton.icon(
                          icon: const Icon(LucideIcons.bookOpen, size: 18),
                          onPressed: () {
                            setState(() {
                              selectedTranslation =
                                  BibleService.fallbackTranslation;
                              _persistReadingPosition();
                            });
                            ref
                                .read(studySettingsProvider.notifier)
                                .setTranslation(BibleService.fallbackTranslation);
                          },
                          label: const Text("SWITCH TO KJV"),
                        ),
                      ),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(
                        bibleChapterProvider(
                          '$selectedTranslation|$selectedBook|$selectedChapter',
                        ),
                      ),
                      child: const Text("RETRY"),
                    ),
                  ],
                ),
              );
            }
            if (widget.initialVerse != null && !_hasScrolledToVerse) {
              _hasScrolledToVerse = true;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _scrollToVerse(widget.initialVerse!),
              );
            }
            return Column(
              children: [
                // Chapter navigator
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Explicit book picker — always visible, large hit area for small phones
                      OutlinedButton.icon(
                        onPressed: _showBookSelector,
                        icon: Icon(LucideIcons.bookOpen, size: 14, color: Theme.of(context).primaryColor),
                        label: Text(
                          _allBooks.isEmpty ? 'Books…' : '${_allBooks.length} Books',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Theme.of(context).primaryColor),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.22)),
                          backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(LucideIcons.chevronLeft, size: 20),
                        onPressed: selectedChapter > 1
                            ? () => setState(() {
                                selectedChapter--;
                                _persistReadingPosition();
                              })
                            : null,
                      ),
                      GestureDetector(
                        onTap: _showChapterSelector,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Text(
                            "Chapter $selectedChapter",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade800,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.chevronRight, size: 20),
                        onPressed: selectedChapter < _maxChapter
                            ? () => setState(() {
                                selectedChapter++;
                                _persistReadingPosition();
                              })
                            : null,
                      ),
                    ],
                  ),
                ),
                // Audio player — toggled from Audio tab
                if (_showAudioPlayer)
                  BibleAudioPlayer(
                    bookName: selectedBook,
                    bookAbbrev:
                        kjvBookAbbrevs[selectedBook] ??
                        selectedBook.toLowerCase(),
                    chapter: selectedChapter,
                    totalChapters: _maxChapter,
                    translationCode: selectedTranslation,
                    verses: verses,
                    onChapterChange: (ch) => setState(() {
                      selectedChapter = ch;
                      _persistReadingPosition();
                    }),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: _verseScrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 25,
                      vertical: 15,
                    ),
                    itemCount: verses.length,
                    itemBuilder: (context, index) {
                      final v = verses[index];
                      final key = "${v.chapter}:${v.verse}";
                      final isHighlighted = _highlightedVerses.contains(key);
                      final bookOrder = _bookOrderFor(selectedBook);
                      final chapterNotes = bookOrder == null
                          ? const <VerseNote>[]
                          : ref
                                  .watch(
                                    verseNotesProvider({
                                      'bookId': bookOrder,
                                      'chapter': selectedChapter,
                                    }),
                                  )
                                  .value ??
                              const <VerseNote>[];
                      final notesForVerse =
                          chapterNotes.where((n) => n.verse == v.verse);
                      final hasBookmark =
                          notesForVerse.any((n) => n.isBookmark);
                      final hasFavorite =
                          notesForVerse.any((n) => n.isFavorite);
                      final hasNote = notesForVerse
                          .any((n) => n.note.trim().isNotEmpty);
                      return GestureDetector(
                        onTap: () {
                          if (_activeBottomTab == 0) {
                            // Highlight mode — tap to toggle highlight
                            setState(() {
                              if (_highlightedVerses.contains(key)) {
                                _highlightedVerses.remove(key);
                              } else {
                                _highlightedVerses.add(key);
                              }
                            });
                          } else {
                            _showVerseDetail(v);
                          }
                        },
                        onLongPress: () => _showVerseDetail(v),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 10,
                          ),
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? Colors.amber.withValues(alpha: 0.15)
                                : (isDarkTheme
                                      ? Colors.white.withValues(alpha: 0.04)
                                      : Colors.grey.withValues(alpha: 0.06)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isHighlighted
                                      ? Colors.amber
                                      : Colors.amber.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${v.verse}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: isHighlighted
                                        ? Colors.black
                                        : Colors.amber.shade800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: v.text,
                                        style: TextStyle(
                                          color: isDarkTheme
                                              ? Colors.white
                                              : const Color(0xFF2D3436),
                                          fontSize: fontSize,
                                          height: 1.7,
                                          fontFamily: 'Georgia',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (hasBookmark || hasFavorite || hasNote)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 6,
                                    top: 2,
                                  ),
                                  child: Column(
                                    children: [
                                      if (hasBookmark)
                                        Icon(
                                          LucideIcons.bookmark,
                                          size: 13,
                                          color: Theme.of(context).primaryColor,
                                        ),
                                      if (hasFavorite)
                                        Icon(
                                          LucideIcons.heart,
                                          size: 13,
                                          color: Theme.of(context).primaryColor.withValues(alpha: 0.75),
                                        ),
                                      if (hasNote)
                                        Icon(
                                          LucideIcons.stickyNote,
                                          size: 13,
                                          color: Theme.of(context).primaryColor.withValues(alpha: 0.55),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.amber),
          ),
          error: (e, s) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.wifiOff, size: 40, color: Colors.grey),
                const SizedBox(height: 10),
                const Text(
                  "Failed to load chapter",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                Text(
                  "$e",
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 15),
                ElevatedButton(
                  onPressed: () => ref.invalidate(
                    bibleChapterProvider(
                      '$selectedTranslation|$selectedBook|$selectedChapter',
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                  ),
                  child: const Text(
                    "RETRY",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
  }

  void _showVerseDetail(BibleVerse verse) {
    final reference = "$selectedBook ${verse.chapter}:${verse.verse}";
    final bookOrder = _bookOrderFor(selectedBook);
    final fullText = "${verse.text}\n— $reference";

    Future<void> deleteNote() async {
      final messenger = ScaffoldMessenger.of(context);
      if (bookOrder == null) return;
      final service = ref.read(bibleVerseServiceProvider);
      // Fetch the existing note for this verse and remove it entirely
      // (toggle-off for highlights/bookmarks + explicit delete).
      final notes = await service.fetchVerseNotes(
        bookId: bookOrder,
        chapter: verse.chapter,
      );
      final mine = notes.where((n) =>
          n.verse == verse.verse &&
          (n.note.trim().isNotEmpty || n.isBookmark || n.isFavorite));
      var deletedAny = false;
      for (final n in mine) {
        final ok = await service.deleteVerseNote(n.id);
        if (ok) deletedAny = true;
      }
      ref.invalidate(
        verseNotesProvider({
          'bookId': bookOrder,
          'chapter': verse.chapter,
        }),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(deletedAny ? "Removed" : "Nothing saved on this verse yet"),
          backgroundColor: deletedAny ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 1),
        ),
      );
    }

    void saveNote(
      String label, {
      bool isBookmark = false,
      bool isFavorite = false,
      String? noteText,
    }) async {
      final messenger = ScaffoldMessenger.of(context);
      if (bookOrder == null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text("$label saved locally"),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 1),
          ),
        );
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
      ref.invalidate(
        verseNotesProvider({
          'bookId': bookOrder,
          'chapter': verse.chapter,
        }),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text("$label saved"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final verseNotes = bookOrder == null
              ? const <VerseNote>[]
              : ref
                      .watch(
                        verseNotesProvider({
                          'bookId': bookOrder,
                          'chapter': verse.chapter,
                          'verse': verse.verse,
                        }),
                      )
                      .value ??
                  const <VerseNote>[];
          final existingNote = verseNotes.isEmpty ? null : verseNotes.first;
          final isBookmarked = existingNote?.isBookmark ?? false;
          final isFavorited = existingNote?.isFavorite ?? false;
          final parallelCodes = ['kjv', 'web']
              .where((c) => c != selectedTranslation && BibleService.canResolve(c))
              .toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                reference,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                selectedTranslation.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          verse.text,
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.6,
                            fontStyle: FontStyle.italic,
                            fontFamily: 'Georgia',
                            color: isDarkTheme
                                ? Colors.white70
                                : Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            ScriptureAudioButton(
                              reference: reference,
                              text: verse.text,
                              iconColor: Theme.of(context).primaryColor,
                              iconSize: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Listen',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 28),
                        const Text(
                          'ACTIONS',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: 1.5,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _actionChip(
                              isFavorited
                                  ? LucideIcons.heartOff
                                  : LucideIcons.highlighter,
                              isFavorited ? 'Unhighlight' : 'Highlight',
                              Colors.amber,
                              onTap: () => saveNote(
                                isFavorited ? 'Highlight removed' : 'Highlight',
                                isFavorite: true,
                              ),
                            ),
                            _actionChip(
                              LucideIcons.copy,
                              "Copy",
                              Theme.of(context).primaryColor,
                              onTap: () async {
                                final messenger =
                                    ScaffoldMessenger.of(context);
                                await Clipboard.setData(
                                  ClipboardData(text: fullText),
                                );
                                messenger.showSnackBar(
                                  const SnackBar(content: Text("Verse copied")),
                                );
                              },
                            ),
                            _actionChip(
                              LucideIcons.share2,
                              "Share",
                              Colors.green,
                              onTap: () {
                                SharePlus.instance
                                    .share(ShareParams(text: fullText));
                              },
                            ),
                            _actionChip(
                              LucideIcons.bookmark,
                              isBookmarked ? 'Bookmarked' : "Bookmark",
                              Theme.of(context).primaryColor.withValues(alpha: 0.7),
                              onTap: () =>
                                  saveNote("Bookmark", isBookmark: true),
                            ),
                            _actionChip(
                              LucideIcons.pencil,
                              "Note",
                              Colors.orange,
                              onTap: () {
                                _showNoteDialog(
                                  reference,
                                  verse.text,
                                  saveNote,
                                );
                              },
                            ),
                            if (verseNotes.any((n) =>
                                n.note.trim().isNotEmpty ||
                                n.isBookmark ||
                                n.isFavorite))
                              _actionChip(
                                LucideIcons.trash2,
                                'Delete',
                                Colors.red,
                                onTap: deleteNote,
                              ),
                          ],
                        ),
                        if (verseNotes.any((n) => n.note.trim().isNotEmpty)) ...[
                          const SizedBox(height: 22),
                          const Text(
                            'YOUR NOTES',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              letterSpacing: 1.5,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...verseNotes
                              .where((n) => n.note.trim().isNotEmpty)
                              .map(
                                (n) => Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.orange.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    n.note,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                        ],
                        const SizedBox(height: 22),
                        const Text(
                          'PARALLEL TRANSLATIONS',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: 1.5,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final code in parallelCodes) ...[
                          _buildParallelTile(code, verse),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 12),
                        const Text(
                          'CROSS REFERENCES',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: 1.5,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (bookOrder == null)
                          const Text(
                            'Unavailable',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          )
                        else
                          ref
                              .watch(
                                verseCrossReferencesProvider({
                                  'bookId': bookOrder,
                                  'chapter': verse.chapter,
                                  'verse': verse.verse,
                                }),
                              )
                              .when(
                                data: (refs) => refs.isEmpty
                                    ? const Text(
                                        'No cross-references found',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      )
                                    : Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: refs
                                            .map(
                                              (r) => GestureDetector(
                                                onTap: () {
                                                  Navigator.pop(context);
                                                  _openCrossReference(
                                                    r.targetRef,
                                                  );
                                                },
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 6,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context)
                                                        .primaryColor
                                                        .withValues(
                                                          alpha: 0.1,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                    border: Border.all(
                                                      color: Theme.of(context)
                                                          .primaryColor
                                                          .withValues(
                                                            alpha: 0.3,
                                                          ),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    r.targetRef,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Theme.of(context)
                                                          .primaryColor,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                loading: () => const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                                error: (_, __) => const SizedBox.shrink(),
                              ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildParallelTile(String code, BibleVerse verse) {
    return ref
        .watch(
          parallelVerseTextProvider({
            'translation': code,
            'book': selectedBook,
            'chapter': verse.chapter,
            'verse': verse.verse,
          }),
        )
        .when(
          data: (text) => text.trim().isEmpty
              ? const SizedBox.shrink()
              : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDarkTheme
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 1,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        text,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          fontFamily: 'Georgia',
                          color: isDarkTheme
                              ? Colors.white70
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
          loading: () => const SizedBox(
            height: 40,
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
        );
  }

  void _openCrossReference(String targetRef) {
    final parts = targetRef.split(' ');
    if (parts.isEmpty) return;
    final bookAbbr = parts.sublist(0, parts.length - 1).join(' ');
    final cv = parts.last.split(':');
    final book = _allBooks
        .where(
          (b) =>
              b.abbreviation.toLowerCase() ==
              bookAbbr.toLowerCase(),
        )
        .firstOrNull;
    if (book == null) return;
    final chapter = int.tryParse(cv[0]);
    final verse = cv.length > 1 ? int.tryParse(cv[1].split('-').first) : null;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BibleScreen(
          initialBook: book.name,
          initialChapter: chapter ?? 1,
          initialVerse: verse,
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

  void _showNoteDialog(
    String reference,
    String verseText,
    void Function(
      String label, {
      bool isBookmark,
      bool isFavorite,
      String? noteText,
    })
    saveNote,
  ) {
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(context);
              saveNote("Note", noteText: text);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(
    IconData icon,
    String label,
    Color color, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        Future.microtask(onTap);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudyPane() {
    final screenW = MediaQuery.sizeOf(context).width;
    return Container(
      width: screenW < 640 ? double.infinity : 300,
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
                const Text(
                  "DEEP STUDY",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1.5,
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 16),
                  onPressed: () => setState(() => isStudyPaneOpen = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: 5,
              itemBuilder: (context, index) {
                switch (index) {
                  case 0:
                    return _buildStudySection("READING", [
                      "$selectedBook $selectedChapter",
                      "Tap verses to highlight, long-press to copy, share or take notes.",
                    ]);
                  case 1:
                    return const SizedBox(height: 30);
                  case 2:
                    return _buildStudySection("STUDY TOOLS", [
                      "Deep Study Suite: word studies, atlas & verse memory",
                      "Cross-references, chapter summaries & reading plans",
                    ]);
                  case 3:
                    return const SizedBox(height: 30);
                  case 4:
                    return _buildStudySection("OPEN DEEP STUDY", [
                      "Open the Deep Study Suite for exegesis, atlas, memory verses and more.",
                    ]);
                  default:
                    return const SizedBox.shrink();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _shareCurrentChapter() {
    final state = ref.read(
      bibleChapterProvider(
        '$selectedTranslation|$selectedBook|$selectedChapter',
      ),
    );
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
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: Colors.amber,
          ),
        ),
        const SizedBox(height: 10),
        ...items.map(
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              i,
              style: TextStyle(
                color: isDarkTheme ? Colors.white70 : Colors.black87,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotebookScreen()),
                  );
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
              padding: EdgeInsets.symmetric(
                horizontal: isActive ? 14 : 8,
                vertical: 6,
              ),
              decoration: isActive
                  ? BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(15),
                    )
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tabs[i]['icon'] as IconData,
                    color: isActive
                        ? Colors.amber
                        : (isDarkTheme ? Colors.white60 : Colors.grey),
                    size: 20,
                  ),
                  if (isActive) ...[
                    const SizedBox(width: 6),
                    Text(
                      tabs[i]['label'] as String,
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                const Text(
                  'Biblical Atlas',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Explore biblical locations',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
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
                      child: const Icon(
                        LucideIcons.mapPin,
                        color: Colors.amber,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      loc.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      loc.era,
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Text(
                      '${loc.latitude.toStringAsFixed(2)}, ${loc.longitude.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
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
              const Text(
                "SELECT BOOK",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 5),
              Text(
                "${_allBooks.length} books",
                style: TextStyle(
                  color: _allBooks.length == 66 ? Colors.grey : Colors.orange,
                  fontSize: 12,
                  fontWeight: _allBooks.length == 66 ? FontWeight.normal : FontWeight.bold,
                ),
              ),
              if (_allBooks.length != 66)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.alertTriangle, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Only ${_allBooks.length}/66 books loaded — tap to fix',
                          style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          try {
                            await ref.read(bibleBooksRefreshProvider(true).future);
                          } catch (_) {}
                          await _loadBooks();
                          if (mounted) _showBookSelector();
                        },
                        child: const Text('FIX', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 20),
              // OT / NT tabs
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setModalState(() => _bookSelectorTab = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _bookSelectorTab == 0
                              ? Colors.amber.withValues(alpha: 0.2)
                              : Colors.amber.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: _bookSelectorTab == 0
                              ? Border.all(color: Colors.amber, width: 1.5)
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            "Old Testament",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: _bookSelectorTab == 0
                                  ? Colors.amber.shade800
                                  : Colors.amber,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setModalState(() => _bookSelectorTab = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _bookSelectorTab == 1
                              ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
                              : Theme.of(context).primaryColor.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: _bookSelectorTab == 1
                              ? Border.all(color: Theme.of(context).primaryColor, width: 1.5)
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            "New Testament",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: _bookSelectorTab == 1
                                  ? Theme.of(context).primaryColor
                                  : Theme.of(context).primaryColor.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 2.5,
                  ),
                  itemCount: _bookSelectorTab == 0
                      ? _allBooks
                            .where((b) => b.testament == Testament.old)
                            .length
                      : _allBooks
                            .where((b) => b.testament == Testament.nt)
                            .length,
                  itemBuilder: (context, index) {
                    final booksInTestament = _bookSelectorTab == 0
                        ? _allBooks
                              .where((b) => b.testament == Testament.old)
                              .toList()
                        : _allBooks
                              .where((b) => b.testament == Testament.nt)
                              .toList();
                    final book = booksInTestament[index].name;
                    final isSelected = book == selectedBook;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedBook = book;
                          selectedChapter = 1;
                          _persistReadingPosition();
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.amber
                              : (isDarkTheme
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.grey.withValues(alpha: 0.08)),
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(color: Colors.amber)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          book,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? Colors.black
                                : (isDarkTheme
                                      ? Colors.white
                                      : const Color(0xFF1A1A2E)),
                            fontWeight: isSelected
                                ? FontWeight.w900
                                : FontWeight.w600,
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

  void _showChapterSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.all(25),
          child: Column(
            children: [
              const Text(
                "SELECT CHAPTER",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 5),
              Text(
                "$selectedBook • $_maxChapter chapters",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const Divider(height: 20),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.4,
                  ),
                  itemCount: _maxChapter,
                  itemBuilder: (context, index) {
                    final chapter = index + 1;
                    final isSelected = chapter == selectedChapter;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedChapter = chapter;
                          _persistReadingPosition();
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.amber
                              : (isDarkTheme
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.grey.withValues(alpha: 0.08)),
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(color: Colors.amber)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$chapter',
                          style: TextStyle(
                            fontSize: 13,
                            color: isSelected
                                ? Colors.black
                                : (isDarkTheme
                                      ? Colors.white
                                      : const Color(0xFF1A1A2E)),
                            fontWeight: isSelected
                                ? FontWeight.w900
                                : FontWeight.w600,
                          ),
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
            ),
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "READER SETTINGS",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 25),
                // Dropdown row: Expanded wrapper so long translation names
                // never overflow the sheet on narrow phones.
                Row(
                  children: [
                    const Text("Translation",
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: selectedTranslation,
                        underline: Container(height: 1, color: Colors.grey.shade300),
                        items: kEnglishTranslations
                            .map(
                              (t) => DropdownMenuItem<String>(
                                value: t.code,
                                enabled: BibleService.canResolve(t.code),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(t.name,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    if (!BibleService.canResolve(t.code))
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: Text(
                                          '(soon)',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              selectedTranslation = v;
                              _persistReadingPosition();
                            });
                            ref
                                .read(studySettingsProvider.notifier)
                                .setTranslation(v);
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text("Font Size"),
                    Expanded(
                      child: Slider(
                        value: localFontSize,
                        min: 12,
                        max: 32,
                        activeColor: Colors.amber,
                        onChanged: (v) =>
                            setModalState(() => localFontSize = v),
                        onChangeEnd: (v) => setState(() => fontSize = v),
                      ),
                    ),
                  ],
                ),
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
                const Divider(height: 30),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(LucideIcons.fileSearch),
                  title: const Text("Bible Content Audit"),
                  subtitle: const Text("Check verse coverage per book"),
                  trailing: const Icon(LucideIcons.chevronRight, size: 18),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/bible-books-audit');
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
        allBooks: _allBooks,
        onBookSelected: (book) {
          setState(() {
            selectedBook = book;
            selectedChapter = 1;
            _persistReadingPosition();
          });
        },
        onVerseSelected: (reference) {
          final parts = reference.split(' ');
          if (parts.length < 2) return;
          final cv = parts.last.split(':');
          final bookName = parts.sublist(0, parts.length - 1).join(' ');
          final chapter = int.tryParse(cv.first) ?? 1;
          final verse = cv.length > 1 ? int.tryParse(cv[1].split('-').first) : null;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BibleScreen(
                initialBook: bookName,
                initialChapter: chapter,
                initialVerse: verse,
              ),
            ),
          );
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
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "BIBLE STUDY HUB",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                "Reading plans, church studies & memory tools",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 25),
              _buildStudyHubTile(
                icon: LucideIcons.calendarCheck,
                title: "My Reading Plans",
                subtitle: "Daily scripture journeys with progress tracking",
                color: Theme.of(context).primaryColor,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StudyPlansScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildStudyHubTile(
                icon: LucideIcons.users,
                title: "Church Bible Studies",
                subtitle: "Join group study sessions with your church",
                color: Theme.of(context).primaryColor.withValues(alpha: 0.75),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BibleStudyListScreen(),
                    ),
                  );
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ScriptureMemoryScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
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
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              color: color.withValues(alpha: 0.5),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _voiceSearch() async {
    final query = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Bible Voice Search'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g. play the story of Joseph, Genesis 1',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
    if (query == null || query.isEmpty) return;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'kael-ai',
        body: {'action': 'voice_search', 'prompt': query},
      );
      final text = (res.data as Map?)?['response']?.toString() ?? '';
      final json = _tryParseJson(text);
      if (json == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not understand.')),
          );
        }
        return;
      }
      final book = json['book'] as String?;
      final chapter = json['chapter'] as int?;
      if (book != null && chapter != null && mounted) {
        setState(() {
          selectedBook = book;
          selectedChapter = chapter;
          _persistReadingPosition();
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(json['suggestion'] ?? 'No matching passage.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Search failed. Try again.')),
        );
      }
    }
  }

  Map<String, dynamic>? _tryParseJson(String text) {
    try {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start >= 0 && end > start) {
        return Map<String, dynamic>.from(
          jsonDecode(text.substring(start, end + 1)),
        );
      }
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }
}

class _ScriptureSearchDialog extends ConsumerStatefulWidget {
  final ValueChanged<String> onBookSelected;
  final ValueChanged<String> onVerseSelected;
  final List<BibleBook> allBooks;
  const _ScriptureSearchDialog({
    required this.onBookSelected,
    required this.onVerseSelected,
    required this.allBooks,
  });

  @override
  ConsumerState<_ScriptureSearchDialog> createState() =>
      _ScriptureSearchDialogState();
}

class _ScriptureSearchDialogState extends ConsumerState<_ScriptureSearchDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    // Full-text verse search (DB + cached books) — falls back to book-name
    // matching when the query is a book title.
    final resultsAsync = query.length >= 3
        ? ref.watch(scriptureSearchProvider(query))
        : null;
    final bookMatches = widget.allBooks
        .where((b) =>
            query.length >= 2 &&
            b.name.toLowerCase().contains(query.toLowerCase()))
        .toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      title: const Text("Search Scripture"),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                hintText: "Search verses, topics or book name...",
                icon: Icon(LucideIcons.search),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: query.length < 3
                  ? Center(
                      child: Text("Type at least 3 characters to search",
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                    )
                  : resultsAsync!.when(
                      data: (hits) {
                        final total = hits.length + bookMatches.length;
                        if (total == 0) {
                          return Center(
                            child: Text('No matches for "$query"',
                                style: TextStyle(color: Colors.grey.shade500)),
                          );
                        }
                        return ListView(
                          children: [
                            if (bookMatches.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 6),
                                child: Text("BOOKS",
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.2,
                                        color: Colors.grey)),
                              ),
                              ...bookMatches.map((b) => ListTile(
                                    dense: true,
                                    leading: const Icon(LucideIcons.bookOpen,
                                        size: 18, color: Colors.amber),
                                    title: Text(b.name),
                                    subtitle: Text('${b.chapters} chapters',
                                        style: const TextStyle(fontSize: 11)),
                                    onTap: () {
                                      Navigator.pop(context);
                                      widget.onBookSelected(b.name);
                                    },
                                  )),
                            ],
                            if (hits.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 6),
                                child: Text("VERSES",
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.2,
                                        color: Colors.grey)),
                              ),
                              ...hits.take(30).map((hit) => ListTile(
                                    dense: true,
                                    leading: const Icon(LucideIcons.textQuote,
                                        size: 18, color: Colors.amber),
                                    title: Text(hit.text,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13)),
                                    subtitle: Text(hit.reference,
                                        style: const TextStyle(fontSize: 11)),
                                    onTap: () {
                                      Navigator.pop(context);
                                      widget.onVerseSelected(hit.reference);
                                    },
                                  )),
                            ],
                          ],
                        );
                      },
                      loading: () => const Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      error: (e, _) => Center(
                          child: Text("Search failed: $e",
                              style: const TextStyle(color: Colors.red))),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("CANCEL"),
        ),
      ],
    );
  }
}
