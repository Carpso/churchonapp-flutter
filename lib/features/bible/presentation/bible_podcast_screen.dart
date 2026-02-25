import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import '../data/bible_podcast_service.dart';

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
  }

  @override
  void dispose() {
    _player.dispose();
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)],
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
        height: 200, width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          image: DecorationImage(image: NetworkImage(episode.thumbnailUrl), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withAlpha(102), BlendMode.darken)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
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
              Text(episode.title, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text("${episode.book} • ${episode.duration}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
          color: isCurrent ? Colors.amber.withOpacity(0.15) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: isCurrent ? Border.all(color: Colors.amber.withOpacity(0.3)) : null,
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
              ]),
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

