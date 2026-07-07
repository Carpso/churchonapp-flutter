import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';

class KingdomKlipsScreen extends StatefulWidget {
  const KingdomKlipsScreen({super.key});

  @override
  State<KingdomKlipsScreen> createState() => KingdomKlipsScreenState();
}

class KingdomKlipsScreenState extends State<KingdomKlipsScreen> {
  late PageController _pageController;
  late Future<List<Map<String, dynamic>>> _klipsFuture;

  // 3 guaranteed sample klips using free Google sample videos
  static const List<Map<String, String>> _sampleKlips = [
    {
      'id': 'sample-1',
      'url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
      'author': 'Pastor Abel Banda',
      'handle': '@pastor_abel',
      'caption': '🔥 God\'s fire purifies and empowers. Stay in His presence! #Faith #Revival',
      'avatar': 'https://i.pravatar.cc/100?img=51',
      'amen_count': '3.2K',
      'comments_count': '184',
      'is_audio': 'false',
    },
    {
      'id': 'sample-2',
      'url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
      'author': 'Worship Ministry',
      'handle': '@worship_unity',
      'caption': '🕊️ Psalm 23 meditation — He restores my soul. Take a moment with God today.',
      'avatar': 'https://i.pravatar.cc/100?img=47',
      'amen_count': '1.8K',
      'comments_count': '95',
      'is_audio': 'false',
    },
    {
      'id': 'sample-3',
      'url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
      'author': 'Bible Study Hub',
      'handle': '@biblestudyhub',
      'caption': '📖 John 3:16 — For God so loved the world. Share this Good News! #Gospel',
      'avatar': 'https://i.pravatar.cc/100?img=32',
      'amen_count': '5.1K',
      'comments_count': '312',
      'is_audio': 'false',
    },
  ];

  void refresh() {
    setState(() {
      _klipsFuture = _fetchKlips();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchKlips() async {
    try {
      final data = await Supabase.instance.client
          .from('klips')
          .select('*')
          .order('created_at', ascending: false)
          .limit(20);
      final dbKlips = List<Map<String, dynamic>>.from(data);
      if (dbKlips.isNotEmpty) return dbKlips;
    } catch (e) {
      debugPrint('Failed to fetch klips from DB, using samples: $e');
    }
    // Always fall back to sample klips so screen is never empty
    return _sampleKlips.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _klipsFuture = _fetchKlips();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _klipsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)));
          }
          final klips = snapshot.data ?? _sampleKlips.map((e) => Map<String, dynamic>.from(e)).toList();

          return Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: klips.length,
                itemBuilder: (context, index) {
                  final k = klips[index];
                  return VideoClipPlayer(
                    key: ValueKey(k['id'] ?? k['url'] ?? index),
                    videoUrl: k['video_url'] ?? k['url'] ?? '',
                    author: k['user_name'] ?? k['author'] ?? '@kingdom',
                    handle: k['handle'] ?? '@${(k['user_name'] ?? k['author'] ?? 'kingdom').toString().toLowerCase().replaceAll(' ', '_')}',
                    caption: k['description'] ?? k['caption'] ?? '',
                    avatarUrl: k['avatar'] ?? 'https://i.pravatar.cc/100',
                    initialAmenCount: _parseCount(k['amen_count'] ?? k['likes']),
                    initialCommentsCount: _parseCount(k['comments_count'] ?? k['comments']),
                    klipId: k['id']?.toString(),
                    isAudio: k['is_audio'] == 'true' || k['is_audio'] == true,
                  );
                },
              ),
              // Back button
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, top: 8),
                  child: IconButton(
                    icon: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              // "Kingdom Klips" header
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.flame, color: Color(0xFFFFD700), size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'Kingdom Klips',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  int _parseCount(dynamic val) {
    if (val == null) return 0;
    final s = val.toString().replaceAll('K', '').replaceAll('.', '');
    if (val.toString().contains('K')) {
      return (double.tryParse(val.toString().replaceAll('K', '')) ?? 0 * 1000).toInt();
    }
    return int.tryParse(s) ?? 0;
  }
}

// ─── Full-screen TikTok-style player ─────────────────────────────────────────

class VideoClipPlayer extends StatefulWidget {
  final String videoUrl;
  final String author;
  final String handle;
  final String caption;
  final String avatarUrl;
  final int initialAmenCount;
  final int initialCommentsCount;
  final String? klipId;
  final bool isAudio;

  const VideoClipPlayer({
    super.key,
    required this.videoUrl,
    required this.author,
    required this.handle,
    required this.caption,
    required this.avatarUrl,
    required this.initialAmenCount,
    required this.initialCommentsCount,
    this.klipId,
    this.isAudio = false,
  });

  @override
  State<VideoClipPlayer> createState() => _VideoClipPlayerState();
}

class _VideoClipPlayerState extends State<VideoClipPlayer> with TickerProviderStateMixin {
  late VideoPlayerController _vc;
  late AnimationController _amenBurstAnim;
  late AnimationController _spinAnim;

  bool _isInitialized = false;
  bool _showAmenBurst = false;
  bool _isLiked = false;
  late int _amenCount;
  late int _commentsCount;

  final List<String> _comments = [
    "🙌 Amen! What an inspiring word!",
    "This touched my heart deeply. Praise God!",
    "God's grace is indeed sufficient. 🕊️",
    "So powerful, thanks for sharing Pastor!",
    "Fire! 🔥 This is the word I needed today.",
  ];
  final TextEditingController _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _amenCount = widget.initialAmenCount;
    _commentsCount = widget.initialCommentsCount;

    _amenBurstAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _spinAnim = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

    _vc = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
          _vc.play();
          _vc.setLooping(true);
        }
      }).catchError((_) {
        if (mounted) setState(() => _isInitialized = false);
      });
  }

  @override
  void dispose() {
    _vc.dispose();
    _amenBurstAnim.dispose();
    _spinAnim.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    _triggerAmen();
  }

  void _triggerAmen() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isLiked = true;
      _amenCount++;
      _showAmenBurst = true;
    });
    _amenBurstAnim.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) setState(() => _showAmenBurst = false);

    // Persist to Supabase
    if (widget.klipId != null && !widget.klipId!.startsWith('sample')) {
      try {
        await Supabase.instance.client
            .from('klips')
            .update({'amen_count': _amenCount})
            .eq('id', widget.klipId!);
      } catch (e) {
        debugPrint('Failed to sync amen count: $e');
      }
    }
  }

  void _togglePlayPause() {
    setState(() {
      _vc.value.isPlaying ? _vc.pause() : _vc.play();
    });
  }

  void _openComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 20, right: 20, top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 48, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(LucideIcons.messageSquare, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text('${_comments.length} Comments', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 240,
                child: ListView.separated(
                  itemCount: _comments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(radius: 16, backgroundImage: NetworkImage('https://i.pravatar.cc/60?img=${i + 10}')),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                          child: Text(_comments[i], style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(30)),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _commentCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(hintText: 'Add your amen…', hintStyle: TextStyle(color: Colors.white38), border: InputBorder.none),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.send, color: Color(0xFFFFD700)),
                      onPressed: () {
                        final text = _commentCtrl.text.trim();
                        if (text.isNotEmpty) {
                          setModal(() => _comments.add(text));
                          setState(() => _commentsCount++);
                          _commentCtrl.clear();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      onTap: _togglePlayPause,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video / Audio background ──────────────────────────────────────
          if (widget.isAudio)
            Container(
              color: const Color(0xFF0F172A),
              child: Center(
                child: RotationTransition(
                  turns: _spinAnim,
                  child: Container(
                    width: 200, height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFFD700), width: 4),
                      image: const DecorationImage(image: NetworkImage('https://images.unsplash.com/photo-1516280440614-37939bbacd81?w=600'), fit: BoxFit.cover),
                      boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.4), blurRadius: 40, spreadRadius: 10)],
                    ),
                  ),
                ),
              ),
            )
          else if (_isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _vc.value.size.width,
                  height: _vc.value.size.height,
                  child: VideoPlayer(_vc),
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700))),

          // ── Gradient overlays ─────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.25), Colors.transparent, Colors.transparent, Colors.black.withValues(alpha: 0.75)],
              ),
            ),
          ),

          // ── Amen burst animation ──────────────────────────────────────────
          if (_showAmenBurst)
            Center(
              child: ScaleTransition(
                scale: CurvedAnimation(parent: _amenBurstAnim, curve: Curves.elasticOut),
                child: const Icon(LucideIcons.flame, color: Color(0xFFFFD700), size: 110),
              ),
            ),

          // ── Pause indicator ───────────────────────────────────────────────
          if (_isInitialized && !_vc.value.isPlaying && !_showAmenBurst)
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 56),
              ),
            ),

          // ── Author & caption (bottom-left) ────────────────────────────────
          Positioned(
            bottom: 90,
            left: 16,
            right: 90,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(radius: 18, backgroundImage: NetworkImage(widget.avatarUrl)),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.author, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                        Text(widget.handle, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12)),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFFFD700), borderRadius: BorderRadius.circular(4)),
                      child: const Text('KINGDOM', style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(widget.caption, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45), maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(LucideIcons.music, color: Colors.white54, size: 13),
                    const SizedBox(width: 6),
                    Text('Original Sound · Church On App', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),

          // ── Right action bar ──────────────────────────────────────────────
          Positioned(
            bottom: 90,
            right: 14,
            child: Column(
              children: [
                // Amen / fire reaction
                _ActionBtn(
                  icon: LucideIcons.flame,
                  label: _amenCount > 0 ? _formatCount(_amenCount) : 'Amen',
                  color: _isLiked ? const Color(0xFFFFD700) : Colors.white,
                  onTap: _triggerAmen,
                ),
                const SizedBox(height: 22),
                // Comments
                _ActionBtn(
                  icon: LucideIcons.messageSquare,
                  label: _formatCount(_commentsCount),
                  onTap: _openComments,
                ),
                const SizedBox(height: 22),
                // Share
                _ActionBtn(
                  icon: LucideIcons.share2,
                  label: 'Share',
                  onTap: () {
                    final shareText = '🔥 Watch this Kingdom Klip on Church On App!\n${widget.caption}\n\nhttps://churchonapp.com/klips/${widget.klipId ?? 'demo'}';
                    SharePlus.instance.share(ShareParams(text: shareText));
                  },
                ),
                const SizedBox(height: 22),
                // Save
                _ActionBtn(
                  icon: LucideIcons.bookmark,
                  label: 'Save',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Klip saved to your library!'), backgroundColor: Colors.green, duration: Duration(seconds: 2)),
                    );
                  },
                ),
                const SizedBox(height: 22),
                // Avatar disc
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFFD700), width: 2),
                  ),
                  child: CircleAvatar(radius: 20, backgroundImage: NetworkImage(widget.avatarUrl)),
                ),
              ],
            ),
          ),

          // ── Progress bar ──────────────────────────────────────────────────
          if (_isInitialized)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                _vc,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Color(0xFFFFD700),
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

// ─── Reusable right-bar action button ────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionBtn({required this.icon, required this.label, this.color = Colors.white, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 27),
          ),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
