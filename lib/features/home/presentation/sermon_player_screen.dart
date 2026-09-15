import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/providers/audio_provider.dart';
import 'package:church_on_app/core/services/r2_service.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import '../data/sermon_service.dart';
import 'sermon_notes_screen.dart';

/// Extracts the 11-char YouTube video id from any common YouTube URL shape
/// (watch?v=, youtu.be/, /embed/, /shorts/, /live/). Returns null for
/// non-YouTube URLs (direct mp4/hls/audio files).
String? youTubeVideoIdFromUrl(String url) {
  if (url.trim().isEmpty) return null;
  const idPattern = r'([A-Za-z0-9_-]{11})';
  final patterns = <RegExp>[
    RegExp('(?:youtube\\.com|youtube-nocookie\\.com)/watch\\?[^#]*v=$idPattern'),
    RegExp('youtu\\.be/$idPattern'),
    RegExp('(?:youtube\\.com|youtube-nocookie\\.com)/embed/$idPattern'),
    RegExp('(?:youtube\\.com|youtube-nocookie\\.com)/shorts/$idPattern'),
    RegExp('(?:youtube\\.com|youtube-nocookie\\.com)/live/$idPattern'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(url);
    if (m != null && m.group(1) != null) return m.group(1);
  }
  return null;
}

class SermonPlayerScreen extends ConsumerStatefulWidget {
  final Sermon sermon;
  const SermonPlayerScreen({super.key, required this.sermon});

  @override
  ConsumerState<SermonPlayerScreen> createState() => _SermonPlayerScreenState();
}

class _SermonPlayerScreenState extends ConsumerState<SermonPlayerScreen> {
  late VideoPlayerController _videoController;
  bool _hasInitialized = false;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isLiked = false;
  int _amenCount = 0;
  final TextEditingController _commentCtrl = TextEditingController();
  String _resolvedVideoUrl = '';

  /// HLS rendition list parsed from the master playlist. Empty = let ABR decide.
  List<Map<String, String>> _hlsVariants = [];
  String? _activeVariantUrl;
  YoutubePlayerController? _ytController;
  /// The YouTube video id currently loaded (used for the "watch on YouTube"
  /// fallback when the owner has disabled embedded playback — errors 101/150).
  String? _ytId;

  // Audio-only sermons (mp3 / m4a / wav / aac) play through just_audio.
  AudioPlayer? _audioPlayer;
  bool _isAudioOnly = false;
  bool _audioPlaying = false;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  final List<StreamSubscription<dynamic>> _audioSubs = [];

  static bool _looksLikeAudio(String url) {
    final clean = url.split('?').first.toLowerCase();
    return clean.endsWith('.mp3') ||
        clean.endsWith('.m4a') ||
        clean.endsWith('.aac') ||
        clean.endsWith('.wav') ||
        clean.endsWith('.ogg') ||
        clean.endsWith('.opus') ||
        clean.endsWith('.flac');
  }

  @override
  void initState() {
    super.initState();
    _amenCount = widget.sermon.amenCount;
    _initializePlayer();
    _loadUserReaction();
    _recordView();
  }

  /// Counts this sermon as viewed (server dedupes to 1 per user per 6h).
  Future<void> _recordView() async {
    try {
      await ref.read(sermonServiceProvider).recordView(widget.sermon.id);
    } catch (e) {
      debugPrint('Sermon view record error (non-fatal): $e');
    }
  }

  Future<void> _loadUserReaction() async {
    try {
      final service = ref.read(sermonServiceProvider);
      final liked = await service.hasUserReacted(widget.sermon.id, 'amen');
      if (mounted && liked) setState(() => _isLiked = true);
    } catch (e) {
      debugPrint("Amen state load error: $e");
    }
  }

  bool get _hasValidMedia {
    return widget.sermon.videoUrl.isNotEmpty || widget.sermon.audioUrl.isNotEmpty;
  }

  Future<void> _initializePlayer() async {
    if (!_hasValidMedia) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = false;
        });
      }
      return;
    }

    if (mounted) setState(() { _isLoading = true; _hasError = false; });

    try {
      final client = ref.read(supabaseServiceProvider).client;
      final r2 = R2Service(client);
      final rawUrl = widget.sermon.videoUrl.isNotEmpty ? widget.sermon.videoUrl : widget.sermon.audioUrl;

      // YouTube sources are played through an embedded YouTube player — the
      // raw `video_player` (ExoPlayer/AVPlayer) cannot play a YouTube page URL,
      // which is why most listed sermons previously showed "Stream Unavailable".
      final ytId = youTubeVideoIdFromUrl(rawUrl);
      if (ytId != null) {
        _ytId = ytId;
        _ytController = YoutubePlayerController.fromVideoId(
          videoId: ytId,
          autoPlay: true,
          params: const YoutubePlayerParams(
            showFullscreenButton: true,
            showControls: true,
            playsInline: true,
            strictRelatedVideos: true,
            showVideoAnnotations: false,
          ),
        );
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = false;
          });
        }
        return;
      }

      // Audio-only sermon (mp3/m4a/wav/…) — use a real audio player. Feeding an
      // audio file to `video_player` renders a black stage with no seek UX.
      final isAudio = widget.sermon.videoUrl.isEmpty || _looksLikeAudio(widget.sermon.videoUrl);
      if (isAudio) {
        final resolved = await r2.getSignedUrl(rawUrl) ?? rawUrl;
        await _initAudioPlayer(resolved);
        return;
      }

      final resolved = await r2.getSignedUrl(rawUrl);
      _resolvedVideoUrl = resolved ?? rawUrl;
      _loadHlsVariants(_resolvedVideoUrl);

      _videoController = VideoPlayerController.networkUrl(Uri.parse(_resolvedVideoUrl));
      _videoController.addListener(() {
        if (mounted) setState(() {});
      });
      await _videoController.initialize();
      _hasInitialized = true;
      _videoController.play();
      if (mounted) setState(() { _isLoading = false; });
    } catch (e) {
      debugPrint("Sermon player init error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  /// Audio sermons play through the SHARED background audio service so they
  /// keep playing with lock-screen / notification controls (previously a private
  /// `AudioPlayer` died as soon as the screen was closed).
  Future<void> _initAudioPlayer(String url) async {
    try {
      _isAudioOnly = true;
      final handler = ref.read(audioHandlerProvider);
      final song = widget.sermon;
      final art = song.thumbnailUrl;

      if (handler != null) {
        _audioSubs.add(handler.positionStream.listen((p) {
          if (mounted) setState(() => _audioPosition = p);
        }));
        _audioSubs.add(handler.durationStream.listen((d) {
          if (d != null && mounted) setState(() => _audioDuration = d);
        }));
        _audioSubs.add(handler.playingStream.listen((playing) {
          if (mounted) setState(() => _audioPlaying = playing);
        }));
        await handler.playFromUri(Uri.parse(url), {
          'title': song.title,
          'artist': song.preacher,
          'album': 'Sermon',
          'route': '/sermon/${song.id}',
          if (art.isNotEmpty) 'artUri': art,
        });
        if (mounted) setState(() { _isLoading = false; _hasError = false; });
        return;
      }

      // Fallback: no background service available — private player.
      final player = AudioPlayer();
      _audioPlayer = player;
      _audioSubs.add(player.positionStream.listen((p) {
        if (mounted) setState(() => _audioPosition = p);
      }));
      _audioSubs.add(player.durationStream.listen((d) {
        if (d != null && mounted) setState(() => _audioDuration = d);
      }));
      _audioSubs.add(player.playerStateStream.listen((s) {
        if (mounted) setState(() => _audioPlaying = s.playing);
      }));
      await player.setUrl(url);
      player.play();
      if (mounted) setState(() { _isLoading = false; _hasError = false; });
    } catch (e) {
      debugPrint('Sermon audio init error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  /// Seek helper — routes to the shared handler when it is in use so the
  /// on-screen controls stay in sync with the lock-screen ones.
  void _seekAudio(Duration position) {
    final handler = ref.read(audioHandlerProvider);
    if (handler != null && _isAudioOnly && _audioPlayer == null) {
      handler.seek(position);
    } else {
      _audioPlayer?.seek(position);
    }
  }

  void _toggleAudioPlayPause() {
    final handler = ref.read(audioHandlerProvider);
    if (handler != null && _isAudioOnly && _audioPlayer == null) {
      if (_audioPlaying) {
        handler.pause();
      } else {
        handler.play();
      }
    } else {
      final p = _audioPlayer;
      if (p == null) return;
      if (_audioPlaying) {
        p.pause();
      } else {
        p.play();
      }
    }
  }

  @override
  void dispose() {
    if (_hasInitialized) _videoController.dispose();
    _ytController?.close();
    for (final s in _audioSubs) {
      s.cancel();
    }
    _audioPlayer?.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yt = _ytController;
    if (yt != null) {
      // YoutubePlayerScaffold gives the embedded player fullscreen support
      // (orientation switch + immersive UI) without replacing our Scaffold.
      return YoutubePlayerScaffold(
        controller: yt,
        aspectRatio: 16 / 9,
        builder: (context, player) => YoutubeValueBuilder(
          controller: yt,
          // YouTube error 101/150 (= "152-4" in the player UI) means the owner
          // disallowed embedding. Nothing can play it inline — give the viewer
          // a one-tap path to YouTube instead of a dead black box.
          builder: (context, value) => value.hasError
              ? _buildScaffold(context, _buildYouTubeFallback(context, value.error))
              : _buildScaffold(context, player),
        ),
      );
    }
    return _buildScaffold(context, null);
  }

  /// Shown in place of the YouTube embed when the video cannot be embedded.
  Widget _buildYouTubeFallback(BuildContext context, YoutubeError error) {
    final blocked = error == YoutubeError.notEmbeddable ||
        error == YoutubeError.sameAsNotEmbeddable;
    final gone = error == YoutubeError.videoNotFound ||
        error == YoutubeError.cannotFindVideo;
    final title = blocked
        ? 'Playback blocked by the video owner'
        : gone
            ? 'This video is no longer available'
            : 'Video unavailable';
    final subtitle = blocked
        ? 'This sermon can only be watched on YouTube. Tap below to open it there.'
        : 'The video could not be embedded here.';
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              blocked ? LucideIcons.lock : LucideIcons.alertTriangle,
              color: Colors.white70,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (!gone && _ytId != null)
              ElevatedButton.icon(
                onPressed: () => _openOnYouTube(),
                icon: const Icon(LucideIcons.externalLink, size: 16),
                label: const Text('WATCH ON YOUTUBE',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFDA03),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Parse an HLS master playlist's renditions so the viewer can pin a quality
  /// (e.g. save data on a weak connection). Adaptive ABR stays the default when
  /// no manual choice is made.
  Future<void> _loadHlsVariants(String url) async {
    if (!url.contains('.m3u8')) return;
    try {
      String? body;
      try {
        final res =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) body = res.body;
      } catch (e) {
        debugPrint('HLS manifest fetch failed: $e');
      }
      if (body == null || !body.contains('#EXT-X-STREAM-INF')) return;

      final lines = body.split('\n');
      final variants = <Map<String, String>>[];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
        final uri = (i + 1 < lines.length) ? lines[i + 1].trim() : '';
        if (uri.isEmpty || uri.startsWith('#')) continue;
        final resMatch = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
        final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        final label = resMatch != null
            ? '${resMatch.group(2)}p'
            : (bwMatch != null
                ? '${(int.tryParse(bwMatch.group(1) ?? '') ?? 0) ~/ 1000} kbps'
                : 'Variant');
        variants.add({
          'label': label,
          'url': uri.startsWith('http')
              ? uri
              : Uri.parse(url).resolve(uri).toString(),
        });
      }
      if (variants.length <= 1 || !mounted) return;
      setState(() => _hlsVariants = variants);
    } catch (e) {
      debugPrint('HLS variant parse failed: $e');
    }
  }

  /// Re-open the video at a specific rendition, keeping the playhead.
  Future<void> _switchQuality(String? url) async {
    final target = url ?? _resolvedVideoUrl;
    if (target.isEmpty) return;
    try {
      final pos = _hasInitialized ? _videoController.value.position : Duration.zero;
      final wasPlaying = _hasInitialized && _videoController.value.isPlaying;

      if (_hasInitialized) {
        await _videoController.pause();
        await _videoController.dispose();
        _hasInitialized = false;
      }
      if (!mounted) return;
      setState(() {
        _activeVariantUrl = url;
        _isLoading = true;
      });

      _videoController = VideoPlayerController.networkUrl(Uri.parse(target));
      _videoController.addListener(() {
        if (mounted) setState(() {});
      });
      await _videoController.initialize();
      await _videoController.seekTo(pos);
      _hasInitialized = true;
      if (wasPlaying) _videoController.play();
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('quality switch failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _showQualitySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Video quality',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ),
            ListTile(
              leading: Icon(
                _activeVariantUrl == null
                    ? LucideIcons.checkCircle
                    : LucideIcons.circle,
                color: Colors.white70,
                size: 18,
              ),
              title: const Text('Auto (adaptive)',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () {
                Navigator.of(ctx).pop();
                _switchQuality(null);
              },
            ),
            ..._hlsVariants.map((v) => ListTile(
                  leading: Icon(
                    _activeVariantUrl == v['url']
                        ? LucideIcons.checkCircle
                        : LucideIcons.circle,
                    color: Colors.white70,
                    size: 18,
                  ),
                  title: Text(v['label'] ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _switchQuality(v['url']);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openOnYouTube() async {
    final id = _ytId;
    if (id == null) return;
    final uri = Uri.parse('https://www.youtube.com/watch?v=$id');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openOnYouTube failed: $e');
    }
  }

  Widget _buildScaffold(BuildContext context, Widget? ytPlayer) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ytPlayer ?? _buildPlayer(),
              if (_hlsVariants.length > 1)
                SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Material(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          onTap: _showQualitySheet,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.settings2,
                                    color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  _activeVariantUrl == null
                                      ? 'AUTO'
                                      : (_hlsVariants.firstWhere(
                                              (v) => v['url'] == _activeVariantUrl,
                                              orElse: () =>
                                                  const {'label': 'AUTO'})['label'] ??
                                          'AUTO'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
                        onPressed: () => Navigator.of(context).maybePop(),
                        tooltip: 'Back',
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(LucideIcons.sparkles, color: Colors.white, size: 20),
                        onPressed: () => context.push(
                          '/ai-sermon-notes/${widget.sermon.id}',
                          extra: {
                            'title': widget.sermon.title,
                            'content': widget.sermon.transcript ?? '',
                          },
                        ),
                        tooltip: 'AI Sermon Notes',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.sermon.title,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      CircleAvatar(radius: 12, backgroundColor: Theme.of(context).primaryColor, child: const Icon(LucideIcons.user, size: 14)),
                      const SizedBox(width: 8),
                      Text(widget.sermon.preacher, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                      const Spacer(),
                      const Icon(LucideIcons.calendar, size: 14, color: Colors.grey),
                      const SizedBox(width: 5),
                      Text(
                        "${widget.sermon.createdAt.day}/${widget.sermon.createdAt.month}/${widget.sermon.createdAt.year}",
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  _buildActionRow(),
                  const SizedBox(height: 20),
                  _buildLikeCommentSection(),
                  if ((widget.sermon.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 30),
                    const Text(
                      "Description",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.sermon.description!,
                      style: const TextStyle(
                        color: Colors.grey,
                        height: 1.6,
                      ),
                    ),
                  ],
                  const SizedBox(height: 30),
                  _buildApostolicArchive(),
                  const SizedBox(height: 30),
                  _buildRecommendedSection(),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildPlayer() {
    if (_isLoading) {
      return Container(
        width: double.infinity,
        height: 280,
        decoration: const BoxDecoration(color: Colors.black87),
        child: Shimmer.fromColors(
          baseColor: Colors.grey[800]!,
          highlightColor: Colors.grey[700]!,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
              ),
              const SizedBox(height: 20),
              Container(width: 160, height: 12, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6))),
              const SizedBox(height: 16),
              Container(width: 120, height: 8, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4))),
            ],
          ),
        ),
      );
    }

    if (_isAudioOnly) {
      return _buildAudioStage();
    }

    if (!_hasValidMedia) {
      return Container(
        width: double.infinity,
        height: 280,
        decoration: const BoxDecoration(color: Colors.black87),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ResolvedR2Image(
              url: widget.sermon.thumbnailUrl,
              builder: (context, resolvedUrl) => CachedNetworkImage(
                imageUrl: resolvedUrl,
                width: 100,
                height: 100,
                memCacheWidth: 200,
                memCacheHeight: 200,
                fit: BoxFit.cover,
                imageBuilder: (context, imageProvider) => Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).primaryColor, width: 3),
                    image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
                  ),
                ),
                placeholder: (context, url) => Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
                  child: const Icon(LucideIcons.music, color: Colors.amber, size: 30),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
                  child: const Icon(LucideIcons.music, color: Colors.amber, size: 30),
                ),
              ),
            ),
            const SizedBox(height: 15),
            const Icon(LucideIcons.music, color: Colors.amber, size: 14),
            const SizedBox(height: 8),
            const Text(
              "AUDIO SERMON",
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 2),
            ),
          ],
        ),
      );
    }

    if (_hasError) {
      return Container(
        width: double.infinity,
        height: 280,
        decoration: const BoxDecoration(color: Colors.black87),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.alertTriangle, color: Colors.redAccent, size: 36),
            const SizedBox(height: 12),
            const Text(
              "Stream Unavailable",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              "Unable to load media. Check your connection.",
              style: TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                // `_videoController` is `late` — only dispose it if it was ever
                // assigned (init can fail before that and throw
                // LateInitializationError here).
                if (_hasInitialized) {
                  _videoController.dispose();
                  _hasInitialized = false;
                }
                _resolvedVideoUrl = '';
                _initializePlayer();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "RETRY",
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final bool isInitialized = _videoController.value.isInitialized;
    final bool isPlaying = _videoController.value.isPlaying;
    final Duration position = _videoController.value.position;
    final Duration duration = _videoController.value.duration;

    return Container(
      width: double.infinity,
      height: 280,
      decoration: const BoxDecoration(color: Colors.black87),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ResolvedR2Image(
            url: widget.sermon.thumbnailUrl,
            builder: (context, resolvedUrl) => CachedNetworkImage(
              imageUrl: resolvedUrl,
              fit: BoxFit.cover,
              memCacheWidth: 360,
              memCacheHeight: 640,
              color: Colors.black.withValues(alpha: 0.85),
              colorBlendMode: BlendMode.dstATop,
              placeholder: (context, url) => Container(color: Colors.black87, child: const Center(child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2))),
              errorWidget: (context, url, error) => Container(color: Colors.black87, child: const Icon(Icons.broken_image, color: Colors.grey)),
            ),
          ),
          SafeArea(
        bottom: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).primaryColor, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.4),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: ResolvedR2Image(
                url: widget.sermon.thumbnailUrl,
                builder: (context, resolvedUrl) => CachedNetworkImage(
                  imageUrl: resolvedUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 360,
                  memCacheHeight: 640,
                  placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(height: 15),
            AudioVisualizerWidget(isPlaying: isPlaying),
            const SizedBox(height: 15),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.music, color: Colors.amber, size: 14),
                SizedBox(width: 8),
                Text(
                  "STREAMING AUDIO ONLY",
                  style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            
            if (isInitialized)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        activeTrackColor: Theme.of(context).primaryColor,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Theme.of(context).primaryColor,
                      ),
                      child: Slider(
                        value: position.inMilliseconds.toDouble(),
                        max: duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                        onChanged: (val) {
                          _videoController.seekTo(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(position),
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 5),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.skipBack, color: Colors.white, size: 22),
                  onPressed: () {
                    final target = position - const Duration(seconds: 10);
                    _videoController.seekTo(target < Duration.zero ? Duration.zero : target);
                  },
                ),
                const SizedBox(width: 15),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isPlaying) {
                        _videoController.pause();
                      } else {
                        _videoController.play();
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPlaying ? LucideIcons.pause : LucideIcons.play,
                      color: Theme.of(context).colorScheme.secondary,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                IconButton(
                  icon: const Icon(LucideIcons.skipForward, color: Colors.white, size: 22),
                  onPressed: () {
                    final target = position + const Duration(seconds: 10);
                    _videoController.seekTo(target > duration ? duration : target);
                  },
                ),
              ],
            ),
          ],
        ),
        ),
      ],
      ),
    );
  }

  Widget _audioFallbackIcon() => Container(
        color: Colors.white12,
        child: const Icon(LucideIcons.music, color: Colors.amber, size: 40),
      );

  Widget _buildAudioStage() {
    final maxMs = _audioDuration.inMilliseconds > 0 ? _audioDuration.inMilliseconds : 1;
    return Container(
      width: double.infinity,
      height: 280,
      decoration: const BoxDecoration(color: Colors.black87),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).primaryColor, width: 3),
            ),
            child: widget.sermon.thumbnailUrl.isNotEmpty
                ? ResolvedR2Image(
                    url: widget.sermon.thumbnailUrl,
                    builder: (context, resolvedUrl) => CachedNetworkImage(
                      imageUrl: resolvedUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 240,
                      memCacheHeight: 240,
                      errorWidget: (c, _, __) => _audioFallbackIcon(),
                    ),
                  )
                : _audioFallbackIcon(),
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.music, color: Colors.amber, size: 14),
              SizedBox(width: 8),
              Text(
                'AUDIO SERMON',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          if (_hasError)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Unable to load audio',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12)),
            )
          else ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Theme.of(context).primaryColor,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Theme.of(context).primaryColor,
                ),
                child: Slider(
                  value: _audioPosition.inMilliseconds.clamp(0, maxMs).toDouble(),
                  max: maxMs.toDouble(),
                  onChanged: (v) =>
                      _seekAudio(Duration(milliseconds: v.toInt())),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 52),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(_audioPosition),
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  Text(
                    _audioDuration > Duration.zero ? _formatDuration(_audioDuration) : '--:--',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.skipBack, color: Colors.white, size: 22),
                  onPressed: () {
                    final t = _audioPosition - const Duration(seconds: 10);
                    _seekAudio(t < Duration.zero ? Duration.zero : t);
                  },
                ),
                const SizedBox(width: 15),
                GestureDetector(
                  onTap: _toggleAudioPlayPause,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _audioPlaying ? LucideIcons.pause : LucideIcons.play,
                      color: Theme.of(context).colorScheme.secondary,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                IconButton(
                  icon: const Icon(LucideIcons.skipForward, color: Colors.white, size: 22),
                  onPressed: () {
                    final t = _audioPosition + const Duration(seconds: 10);
                    _seekAudio(t > _audioDuration ? _audioDuration : t);
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    String seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Future<void> _toggleAmen() async {
    final wasLiked = _isLiked;
    setState(() {
      _isLiked = !wasLiked;
      _amenCount = _amenCount + (wasLiked ? -1 : 1);
    });
    try {
      await ref.read(sermonServiceProvider).reactToSermon(widget.sermon.id, 'amen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(wasLiked ? "Amen removed." : "Amen! Seed of faith received."),
        ));
      }
    } catch (e) {
      debugPrint("Amen reaction error: $e");
      if (mounted) {
        setState(() {
          _isLiked = wasLiked;
          _amenCount = _amenCount + (wasLiked ? 1 : -1);
        });
      }
    }
  }

  Widget _buildActionRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildActionItem(LucideIcons.heart, _isLiked ? "Amen ✓" : "Amen", onTap: _toggleAmen),
        _buildActionItem(LucideIcons.messageSquare, "Discuss", onTap: () {
          _showComments();
        }),
        _buildActionItem(LucideIcons.share2, "Forward", onTap: () async {
          try {
            await SharePlus.instance.share(ShareParams(
              text: 'Check out this sermon: ${widget.sermon.title} by ${widget.sermon.preacher}',
              title: 'Share Sermon',
            ));
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sharing spiritual wisdom...")));
          } catch (e) {
            debugPrint("Share error: $e");
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to share: $e"), backgroundColor: Colors.red));
          }
        }),
        _buildActionItem(LucideIcons.bookOpen, "Notes", onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SermonNotesScreen(sermon: widget.sermon),
            ),
          );
        }),
      ],
    );
  }

  void _showComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer(builder: (context, ref, child) {
        final insightsAsync = ref.watch(sermonInsightsProvider(widget.sermon.id));
        final commentCtrl = TextEditingController();
        // Single-send guard: Enter key AND the send icon share this flag so a
        // keyboard action + tap can never insert the same insight twice.
        var isSending = false;
        Future<void> sendInsight() async {
          final value = commentCtrl.text.trim();
          if (value.isEmpty || isSending) return;
          isSending = true;
          try {
            await ref
                .read(sermonServiceProvider)
                .reactToSermon(widget.sermon.id, 'discuss', content: value);
            commentCtrl.clear();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("Insight shared successfully!"),
                  backgroundColor: Colors.green));
            }
          } catch (e) {
            debugPrint("Comment error: $e");
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text("Failed to send: $e"),
                  backgroundColor: Colors.red));
            }
          } finally {
            isSending = false;
          }
        }

        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
          padding: const EdgeInsets.all(25),
          child: Column(
            children: [
              const Text("Communal Insights", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const Divider(height: 40),
              Expanded(
                child: insightsAsync.when(skipLoadingOnRefresh: true,
                  data: (comments) => comments.isEmpty 
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.messageCircle, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text("No insights yet", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 16)),
                            const SizedBox(height: 8),
                            const Text("Be the first to share your spiritual insight.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      )
                    : FutureBuilder<Map<String, Map<String, dynamic>>>(
                        future: ref.read(sermonServiceProvider).fetchInsightAuthors(
                              comments
                                  .map((c) => c['user_id']?.toString() ?? '')
                                  .toList(),
                            ),
                        builder: (context, authorsSnap) {
                          final authors = authorsSnap.data ?? const {};
                          return ListView.builder(
                            itemCount: comments.length,
                            itemBuilder: (context, i) {
                              final author =
                                  authors[comments[i]['user_id']?.toString() ?? ''];
                              final name =
                                  author?['full_name']?.toString() ?? 'Member';
                              final avatar = author?['avatar_url']?.toString();
                              return ListTile(
                                leading: CircleAvatar(
                                  child: avatar != null && avatar.isNotEmpty
                                      ? ClipOval(child: AppImage(avatar, width: 40, height: 40, fit: BoxFit.cover))
                                      : Text(name.isNotEmpty ? name[0] : '?'),
                                ),
                                title: Text(comments[i]['content'] ?? "",
                                    style: const TextStyle(fontSize: 14)),
                                subtitle: Text(name,
                                    style: const TextStyle(fontSize: 11)),
                              );
                            },
                          );
                        },
                      ),
                  loading: () => const ListSkeleton(count: 3),
                  error: (e, _) => Center(child: Text("Sync Error: $e")),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: TextField(
                  controller: commentCtrl,
                  onSubmitted: (_) => sendInsight(),
                  decoration: InputDecoration(
                    hintText: "Add your spiritual insight...",
                    suffixIcon: IconButton(
                      icon: const Icon(LucideIcons.send),
                      onPressed: () => sendInsight(),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildActionItem(IconData icon, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle, border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
            child: Icon(icon, color: Theme.of(context).colorScheme.secondary, size: 22),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildLikeCommentSection() {
    final insightsAsync = ref.watch(sermonInsightsProvider(widget.sermon.id));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _toggleAmen,
                child: Row(
                  children: [
                    Icon(
                      _isLiked ? LucideIcons.heart : LucideIcons.heart,
                      color: _isLiked ? Colors.red : Colors.grey,
                      size: 18,
                      fill: _isLiked ? 1.0 : 0.0,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isLiked ? "Amen!" : "Amen",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _isLiked ? Colors.red : Colors.grey,
                      ),
                    ),
                    if (_amenCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '$_amenCount',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 20),
              const Icon(LucideIcons.messageSquare, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              insightsAsync.when(skipLoadingOnRefresh: true,
                data: (comments) => Text(
                  "${comments.length} insight${comments.length == 1 ? '' : 's'}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                ),
                loading: () => const Text("...", style: TextStyle(color: Colors.grey)),
                error: (_, __) => const Text("0 insights", style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          insightsAsync.when(skipLoadingOnRefresh: true,
            data: (comments) {
              if (comments.isEmpty) {
                return const SizedBox.shrink();
              }
              final preview = comments.take(2).toList();
              return FutureBuilder<Map<String, Map<String, dynamic>>>(
                future: ref.read(sermonServiceProvider).fetchInsightAuthors(
                      preview.map((c) => c['user_id']?.toString() ?? '').toList(),
                    ),
                builder: (context, authorsSnap) {
                  final authors = authorsSnap.data ?? const {};
                  return Column(
                    children: preview.map((c) {
                      final author =
                          authors[c['user_id']?.toString() ?? ''];
                      final name =
                          author?['full_name']?.toString() ?? 'Member';
                      final avatar = author?['avatar_url']?.toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 12,
                              child: avatar != null && avatar.isNotEmpty
                                  ? ClipOval(child: AppImage(avatar, width: 24, height: 24, fit: BoxFit.cover))
                                  : Text(name.isNotEmpty ? name[0] : '?'),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            Theme.of(context).primaryColor),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    c['content'] ?? "",
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.black87),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (value) async {
                    if (value.trim().isEmpty) return;
                    final text = value.trim();
                    _commentCtrl.clear();
                    try {
                      await ref.read(sermonServiceProvider).reactToSermon(widget.sermon.id, 'discuss', content: text);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Insight shared successfully!"), backgroundColor: Colors.green));
                    } catch (e) {
                      debugPrint("Comment error: $e");
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to send: $e"), backgroundColor: Colors.red));
                    }
                  },
                  decoration: InputDecoration(
                    hintText: "Share your insight...",
                    hintStyle: const TextStyle(fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade200)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Theme.of(context).primaryColor)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  if (_commentCtrl.text.trim().isEmpty) return;
                  final text = _commentCtrl.text.trim();
                  _commentCtrl.clear();
                  try {
                    await ref.read(sermonServiceProvider).reactToSermon(widget.sermon.id, 'discuss', content: text);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Insight shared successfully!"), backgroundColor: Colors.green));
                  } catch (e) {
                    debugPrint("Comment error: $e");
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to send: $e"), backgroundColor: Colors.red));
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
                  child: Icon(LucideIcons.send, size: 18, color: Theme.of(context).colorScheme.secondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "More from this Series",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        FutureBuilder<List<Sermon>>(
          future: ref
              .read(sermonServiceProvider)
              .fetchLatestSermons(limit: 6, category: widget.sermon.category),
          builder: (context, snapshot) {
            final sermons = (snapshot.data ?? const <Sermon>[])
                .where((s) => s.id != widget.sermon.id)
                .take(3)
                .toList();
            if (sermons.isEmpty) {
              return const Text(
                'No other sermons in this series yet.',
                style: TextStyle(color: Colors.grey),
              );
            }
            return Column(
              children: sermons.map(_buildRecommendedItem).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRecommendedItem(Sermon sermon) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SermonPlayerScreen(sermon: sermon),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 50,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: sermon.thumbnailUrl.isNotEmpty
                  ? ResolvedR2Image(
                      url: sermon.thumbnailUrl,
                      builder: (context, resolvedUrl) => CachedNetworkImage(
                        imageUrl: resolvedUrl,
                        fit: BoxFit.cover,
                      ),
                    )
                  : const Icon(LucideIcons.play, size: 20),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                sermon.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              sermon.durationMinutes == null || sermon.durationMinutes == 0
                  ? ''
                  : '${sermon.durationMinutes} min',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApostolicArchive() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Apostolic Archive", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
              ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.sparkles, color: Colors.amber, size: 18),
                  const SizedBox(width: 10),
                  const Text("AI Summary", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.sermon.aiSummary ??
                    'No AI summary available yet — tap Kael Notes to generate one.',
                style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
              ),
              const Divider(height: 30),
              Row(
                children: [
                  Icon(LucideIcons.fileText, color: Theme.of(context).primaryColor, size: 18),
                  const SizedBox(width: 10),
                  const Text("Full Transcription", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _showFullTranscript(),
                    child: const Text("VIEW FULL", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _transcriptExcerpt(widget.sermon.transcript),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _transcriptExcerpt(String? transcript) {
    if (transcript == null || transcript.trim().isEmpty) {
      return 'No transcription available yet.';
    }
    if (transcript.length <= 200) return transcript;
    return '${transcript.substring(0, 200)}…';
  }

  void _showFullTranscript() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(25, 40, 25, 25),
        child: Column(
          children: [
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(5))),
            const SizedBox(height: 25),
            Row(
              children: [
                Icon(LucideIcons.fileText, color: Theme.of(context).primaryColor),
                const SizedBox(width: 15),
                const Text("Sermon Transcription", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  widget.sermon.transcript ?? 'No transcription available yet.',
                  style: const TextStyle(height: 1.8, color: Colors.black87),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AudioVisualizerWidget extends StatefulWidget {
  final bool isPlaying;
  const AudioVisualizerWidget({super.key, required this.isPlaying});

  @override
  State<AudioVisualizerWidget> createState() => _AudioVisualizerWidgetState();
}

class _AudioVisualizerWidgetState extends State<AudioVisualizerWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _barHeights = [0.2, 0.5, 0.8, 0.3, 0.6, 0.9, 0.4, 0.7, 0.5, 0.3];
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.isPlaying) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant AudioVisualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(_barHeights.length, (index) {
            final double value = widget.isPlaying 
                ? (_controller.value + (index * 0.15)) % 1.0 
                : 0.05;
            final double currentHeight = 10.0 + (_barHeights[index] * 35.0 * (0.3 + 0.7 * (value - 0.5).abs() * 2));
            return Container(
              width: 3,
              height: currentHeight,
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Theme.of(context).primaryColor,
                    Colors.amberAccent,
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

