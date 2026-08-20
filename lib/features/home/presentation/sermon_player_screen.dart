import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/services/r2_service.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import '../data/sermon_service.dart';
import 'sermon_notes_screen.dart';

class SermonPlayerScreen extends ConsumerStatefulWidget {
  final Sermon sermon;
  const SermonPlayerScreen({super.key, required this.sermon});

  @override
  ConsumerState<SermonPlayerScreen> createState() => _SermonPlayerScreenState();
}

class _SermonPlayerScreenState extends ConsumerState<SermonPlayerScreen> {
  late VideoPlayerController _videoController;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isLiked = false;
  int _amenCount = 0;
  final TextEditingController _commentCtrl = TextEditingController();
  String _resolvedVideoUrl = '';

  @override
  void initState() {
    super.initState();
    _amenCount = widget.sermon.amenCount;
    _initializePlayer();
    _loadUserReaction();
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
      final resolved = await r2.getSignedUrl(rawUrl);
      _resolvedVideoUrl = resolved ?? rawUrl;

      _videoController = VideoPlayerController.networkUrl(Uri.parse(_resolvedVideoUrl));
      _videoController.addListener(() {
        if (mounted) setState(() {});
      });
      await _videoController.initialize();
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

  @override
  void dispose() {
    _videoController.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              _buildPlayer(),
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
                          extra: {'title': widget.sermon.title},
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
                  const SizedBox(height: 30),
                  const Text(
                    "Description",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Discover the spiritual foundations of stewardship and how to manage the blessings of faith in this powerful message. Pastor John explores the biblical principles of faith and finance.",
                    style: TextStyle(color: Colors.grey, height: 1.6),
                  ),
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

    if (!_hasValidMedia) {
      return Container(
        width: double.infinity,
        height: 280,
        decoration: const BoxDecoration(color: Colors.black87),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CachedNetworkImage(
              imageUrl: widget.sermon.thumbnailUrl,
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
                _videoController.dispose();
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
          CachedNetworkImage(
            imageUrl: widget.sermon.thumbnailUrl,
            fit: BoxFit.cover,
            memCacheWidth: 360,
            memCacheHeight: 640,
            color: Colors.black.withValues(alpha: 0.85),
            colorBlendMode: BlendMode.dstATop,
            placeholder: (context, url) => Container(color: Colors.black87, child: const Center(child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2))),
            errorWidget: (context, url, error) => Container(color: Colors.black87, child: const Icon(Icons.broken_image, color: Colors.grey)),
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
              child: CachedNetworkImage(
                imageUrl: widget.sermon.thumbnailUrl,
                fit: BoxFit.cover,
                memCacheWidth: 360,
                memCacheHeight: 640,
                placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey),
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
          Navigator.push(context, MaterialPageRoute(builder: (context) => const SermonNotesScreen()));
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

        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
          padding: const EdgeInsets.all(25),
          child: Column(
            children: [
              const Text("Communal Insights", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const Divider(height: 40),
              Expanded(
                child: insightsAsync.when(
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
                    : ListView.builder(
                        itemCount: comments.length,
                        itemBuilder: (context, i) => ListTile(
                          leading: const CircleAvatar(child: Icon(LucideIcons.user, size: 14)),
                          title: Text(comments[i]['content'] ?? "", style: const TextStyle(fontSize: 14)),
                          subtitle: const Text("Citizen", style: TextStyle(fontSize: 11)),
                        ),
                      ),
                  loading: () => const ListSkeleton(count: 3),
                  error: (e, _) => Center(child: Text("Sync Error: $e")),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: TextField(
                  controller: commentCtrl,
                  onSubmitted: (value) async {
                    if (value.trim().isEmpty) return;
                    try {
                      await ref.read(sermonServiceProvider).reactToSermon(widget.sermon.id, 'discuss', content: value.trim());
                      commentCtrl.clear();
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Insight shared successfully!"), backgroundColor: Colors.green));
                    } catch (e) {
                      debugPrint("Comment error: $e");
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to send: $e"), backgroundColor: Colors.red));
                    }
                  },
                  decoration: InputDecoration(
                    hintText: "Add your spiritual insight...",
                    suffixIcon: IconButton(
                      icon: const Icon(LucideIcons.send),
                      onPressed: () async {
                        if (commentCtrl.text.isEmpty) return;
                        try {
                          await ref.read(sermonServiceProvider).reactToSermon(widget.sermon.id, 'discuss', content: commentCtrl.text);
                          commentCtrl.clear();
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Insight shared successfully!"), backgroundColor: Colors.green));
                        } catch (e) {
                          debugPrint("Comment error: $e");
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to send: $e"), backgroundColor: Colors.red));
                        }
                      },
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
              insightsAsync.when(
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
          insightsAsync.when(
            data: (comments) {
              if (comments.isEmpty) {
                return const SizedBox.shrink();
              }
              final preview = comments.take(2).toList();
              return Column(
                children: preview.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                        radius: 12,
                        child: Icon(LucideIcons.user, size: 12),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Citizen",
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c['content'] ?? "",
                              style: const TextStyle(fontSize: 13, color: Colors.black87),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )).toList(),
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
         const Text("More from this Series", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
         const SizedBox(height: 20),
         _buildRecommendedItem("Part 1: The Covenant of Plenty", "12:45"),
         _buildRecommendedItem("Part 2: Multipliers", "15:20"),
      ],
    );
  }

  Widget _buildRecommendedItem(String title, String duration) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 50,
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
            child: const Icon(LucideIcons.play, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(duration, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
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
                widget.sermon.aiSummary ?? "This sermon explores the foundational principles of stewardship, emphasizing faithfulness and spiritual multiplier effects in everyday life.",
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
                widget.sermon.transcript?.substring(0, 200) ?? "In the beginning of this profound message, Pastor John Doe invites us to consider the ultimate source of all our blessings. He reminds us that true prosperity is not measured solely by material wealth, but by our capacity to be faithful stewards of what has been entrusted to us...",
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
                  widget.sermon.transcript ?? "Transcription pending... In the beginning of this profound message, Pastor John Doe invites us to consider the ultimate source of all our blessings. He reminds us that true prosperity is not measured solely by material wealth, but by our capacity to be faithful stewards of what has been entrusted to us. As we dive into the Word today, let us open our hearts to the multiplier effect that comes from a life fully surrendered to spiritual service. It's about being a conduit for grace, not just a reservoir. (Complete archive available on the VPS)",
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

