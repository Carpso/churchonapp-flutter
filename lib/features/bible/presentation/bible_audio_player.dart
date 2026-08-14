import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/features/bible/data/audio_bible_service.dart';
import 'package:church_on_app/features/bible/data/bible_service.dart';

/// Bible chapter audio player — TTS only.
///
/// Reads the chapter aloud with on-device Flutter TTS in ANY translation.
/// (Dramatized LibriVox recordings are used only in the Bible Podcast.)
class BibleAudioPlayer extends ConsumerStatefulWidget {
  final String bookName;
  final String bookAbbrev;
  final int chapter;
  final int totalChapters;
  final String translationCode;
  final List<BibleVerse>? verses;
  final void Function(int newChapter)? onChapterChange;

  const BibleAudioPlayer({
    super.key,
    required this.bookName,
    required this.bookAbbrev,
    required this.chapter,
    required this.totalChapters,
    this.translationCode = 'kjv',
    this.verses,
    this.onChapterChange,
  });

  @override
  ConsumerState<BibleAudioPlayer> createState() => _BibleAudioPlayerState();
}

class _BibleAudioPlayerState extends ConsumerState<BibleAudioPlayer> {
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _wasPlaying = false;
  String? _error;
  double _speed = 1.0;
  StreamSubscription<bool>? _ttsSub;

  AudioBibleService get _tts => ref.read(audioBibleServiceProvider);

  bool get _ttsAvailable =>
      widget.verses != null && widget.verses!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _load();
  }

  @override
  void didUpdateWidget(BibleAudioPlayer old) {
    super.didUpdateWidget(old);
    final chapterChanged = old.chapter != widget.chapter;
    final translationChanged = old.translationCode != widget.translationCode;
    final versesChanged = old.verses != widget.verses;
    if (chapterChanged || translationChanged || versesChanged) {
      _load();
    }
  }

  void _subscribe() {
    _ttsSub?.cancel();
    _ttsSub = _tts.speechStateStream.listen((playing) {
      if (!mounted) return;
      setState(() {
        _isPlaying = playing;
        if (playing) _wasPlaying = true;
      });
      // Chapter finished naturally (not paused, not stopped manually) →
      // advance to the next chapter.
      if (!playing && _wasPlaying && !_tts.isPausedSpeech) {
        _wasPlaying = false;
        _nextChapter();
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _isPlaying = false;
      _wasPlaying = false;
    });
    if (!_ttsAvailable) {
      setState(() {
        _isLoading = false;
        _error = 'Audio unavailable — chapter text not loaded.';
      });
      return;
    }
    await _tts.initialize();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _error = null;
    });
  }

  @override
  void dispose() {
    _ttsSub?.cancel();
    _tts.stopSpeech();
    super.dispose();
  }

  Future<void> _playPause() async {
    final service = _tts;
    if (_isPlaying) {
      _wasPlaying = false;
      await service.pauseSpeech();
      return;
    }
    if (service.isPausedSpeech) {
      _wasPlaying = true;
      await service.resumeSpeech();
      return;
    }
    setState(() => _isLoading = true);
    await service.speakChapterText(
      widget.bookName,
      widget.chapter,
      widget.verses!,
    );
    if (mounted) setState(() => _isLoading = false);
  }

  void _prevChapter() {
    if (widget.chapter > 1) widget.onChapterChange?.call(widget.chapter - 1);
  }

  void _nextChapter() {
    if (widget.chapter < widget.totalChapters) {
      widget.onChapterChange?.call(widget.chapter + 1);
    }
  }

  Future<void> _setSpeed(double s) async {
    setState(() => _speed = s);
    await _tts.setSpeechRate(s);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bookCh = '${widget.bookName} ${widget.chapter}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoading)
              const Center(
                child: SizedBox(height: 40, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '🎧 $_error',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            if (!_isLoading && _error == null) ...[
              // Title + chapter
              Row(children: [
                Expanded(
                  child: Text(
                    bookCh,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Text(
                  '${widget.translationCode.toUpperCase()} · on-device voice',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ]),
              const SizedBox(height: 12),
              // Controls
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(icon: const Icon(LucideIcons.skipBack), onPressed: _prevChapter, iconSize: 20, tooltip: 'Previous chapter'),
                const SizedBox(width: 8),
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primaryColor),
                  child: IconButton(
                    icon: Icon(_isPlaying ? LucideIcons.pause : LucideIcons.play, color: Colors.white, size: 24),
                    onPressed: _playPause,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(LucideIcons.skipForward), onPressed: _nextChapter, iconSize: 20, tooltip: 'Next chapter'),
              ]),
              // Speed
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Speed:', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ...[0.75, 1.0, 1.25, 1.5].map((s) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: GestureDetector(
                    onTap: () => _setSpeed(s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _speed == s ? theme.primaryColor.withValues(alpha: 0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${s}x',
                        style: TextStyle(
                          fontSize: 11,
                          color: _speed == s ? theme.primaryColor : Colors.grey,
                          fontWeight: _speed == s ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                )),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Read aloud from the ${widget.translationCode.toUpperCase()} text — works offline for every translation.',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Maps Bible book names to their LibriVox abbreviation for URL construction.
const Map<String, String> kjvBookAbbrevs = {
  'Genesis': 'genesis', 'Exodus': 'exodus', 'Leviticus': 'leviticus',
  'Numbers': 'numbers', 'Deuteronomy': 'deuteronomy', 'Joshua': 'joshua',
  'Judges': 'judges', 'Ruth': 'ruth', '1 Samuel': '1_samuel', '2 Samuel': '2_samuel',
  '1 Kings': '1_kings', '2 Kings': '2_kings', '1 Chronicles': '1_chronicles',
  '2 Chronicles': '2_chronicles', 'Ezra': 'ezra', 'Nehemiah': 'nehemiah',
  'Esther': 'esther', 'Job': 'job', 'Psalm': 'psalms', 'Proverbs': 'proverbs',
  'Ecclesiastes': 'ecclesiastes', 'Song of Solomon': 'song_of_solomon',
  'Isaiah': 'isaiah', 'Jeremiah': 'jeremiah', 'Lamentations': 'lamentations',
  'Ezekiel': 'ezekiel', 'Daniel': 'daniel', 'Hosea': 'hosea', 'Joel': 'joel',
  'Amos': 'amos', 'Obadiah': 'obadiah', 'Jonah': 'jonah', 'Micah': 'micah',
  'Nahum': 'nahum', 'Habakkuk': 'habakkuk', 'Zephaniah': 'zephaniah',
  'Haggai': 'haggai', 'Zechariah': 'zechariah', 'Malachi': 'malachi',
  'Matthew': 'matthew', 'Mark': 'mark', 'Luke': 'luke', 'John': 'john',
  'Acts': 'acts', 'Romans': 'romans', '1 Corinthians': '1_corinthians',
  '2 Corinthians': '2_corinthians', 'Galatians': 'galatians', 'Ephesians': 'ephesians',
  'Philippians': 'philippians', 'Colossians': 'colossians',
  '1 Thessalonians': '1_thessalonians', '2 Thessalonians': '2_thessalonians',
  '1 Timothy': '1_timothy', '2 Timothy': '2_timothy', 'Titus': 'titus',
  'Philemon': 'philemon', 'Hebrews': 'hebrews', 'James': 'james',
  '1 Peter': '1_peter', '2 Peter': '2_peter', '1 John': '1_john',
  '2 John': '2_john', '3 John': '3_john', 'Jude': 'jude', 'Revelation': 'revelation',
};

/// Chapter counts per book (KJV standard).
const Map<String, int> kjvChapterCounts = {
  'Genesis': 50, 'Exodus': 40, 'Leviticus': 27, 'Numbers': 36, 'Deuteronomy': 34,
  'Joshua': 24, 'Judges': 21, 'Ruth': 4, '1 Samuel': 31, '2 Samuel': 24,
  '1 Kings': 22, '2 Kings': 25, '1 Chronicles': 29, '2 Chronicles': 36,
  'Ezra': 10, 'Nehemiah': 13, 'Esther': 10, 'Job': 42, 'Psalm': 150, 'Proverbs': 31,
  'Ecclesiastes': 12, 'Song of Solomon': 8, 'Isaiah': 66, 'Jeremiah': 52,
  'Lamentations': 5, 'Ezekiel': 48, 'Daniel': 12, 'Hosea': 14, 'Joel': 3,
  'Amos': 9, 'Obadiah': 1, 'Jonah': 4, 'Micah': 7, 'Nahum': 3, 'Habakkuk': 3,
  'Zephaniah': 3, 'Haggai': 2, 'Zechariah': 14, 'Malachi': 4,
  'Matthew': 28, 'Mark': 16, 'Luke': 24, 'John': 21, 'Acts': 28, 'Romans': 16,
  '1 Corinthians': 16, '2 Corinthians': 13, 'Galatians': 6, 'Ephesians': 6,
  'Philippians': 4, 'Colossians': 4, '1 Thessalonians': 5, '2 Thessalonians': 3,
  '1 Timothy': 6, '2 Timothy': 4, 'Titus': 3, 'Philemon': 1, 'Hebrews': 13,
  'James': 5, '1 Peter': 5, '2 Peter': 3, '1 John': 5, '2 John': 1, '3 John': 1,
  'Jude': 1, 'Revelation': 22,
};