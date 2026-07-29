import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
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
  late AudioPlayer _player;
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
    _player = AudioPlayer();
    
    _player.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() { _isPlaying = false; _position = Duration.zero; });
    });

    _initTts();
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
    _player.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _playEpisode(BiblePodcastEpisode episode) async {
    if (_currentEpisode?.id == episode.id && _isPlaying) {
      await _player.pause();
      setState(() => _isPlaying = false);
      return;
    }
    
    if (_currentEpisode?.id == episode.id && !_isPlaying) {
      await _player.resume();
      setState(() => _isPlaying = true);
      return;
    }

    try {
      setState(() { _currentEpisode = episode; _isPlaying = true; });
      await _player.stop();
      await _player.play(UrlSource(episode.audioUrl));

      globalMediaPlayerController.playEpisode(
        title: episode.title,
        subtitle: episode.book,
        audioUrl: episode.audioUrl,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isPlaying = false);
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
                      Text("TRENDING PODCASTS", style: GoogleFonts.plusJakartaSans(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      const SizedBox(height: 20),
                      if (episodes.isNotEmpty) ...[
                        _buildFeaturedCard(context, episodes.first),
                      ] else ...[
                        const Center(child: Text("No podcasts available", style: TextStyle(color: Colors.white54))),
                      ],
                      const SizedBox(height: 40),
                      Text("ALL BIBLE BOOKS", style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
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
                  child: Image.network(episode.thumbnailUrl, width: 45, height: 45, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(width: 45, height: 45, color: Colors.grey[800]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(episode.book, style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                      Text(episode.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text("${_fmt(_position)} / ${_fmt(_duration)}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.skipBack, color: Colors.white, size: 20),
                  onPressed: () => _player.seek(Duration(seconds: (_position.inSeconds - 15).clamp(0, _duration.inSeconds))),
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
                  onPressed: () => _player.seek(Duration(seconds: (_position.inSeconds + 15).clamp(0, _duration.inSeconds))),
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
          image: DecorationImage(image: NetworkImage(episode.thumbnailUrl), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withAlpha(102), BlendMode.darken)),
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
                Text("HOT NEW RELEASE", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
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
              child: Image.network(episode.thumbnailUrl, width: 60, height: 60, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(width: 60, height: 60, color: Colors.grey[800]),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(episode.book, style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                const SizedBox(height: 4),
                Text(episode.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
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

