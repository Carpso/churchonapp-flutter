import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/bible_service.dart';
import '../data/bible_books_service.dart';
import '../data/bible_book_model.dart';

/// Chapter-level parallel reader: shows one chapter side-by-side across
/// 2+ selectable translations (verse-aligned rows).
class ParallelBibleScreen extends ConsumerStatefulWidget {
  final String book;
  final int chapter;

  const ParallelBibleScreen({
    super.key,
    required this.book,
    required this.chapter,
  });

  @override
  ConsumerState<ParallelBibleScreen> createState() =>
      _ParallelBibleScreenState();
}

class _ParallelBibleScreenState extends ConsumerState<ParallelBibleScreen> {
  late List<String> _selectedTranslations;
  late int _chapter;
  int _maxChapter = 150;

  /// Curated, resolvable translation picker (kept readable & ordered).
  static const _pickerCodes = [
    'kjv', 'web', 'asv', 'bbe', 'ylt', 'dra', 'noyes', 'tyndale',
    'webster', 'ukjv', 'mkjv',
  ];

  @override
  void initState() {
    super.initState();
    _chapter = widget.chapter;
    // Default: KJV + WEB (both fully resolvable almost everywhere).
    _selectedTranslations = ['kjv', 'web'];
    _loadMaxChapter();
  }

  Future<void> _loadMaxChapter() async {
    try {
      final books = await ref.read(bibleBooksProvider.future);
      final book = books.cast<BibleBook?>().firstWhere(
            (b) => b?.name == widget.book,
            orElse: () => null,
          );
      if (book != null && mounted) {
        setState(() => _maxChapter = book.chapters);
      }
    } catch (e) {
      debugPrint('Parallel: load max chapter failed: $e');
    }
  }

  Future<void> _openChapterPicker() async {
    final maxCh = _maxChapter;
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Change Chapter',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
            SizedBox(
              height: 320,
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: maxCh,
                itemBuilder: (ctx, i) {
                  final ch = i + 1;
                  final selected = ch == _chapter;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.pop(ctx, ch),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(ctx).primaryColor.withValues(alpha: 0.15)
                            : Theme.of(ctx)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                        border: selected
                            ? Border.all(
                                color: Theme.of(ctx).primaryColor,
                                width: 1.4,
                              )
                            : null,
                      ),
                      child: Text(
                        '$ch',
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w900 : FontWeight.w600,
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
    );
    if (picked != null && mounted) {
      setState(() => _chapter = picked);
    }
  }

  void _toggleTranslation(String code) {
    setState(() {
      if (_selectedTranslations.contains(code)) {
        if (_selectedTranslations.length > 1) {
          _selectedTranslations.remove(code);
        }
      } else {
        _selectedTranslations.add(code);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final resolvable =
        _pickerCodes.where(BibleService.canResolve).toList();
    final ordered = [
      ..._selectedTranslations,
      ...resolvable.where((c) => !_selectedTranslations.contains(c)),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.book} $_chapter — Parallel',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.bookCopy),
            tooltip: 'Change chapter',
            onPressed: _openChapterPicker,
          ),
        ],
      ),
      body: Column(
        children: [
          // Translation picker chips
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in resolvable)
                  FilterChip(
                    label: Text(code.toUpperCase()),
                    selected: _selectedTranslations.contains(code),
                    onSelected: (_) => _toggleTranslation(code),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ref
                .watch(
                  bibleChapterProvider(
                    'kjv|${widget.book}|$_chapter',
                  ),
                )
                .when(
                  data: (baseVerses) {
                    if (baseVerses.isEmpty) {
                      return const Center(
                        child: Text('Chapter not found'),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      itemCount: baseVerses.length,
                      itemBuilder: (ctx, index) {
                        final v = baseVerses[index];
                        return _VerseCompareBlock(
                          book: widget.book,
                          chapter: _chapter,
                          verse: v.verse,
                          translations: ordered,
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (_, __) => const Center(
                    child: Text('Failed to load chapter'),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _VerseCompareBlock extends ConsumerWidget {
  final String book;
  final int chapter;
  final int verse;
  final List<String> translations;

  const _VerseCompareBlock({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.translations,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.grey.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.amber.withValues(alpha: 0.15)
                      : Colors.amber.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$verse',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$book $chapter:$verse',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final code in translations) ...[
            _TranslationRow(
              code: code,
              book: book,
              chapter: chapter,
              verse: verse,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _TranslationRow extends ConsumerWidget {
  final String code;
  final String book;
  final int chapter;
  final int verse;

  const _TranslationRow({
    required this.code,
    required this.book,
    required this.chapter,
    required this.verse,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ref
        .watch(
          parallelVerseTextProvider({
            'translation': code,
            'book': book,
            'chapter': chapter,
            'verse': verse,
          }),
        )
        .when(
          data: (text) => text.trim().isEmpty
              ? const SizedBox.shrink()
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        code.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 0.8,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 14,
                          height: 1.5,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
          loading: () => const SizedBox(
            height: 20,
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, __) => const SizedBox(height: 20),
        );
  }
}