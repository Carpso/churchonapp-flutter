import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:church_on_app/features/finance/presentation/lipila_payment_gateway.dart';

class KingdomKlipsScreen extends StatefulWidget {
  const KingdomKlipsScreen({super.key});

  @override
  State<KingdomKlipsScreen> createState() => KingdomKlipsScreenState();
}

class KingdomKlipsScreenState extends State<KingdomKlipsScreen> with WidgetsBindingObserver {
  late PageController _pageController;
  late Future<List<Map<String, dynamic>>> _klipsFuture;
  int _currentPage = 0;
  bool _forYouMode = true;

  void refresh() {
    setState(() {
      _klipsFuture = _fetchKlips();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchKlips() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final data = await Supabase.instance.client
          .from('klips')
          .select('id, video_url, user_name, description, user_avatar, amen_count, comments_count, is_audio, created_at, user_id')
          .order('created_at', ascending: false)
          .limit(50);

      if (userId != null) {
        try {
          final likedKlips = await Supabase.instance.client
              .from('klip_likes')
              .select('klip_id')
              .eq('user_id', userId);
          final likedIds = (likedKlips as List).map((e) => e['klip_id'] as String).toSet();

          for (final k in data) {
            final engagement = (k['amen_count'] ?? 0) + (k['comments_count'] ?? 0) * 2;
            final isLiked = likedIds.contains(k['id']);
            k['_score'] = engagement - (isLiked ? 1000 : 0);
          }

          data.sort((a, b) => (b['_score'] as int).compareTo(a['_score'] as int));
        } catch (e) {
          debugPrint('Recommendation scoring failed, using chronological: $e');
        }
      }

      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Failed to fetch klips: $e');
      return [];
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _klipsFuture = _fetchKlips();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)),
            );
          }
          final klips = snapshot.data ?? [];
          if (klips.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.video, size: 64, color: Colors.grey[700]),
                  const SizedBox(height: 16),
                  const Text(
                    'No Klips yet',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Church leaders can upload short-form videos',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            );
          }

          return Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: klips.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  final k = klips[index];
                  return VideoClipPlayer(
                    key: ValueKey(k['id'] ?? index),
                    videoUrl: k['video_url'] ?? '',
                    author: k['user_name'] ?? '@user',
                    handle: '@${(k['user_name'] ?? 'user').toString().toLowerCase().replaceAll(' ', '_')}',
                    caption: k['description'] ?? '',
                    avatarUrl: k['user_avatar'] ?? '',
                    initialAmenCount: k['amen_count'] ?? 0,
                    initialCommentsCount: k['comments_count'] ?? 0,
                    klipId: k['id']?.toString(),
                    isAudio: k['is_audio'] == true,
                    isActive: index == _currentPage,
                  );
                },
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, top: 8),
                  child: IconButton(
                    icon: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(LucideIcons.flame, color: Color(0xFFFFD700), size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'Klips',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.all(3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  setState(() => _forYouMode = true);
                                  refresh();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _forYouMode ? const Color(0xFFFFD700) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    'For You',
                                    style: TextStyle(
                                      color: _forYouMode ? Colors.black : Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() => _forYouMode = false);
                                  refresh();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: !_forYouMode ? const Color(0xFFFFD700) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    'Latest',
                                    style: TextStyle(
                                      color: !_forYouMode ? Colors.black : Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
}

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
  final bool isActive;

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
    this.isActive = true,
  });

  @override
  State<VideoClipPlayer> createState() => _VideoClipPlayerState();
}

class _VideoClipPlayerState extends State<VideoClipPlayer> with TickerProviderStateMixin {
  VideoPlayerController? _vc;
  late AnimationController _amenBurstAnim;
  late AnimationController _spinAnim;

  bool _isInitialized = false;
  bool _showAmenBurst = false;
  bool _isLiked = false;
  late int _amenCount;
  late int _commentsCount;
  bool _tabVisible = true;
  final TextEditingController _commentCtrl = TextEditingController();
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _amenCount = widget.initialAmenCount;
    _commentsCount = widget.initialCommentsCount;

    _amenBurstAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _spinAnim = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

    if (widget.isActive && widget.videoUrl.isNotEmpty) {
      _initPlayer();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newController = DefaultTabController.maybeOf(context);
    if (newController != _tabController) {
      _tabController?.removeListener(_onTabChanged);
      _tabController = newController;
      _tabController?.addListener(_onTabChanged);
    }
  }

  void _onTabChanged() {
    if (_tabController != null && mounted) {
      final visible = _tabController!.index == 0;
      if (visible != _tabVisible) {
        setState(() => _tabVisible = visible);
        if (visible && widget.isActive && _vc != null && !_vc!.value.isPlaying) {
          _vc!.play();
        } else if (!visible && _vc != null && _vc!.value.isPlaying) {
          _vc!.pause();
        }
      }
    }
  }

  @override
  void didUpdateWidget(VideoClipPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      // Became active — initialize and play
      if (_vc == null && widget.videoUrl.isNotEmpty) {
        _initPlayer();
      } else if (_vc != null && !_vc!.value.isPlaying) {
        _vc!.play();
      }
    } else if (!widget.isActive && oldWidget.isActive) {
      // Became inactive — pause
      if (_vc != null && _vc!.value.isPlaying) {
        _vc!.pause();
      }
    }
  }

  void _initPlayer() {
    _vc = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
          _vc!.play();
          _vc!.setLooping(true);
        }
      }).catchError((_) {
        if (mounted) setState(() => _isInitialized = false);
      });
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    _vc?.dispose();
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
      _isLiked = !_isLiked;
      _amenCount += _isLiked ? 1 : -1;
      _showAmenBurst = _isLiked;
    });
    if (_isLiked) {
      _amenBurstAnim.forward(from: 0);
    }
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) setState(() => _showAmenBurst = false);

    if (widget.klipId != null) {
      try {
        await Supabase.instance.client
            .from('klips')
            .update({'amen_count': _amenCount})
            .eq('id', widget.klipId!);
      } catch (e) {
        debugPrint('Failed to sync amen count: $e');
      }

      try {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId != null && _isLiked) {
          await Supabase.instance.client.from('klip_likes').upsert({
            'user_id': userId,
            'klip_id': widget.klipId,
          });
        } else if (userId != null && !_isLiked) {
          await Supabase.instance.client
              .from('klip_likes')
              .delete()
              .eq('user_id', userId)
              .eq('klip_id', widget.klipId!);
        }
      } catch (e) {
        debugPrint('Error toggling klip like: $e');
      }
    }
  }

  void _togglePlayPause() {
    if (_vc == null) return;
    setState(() {
      _vc!.value.isPlaying ? _vc!.pause() : _vc!.play();
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
                  Text('$_commentsCount Comments', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 240,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.messageSquare, size: 40, color: Colors.grey[600]),
                      const SizedBox(height: 12),
                      const Text('No comments yet', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      const SizedBox(height: 4),
                      const Text('Be the first to say Amen!', style: TextStyle(color: Colors.white38, fontSize: 11)),
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
                      onPressed: () async {
                        final text = _commentCtrl.text.trim();
                        if (text.isNotEmpty && widget.klipId != null) {
                          try {
                            final userId = Supabase.instance.client.auth.currentUser?.id;
                            String? userName;
                            if (userId != null) {
                              final profile = await Supabase.instance.client
                                  .from('profiles')
                                  .select('full_name, username')
                                  .eq('id', userId)
                                  .maybeSingle();
                              userName = profile != null
                                  ? (profile['full_name'] ?? profile['username'] ?? 'User')
                                  : 'User';
                            }
                            await Supabase.instance.client.from('klip_comments').insert({
                              'klip_id': widget.klipId,
                              'content': text,
                              'user_id': userId,
                              'user_name': userName ?? 'User',
                            });
                            setModal(() => _commentsCount++);
                            _commentCtrl.clear();
                          } catch (e) {
                            debugPrint('Failed to post comment: $e');
                          }
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
                      boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.4), blurRadius: 40, spreadRadius: 10)],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: const Icon(LucideIcons.music, color: Colors.white38, size: 60),
                  ),
                ),
              ),
            )
          else if (_isInitialized && _vc != null)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _vc!.value.size.width,
                  height: _vc!.value.size.height,
                  child: VideoPlayer(_vc!),
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700))),

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.25), Colors.transparent, Colors.transparent, Colors.black.withValues(alpha: 0.8)],
              ),
            ),
          ),

          if (_showAmenBurst)
            Center(
              child: ScaleTransition(
                scale: CurvedAnimation(parent: _amenBurstAnim, curve: Curves.elasticOut),
                child: const Icon(LucideIcons.flame, color: Color(0xFFFFD700), size: 110),
              ),
            ),

          if (_isInitialized && _vc != null && !_vc!.value.isPlaying && !_showAmenBurst)
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 56),
              ),
            ),

          Positioned(
            bottom: 110,
            left: 16,
            right: 90,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF0F172A),
                      backgroundImage: widget.avatarUrl.isNotEmpty
                          ? CachedNetworkImageProvider(widget.avatarUrl)
                          : null,
                      child: widget.avatarUrl.isEmpty
                          ? Text(
                              (widget.author.isNotEmpty ? widget.author[0] : 'K').toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
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
                      child: const Text('KLIP', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(widget.caption, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45), maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),

          Positioned(
            bottom: 110,
            right: 14,
            child: Column(
              children: [
                _ActionBtn(
                  icon: LucideIcons.flame,
                  label: _amenCount > 0 ? _formatCount(_amenCount) : 'Amen',
                  color: _isLiked ? const Color(0xFFFFD700) : Colors.white,
                  onTap: _triggerAmen,
                ),
                const SizedBox(height: 18),
                _ActionBtn(
                  icon: LucideIcons.messageSquare,
                  label: _formatCount(_commentsCount),
                  onTap: _openComments,
                ),
                const SizedBox(height: 18),
                _ActionBtn(
                  icon: LucideIcons.share2,
                  label: 'Share',
                  onTap: () {
                    final shareText = '🔥 Watch this Klip on Church On App!\n${widget.caption}\n\nhttps://churchonapp.com/klips/${widget.klipId ?? 'demo'}';
                    SharePlus.instance.share(ShareParams(text: shareText));
                  },
                ),
                const SizedBox(height: 18),
                _ActionBtn(
                  icon: LucideIcons.bookmark,
                  label: 'Save',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Klip saved to your library!'), backgroundColor: Colors.green, duration: Duration(seconds: 2)),
                    );
                  },
                ),
                const SizedBox(height: 18),
                _ActionBtn(
                  icon: LucideIcons.heart,
                  label: 'Give',
                  color: const Color(0xFFE91E63),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => Container(
                        height: MediaQuery.of(ctx).size.height * 0.85,
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                        ),
                        child: LipilaPaymentGateway(
                          amount: 50.0,
                          description: "Klip Offering",
                          category: "offering",
                          onComplete: (success, txId) {
                            if (success) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Offering received! God bless your generous giving."),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          if (_isInitialized && _vc != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                _vc!,
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
            decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 27),
          ),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
