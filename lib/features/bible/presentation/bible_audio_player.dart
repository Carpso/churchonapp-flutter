import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:just_audio/just_audio.dart';

/// Bible chapter audio player — streams from LibriVox/Internet Archive.
/// URLs are computed from book abbreviation + chapter number.
/// When user uploads to R2, just change [baseUrl].
class BibleAudioPlayer extends ConsumerStatefulWidget {
  final String bookName;
  final String bookAbbrev;
  final int chapter;
  final int totalChapters;
  final void Function(int newChapter)? onChapterChange;

  const BibleAudioPlayer({
    super.key,
    required this.bookName,
    required this.bookAbbrev,
    required this.chapter,
    required this.totalChapters,
    this.onChapterChange,
  });

  @override
  ConsumerState<BibleAudioPlayer> createState() => _BibleAudioPlayerState();
}

class _BibleAudioPlayerState extends ConsumerState<BibleAudioPlayer> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = true;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(minutes: 1);
  double _speed = 1.0;

  // Base URL for LibriVox KJV recordings. Switch to R2 URL later:
  // static const _baseUrl = 'https://media.churchonapp.com/kjv_audio';
  static const _baseUrl = 'https://archive.org/download/kjv_librivox';

  String get _audioUrl {
    final book = widget.bookAbbrev.toLowerCase().replaceAll(' ', '_');
    final ch = widget.chapter.toString().padLeft(2, '0');
    return '$_baseUrl/${book}_${ch}_kjv.mp3';
  }

  @override
  void didUpdateWidget(BibleAudioPlayer old) {
    super.didUpdateWidget(old);
    if (old.chapter != widget.chapter) _loadAudio();
  }

  @override
  void initState() {
    super.initState();
    _loadAudio();
  }

  Future<void> _loadAudio() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      await _player.setUrl(_audioUrl);
      _player.positionStream.listen((p) => mounted ? setState(() => _position = p) : null);
      _player.durationStream.listen((d) => mounted ? setState(() => _duration = d ?? const Duration(minutes: 1)) : null);
      _player.playerStateStream.listen((s) {
        if (!mounted) return;
        setState(() => _isPlaying = s.playing);
        if (s.processingState == ProcessingState.completed) _nextChapter();
      });
      setState(() { _isLoading = false; _error = null; });
    } catch (e) {
      setState(() { _isLoading = false; _error = 'Audio unavailable — chapter may not be recorded yet. Will be available after R2 upload.'; });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _playPause() => _isPlaying ? _player.pause() : _player.play();

  void _seekRelative(Duration d) {
    final ms = (_position.inMilliseconds + d.inMilliseconds).clamp(0, _duration.inMilliseconds);
    _player.seek(Duration(milliseconds: ms));
  }

  void _prevChapter() {
    if (widget.chapter > 1) widget.onChapterChange?.call(widget.chapter - 1);
  }

  void _nextChapter() {
    if (widget.chapter < widget.totalChapters) widget.onChapterChange?.call(widget.chapter + 1);
  }

  void _setSpeed(double s) {
    setState(() => _speed = s);
    _player.setSpeed(s);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0.0;
    final bookCh = '${widget.bookName} ${widget.chapter}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoading) const Center(child: SizedBox(height: 40, child: CircularProgressIndicator(strokeWidth: 2))),
            if (_error != null) Padding(
              padding: const EdgeInsets.all(12),
              child: Text('🎧 $_error', style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
            ),
            if (!_isLoading) ...[
              // Title + chapter
              Row(children: [
                Expanded(child: Text(bookCh, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                Text(_formatDuration(_position), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const Text(' / ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text(_formatDuration(_duration), style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
              const SizedBox(height: 8),
              // Progress
              ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation(theme.primaryColor))),
              const SizedBox(height: 12),
              // Controls
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(icon: const Icon(LucideIcons.skipBack), onPressed: _prevChapter, iconSize: 20, tooltip: 'Previous chapter'),
                const SizedBox(width: 4),
                IconButton(icon: const Icon(LucideIcons.rewind), onPressed: () => _seekRelative(const Duration(seconds: -10)), iconSize: 18),
                const SizedBox(width: 8),
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primaryColor),
                  child: IconButton(icon: Icon(_isPlaying ? LucideIcons.pause : LucideIcons.play, color: Colors.white, size: 24), onPressed: _playPause),
                ),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(LucideIcons.fastForward), onPressed: () => _seekRelative(const Duration(seconds: 10)), iconSize: 18),
                const SizedBox(width: 4),
                IconButton(icon: const Icon(LucideIcons.skipForward), onPressed: _nextChapter, iconSize: 20, tooltip: 'Next chapter'),
              ]),
              // Speed + auto-advance
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
                      child: Text('${s}x', style: TextStyle(fontSize: 11, color: _speed == s ? theme.primaryColor : Colors.grey, fontWeight: _speed == s ? FontWeight.bold : FontWeight.normal)),
                    ),
                  ),
                )),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours > 0 ? '${d.inHours}:' : '';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h$m:$s';
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
