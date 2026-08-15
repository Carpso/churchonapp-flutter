import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/bible_podcast_service.dart';
import 'deep_study_suite_screen.dart';
import 'package:church_on_app/core/widgets/global_media_player.dart';

class BiblePodcastScreen extends ConsumerStatefulWidget {
  const BiblePodcastScreen({super.key});

  @override
  ConsumerState<BiblePodcastScreen> createState() => _BiblePodcastScreenState();
}

class _BiblePodcastScreenState extends ConsumerState<BiblePodcastScreen> {
  BiblePodcastEpisode? _currentEpisode;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(minutes: 1);

  final FlutterTts _tts = FlutterTts();
  double _ttsSpeed = 1.0;
  double _ttsPitch = 1.0;
  String _ttsVoice = '';
  List<dynamic> _availableVoices = [];
  bool _isReadingVerse = false;

  @override
  void initState() {
    super.initState();
    globalMediaPlayerController.init();
    _initTts();
    
    // Listen to global media player state
    globalMediaPlayerController.state.addListener(_onGlobalPlayerStateChanged);
  }

  void _onGlobalPlayerStateChanged() {
    if (mounted) {
      final state = globalMediaPlayerController.state.value;
      setState(() {
        _isPlaying = state.isPlaying;
        _position = state.position;
        _duration = state.duration;
        if (state.title.isEmpty) {
          _currentEpisode = null;
        }
      });
    }
  }

  Future<void> _initTts() async {
    await _tts.awaitSpeakCompletion(true);
    final voices = await _tts.getVoices;
    if (mounted) {
      setState(() => _availableVoices = voices);
    }
    await _loadTtsSettings();
  }

  Future<void> _loadTtsSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ttsSpeed = prefs.getDouble('tts_speed') ?? 1.0;
      _ttsPitch = prefs.getDouble('tts_pitch') ?? 1.0;
      _ttsVoice = prefs.getString('tts_voice') ?? '';
    });
    await _applyTtsSettings();
  }

  Future<void> _applyTtsSettings() async {
    await _tts.setSpeechRate(_ttsSpeed);
    await _tts.setPitch(_ttsPitch);
    if (_ttsVoice.isNotEmpty) {
      await _tts.setVoice({"name": _ttsVoice, "locale": _ttsVoice});
    }
  }

  Future<void> _saveTtsSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('tts_speed', _ttsSpeed);
    await prefs.setDouble('tts_pitch', _ttsPitch);
    await prefs.setString('tts_voice', _ttsVoice);
  }

  Future<void> _speakVerse(String text) async {
    if (_isReadingVerse) {
      await _tts.stop();
      if (mounted) setState(() => _isReadingVerse = false);
      return;
    }
    if (mounted) setState(() => _isReadingVerse = true);
    await _tts.speak(text);
    if (mounted) setState(() => _isReadingVerse = false);
  }

  void _showVoiceSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text("Voice Settings", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  Text("Speed: ${_ttsSpeed.toStringAsFixed(1)}x", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  Slider(
                    value: _ttsSpeed, min: 0.5, max: 2.0, divisions: 15,
                    activeColor: Colors.amber, inactiveColor: Colors.white24,
                    onChanged: (v) {
                      setSheetState(() => _ttsSpeed = v);
                      setState(() => _ttsSpeed = v);
                      _tts.setSpeechRate(v);
                      _saveTtsSettings();
                    },
                  ),
                  const SizedBox(height: 12),
                  Text("Pitch: ${_ttsPitch.toStringAsFixed(1)}", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  Slider(
                    value: _ttsPitch, min: 0.5, max: 2.0, divisions: 15,
                    activeColor: Colors.amber, inactiveColor: Colors.white24,
                    onChanged: (v) {
                      setSheetState(() => _ttsPitch = v);
                      setState(() => _ttsPitch = v);
                      _tts.setPitch(v);
                      _saveTtsSettings();
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_availableVoices.isNotEmpty) ...[
                    Text("Voice", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _ttsVoice.isNotEmpty ? _ttsVoice : null,
                          hint: const Text("Default", style: TextStyle(color: Colors.white54)),
                          dropdownColor: const Color(0xFF1E293B),
                          items: _availableVoices.map<DropdownMenuItem<String>>((voice) {
                            final name = voice['name']?.toString() ?? '';
                            return DropdownMenuItem(value: name, child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis));
                          }).toList(),
                          onChanged: (v) {
                            setSheetState(() => _ttsVoice = v ?? '');
                            setState(() => _ttsVoice = v ?? '');
                            _applyTtsSettings();
                            _saveTtsSettings();
                          },
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text("Done"),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _tts.stop();
    globalMediaPlayerController.state.removeListener(_onGlobalPlayerStateChanged);
    super.dispose();
  }

  Future<void> _playEpisode(BiblePodcastEpisode episode) async {
    final state = globalMediaPlayerController.state.value;
    
    if (state.title == episode.title && _isPlaying) {
      globalMediaPlayerController.togglePlayPause();
      return;
    }
    
    if (state.title == episode.title && !_isPlaying) {
      globalMediaPlayerController.togglePlayPause();
      return;
    }

    try {
      // Create episode with thumbnail
      final episodeWithThumb = BiblePodcastEpisode(
        id: episode.id,
        title: episode.title,
        book: episode.book,
        duration: episode.duration,
        thumbnailUrl: _getBookThumbnail(episode.book),
        audioUrl: episode.audioUrl,
        description: episode.description,
        hasAudio: episode.hasAudio,
      );
      
      setState(() { _currentEpisode = episodeWithThumb; });
      globalMediaPlayerController.playEpisode(
        title: episodeWithThumb.title,
        subtitle: episodeWithThumb.book,
        audioUrl: episodeWithThumb.audioUrl,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error playing audio: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final episodes = ref.watch(biblePodcastProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _buildSliverAppBar(context),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(25.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("TRENDING PODCASTS", style: GoogleFonts.plusJakartaSans(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      const SizedBox(height: 20),
                      if (episodes.isNotEmpty) ...[
                        _buildFeaturedCard(context, episodes.first),
                      ] else ...[
                        const Center(child: Text("No podcasts available", style: TextStyle(color: Colors.white54))),
                      ],
                      const SizedBox(height: 40),
                      Text("ALL BIBLE BOOKS", style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final episode = episodes[index];
                      final isCurrent = _currentEpisode?.id == episode.id;
                      return _buildEpisodeTile(context, episode, isCurrent, _isPlaying && isCurrent);
                    },
                    childCount: episodes.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 140)),
            ],
          ),
          if (_currentEpisode != null)
            _buildMiniPlayer(_currentEpisode!, _isPlaying),
        ],
      ),
    );
  }

  Widget _buildMiniPlayer(BiblePodcastEpisode episode, bool isPlaying) {
    final progress = _duration.inSeconds > 0 ? _position.inSeconds / _duration.inSeconds : 0.0;

    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 25),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress.clamp(0.0, 1.0), backgroundColor: Colors.white12, valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber), minHeight: 3),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(imageUrl: episode.thumbnailUrl, width: 45, height: 45, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(width: 45, height: 45, color: Colors.grey[800]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(episode.book, style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                      Text(episode.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text("${_fmt(_position)} / ${_fmt(_duration)}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.skipBack, color: Colors.white, size: 20),
                  onPressed: globalMediaPlayerController.skipBackward,
                ),
                GestureDetector(
                  onTap: () => _playEpisode(episode),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                    child: Icon(isPlaying ? LucideIcons.pause : LucideIcons.play, color: Colors.black, size: 20),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.skipForward, color: Colors.white, size: 20),
                  onPressed: globalMediaPlayerController.skipForward,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  String _getBookThumbnail(String book) {
    // Map of book names to thumbnail URLs (using free Christian art from various sources)
    final Map<String, String> thumbnails = {
      'Genesis': 'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?w=400&q=80',
      'Exodus': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      'Leviticus': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      'Numbers': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      'Deuteronomy': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      'Joshua': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      'Judges': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      'Ruth': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      '1 Samuel': 'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?w=400&q=80',
      '2 Samuel': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      '1 Kings': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      '2 Kings': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      '1 Chronicles': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      '2 Chronicles': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      'Ezra': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      'Nehemiah': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      'Esther': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      'Job': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      'Psalms': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      'Proverbs': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      'Ecclesiastes': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      'Song of Solomon': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      'Isaiah': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      'Jeremiah': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      'Lamentations': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      'Ezekiel': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      'Daniel': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      'Hosea': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      'Joel': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      'Amos': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      'Obadiah': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      'Jonah': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      'Micah': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      'Nahum': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      'Habakkuk': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      'Zephaniah': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      'Haggai': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      'Zechariah': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      'Malachi': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      'Matthew': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      'Mark': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      'Luke': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      'John': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      'Acts': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      'Romans': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      '1 Corinthians': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      '2 Corinthians': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      'Galatians': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      'Ephesians': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      'Philippians': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      'Colossians': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      '1 Thessalonians': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      '2 Thessalonians': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      '1 Timothy': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      '2 Timothy': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      'Titus': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      'Philemon': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      'Hebrews': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      'James': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      '1 Peter': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      '2 Peter': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      '1 John': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
      '2 John': 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80',
      '3 John': 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80',
      'Jude': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80',
      'Revelation': 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80',
    };
    return thumbnails[book] ?? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80';
  }

  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 150, pinned: true, backgroundColor: const Color(0xFF1E293B),
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.settings2, color: Colors.white70, size: 20),
          onPressed: _showVoiceSettingsSheet,
          tooltip: 'Voice Settings',
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        title: Text("Bible Books Podcast", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16)),
        background: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.amber.shade700, const Color(0xFF0F172A)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        ),
      ),
    );
  }

  Widget _buildFeaturedCard(BuildContext context, BiblePodcastEpisode episode) {
    return GestureDetector(
      onTap: () => _playEpisode(episode),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(colors: [Color(0xFF4A2C6D), Color(0xFF1A1A2E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(LucideIcons.radio, color: Colors.amber, size: 16),
                const SizedBox(width: 8),
                Text("HOT NEW RELEASE", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                const Spacer(),
                Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle), child: const Icon(LucideIcons.play, color: Colors.black, size: 18)),
              ]),
              const SizedBox(height: 10),
              Text(episode.title, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              Text("${episode.book} • ${episode.duration}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 15),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _playEpisode(episode),
                    icon: const Icon(LucideIcons.play, size: 16),
                    label: const Text("PLAY"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => DeepStudySuiteScreen()),
                      );
                    },
                    icon: const Icon(LucideIcons.bookOpen, size: 16),
                    label: const Text("READ"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeTile(BuildContext context, BiblePodcastEpisode episode, bool isCurrent, bool isPlaying) {
    return GestureDetector(
      onTap: () => _playEpisode(episode),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isCurrent ? Colors.amber.withValues(alpha: 0.15) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: isCurrent ? Border.all(color: Colors.amber.withValues(alpha: 0.3)) : null,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: CachedNetworkImage(imageUrl: episode.thumbnailUrl, width: 60, height: 60, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(width: 60, height: 60, color: Colors.grey[800]),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(episode.book, style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: Text(episode.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (!episode.hasAudio)
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)), child: const Text('TTS', style: TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 4),
                Text(episode.duration, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _speakVerse(episode.description ?? episode.title),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isReadingVerse && isCurrent ? LucideIcons.volumeX : LucideIcons.volume2,
                        color: Colors.amber,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isReadingVerse && isCurrent ? "Stop" : "Read Aloud",
                        style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
            IconButton(
              icon: const Icon(LucideIcons.bookOpen, color: Colors.white30, size: 20),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => DeepStudySuiteScreen()),
                );
              },
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: isCurrent ? Colors.amber : Colors.amber.withAlpha(25), shape: BoxShape.circle),
              child: Icon(isCurrent && isPlaying ? LucideIcons.pause : LucideIcons.play, color: isCurrent ? Colors.black : Colors.amber, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

