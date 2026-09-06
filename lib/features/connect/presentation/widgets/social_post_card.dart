import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/widgets/post_image_carousel.dart';
import '../../data/social_service.dart';

class SocialPostCard extends ConsumerStatefulWidget {
  final SocialPost post;
  final String Function(DateTime) formatTimeAgo;
  final VoidCallback? onCommentTap;
  final VoidCallback? onShareTap;

  const SocialPostCard({
    super.key,
    required this.post,
    required this.formatTimeAgo,
    this.onCommentTap,
    this.onShareTap,
  });

  @override
  ConsumerState<SocialPostCard> createState() => _SocialPostCardState();
}

class _SocialPostCardState extends ConsumerState<SocialPostCard> with SingleTickerProviderStateMixin {
  bool _liked = false;
  bool _showBurst = false;
  late AnimationController _burstController;
  late Animation<double> _burstAnimation;

  @override
  void initState() {
    super.initState();
    _burstController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _burstAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _burstController, curve: Curves.elasticOut));
    _loadLikeState();
  }

  Future<void> _loadLikeState() async {
    final liked = await ref.read(socialServiceProvider).hasLiked(widget.post.id);
    if (mounted) setState(() => _liked = liked);
  }

  Future<void> _handleDoubleTapLike() async {
    if (_liked) {
      _triggerBurst();
      return;
    }
    HapticFeedback.mediumImpact();
    _triggerBurst();
    final service = ref.read(socialServiceProvider);
    final nowLiked = await service.toggleLike(widget.post.id);
    if (mounted) setState(() => _liked = nowLiked);
  }

  void _triggerBurst() {
    setState(() => _showBurst = true);
    _burstController.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showBurst = false);
    });
  }

  @override
  void dispose() {
    _burstController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final socialService = ref.read(socialServiceProvider);
    final isOwner = socialService.isPostOwner(widget.post);
    return Container(
      margin: const EdgeInsets.only(bottom: 25),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Theme.of(context).shadowColor.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/profile-by-id/${widget.post.userId}'),
                    child: Row(
                      children: [
                        widget.post.userAvatar != null && widget.post.userAvatar!.isNotEmpty
                            ? ClipOval(child: CachedNetworkImage(imageUrl: widget.post.userAvatar!, width: 40, height: 40, memCacheWidth: 80, memCacheHeight: 80, fit: BoxFit.cover, placeholder: (_, __) => CircleAvatar(radius: 20, backgroundColor: Colors.grey[200]), errorWidget: (_, __, ___) => CircleAvatar(radius: 20, backgroundColor: Colors.grey[300], child: Text((widget.post.userName != null && widget.post.userName!.trim().isNotEmpty) ? widget.post.userName!.trim()[0].toUpperCase() : 'M', style: const TextStyle(fontWeight: FontWeight.bold)))))
                            : CircleAvatar(
                                radius: 20,
                                child: Text(
                                  (widget.post.userName != null && widget.post.userName!.trim().isNotEmpty) ? widget.post.userName!.trim()[0].toUpperCase() : 'M',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.post.userName ?? "User", style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                widget.formatTimeAgo(widget.post.createdAt),
                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(LucideIcons.moreHorizontal, color: Colors.grey),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (value) async {
                    if (value == 'edit') {
                      final controller = TextEditingController(text: widget.post.content ?? '');
                      final newContent = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Edit Post'),
                          content: TextField(
                            controller: controller,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              hintText: 'Edit your widget.post...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      );
                      if (newContent != null && newContent.isNotEmpty && context.mounted) {
                        try {
                          await socialService.updatePost(widget.post.id, content: newContent);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Post updated'), backgroundColor: Colors.green),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      }
                    } else if (value == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Post?'),
                          content: const Text('This action cannot be undone.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: FilledButton.styleFrom(backgroundColor: Colors.red),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && context.mounted) {
                        try {
                          await socialService.deletePost(widget.post.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Post deleted'), backgroundColor: Colors.red),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      }
                    } else if (value == 'report') {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Post reported. Thank you for your feedback.'), backgroundColor: Colors.orange),
                        );
                      }
                    } else if (value == 'share') {
                      widget.onShareTap?.call();
                    }
                  },
                  itemBuilder: (ctx) => [
                    if (isOwner) ...[
                      const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(LucideIcons.pencil), title: Text('Edit'), dense: true)),
                      const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(LucideIcons.trash2, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)), dense: true)),
                    ],
                    const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(LucideIcons.share2), title: Text('Share'), dense: true)),
                    if (!isOwner)
                      const PopupMenuItem(value: 'report', child: ListTile(leading: Icon(LucideIcons.flag), title: Text('Report'), dense: true)),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onDoubleTap: _handleDoubleTapLike,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (widget.post.images.isNotEmpty)
                  PostImageCarousel(images: widget.post.images)
                else if (widget.post.mediaUrl != null && widget.post.mediaType == 'image')
                  PostImageCarousel(images: [widget.post.mediaUrl!]),
                if (_showBurst)
                  ScaleTransition(
                    scale: _burstAnimation,
                    child: const Icon(Icons.favorite, size: 80, color: Colors.white),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.post.content != null && widget.post.content!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(widget.post.content!, style: const TextStyle(fontSize: 14)),
                  ),
                SocialPostActions(post: widget.post, onCommentTap: widget.onCommentTap, onShareTap: widget.onShareTap),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SocialPostActions extends ConsumerStatefulWidget {
  final SocialPost post;
  final VoidCallback? onCommentTap;
  final VoidCallback? onShareTap;
  const SocialPostActions({super.key, required this.post, this.onCommentTap, this.onShareTap});

  @override
  ConsumerState<SocialPostActions> createState() => _SocialPostActionsState();
}

class _SocialPostActionsState extends ConsumerState<SocialPostActions> {
  late int _likeCount;
  bool _liked = false;
  bool _likeLoading = false;
  bool _saved = false;
  bool _saveLoading = false;
  late int _commentsCount;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likesCount;
    _commentsCount = widget.post.commentsCount;
    _loadLikeState();
    _loadSaveState();
  }

  Future<void> _loadLikeState() async {
    final service = ref.read(socialServiceProvider);
    final liked = await service.hasLiked(widget.post.id);
    if (mounted) setState(() => _liked = liked);
  }

  Future<void> _loadSaveState() async {
    final service = ref.read(socialServiceProvider);
    final saved = await service.isSaved(widget.post.id);
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _handleSave() async {
    if (_saveLoading) return;
    setState(() => _saveLoading = true);
    try {
      final service = ref.read(socialServiceProvider);
      final nowSaved = await service.toggleSave(widget.post.id);
      if (mounted) {
        setState(() => _saved = nowSaved);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nowSaved ? "Post saved!" : "Post unsaved!"),
            backgroundColor: nowSaved ? Theme.of(context).primaryColor : Colors.grey,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saveLoading = false);
    }
  }

  Future<void> _handleLike() async {
    if (_likeLoading) return;
    setState(() => _likeLoading = true);
    try {
      final service = ref.read(socialServiceProvider);
      final nowLiked = await service.toggleLike(widget.post.id);
      if (mounted) {
        setState(() {
          _liked = nowLiked;
          _likeCount = (_likeCount + (nowLiked ? 1 : -1)).clamp(0, 999999);
        });
      }
    } finally {
      if (mounted) setState(() => _likeLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: _handleLike,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: _liked ? 1 : 0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(scale: 0.7 + value * 0.3, child: child);
              },
              child: Icon(
                LucideIcons.heart,
                size: 24,
                color: _liked ? Colors.red : Colors.grey,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text("$_likeCount", style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: widget.onCommentTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(LucideIcons.messageCircle, size: 24, color: Colors.grey),
                const SizedBox(width: 6),
                Text("$_commentsCount", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: widget.onShareTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: const Icon(LucideIcons.send, size: 24, color: Colors.grey),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: _handleSave,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Icon(
              LucideIcons.bookmark,
              size: 24,
              color: _saved ? Colors.amber : Colors.grey,
            ),
          ),
        ),
      ],
    );
  }
}
