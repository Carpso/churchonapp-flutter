import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/widgets/post_image_carousel.dart';
import '../../data/social_service.dart';

class SocialPostCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                    onTap: () => context.push('/profile-by-id/${post.userId}'),
                    child: Row(
                      children: [
                        post.userAvatar != null && post.userAvatar!.isNotEmpty
                            ? ClipOval(child: CachedNetworkImage(imageUrl: post.userAvatar!, width: 40, height: 40, memCacheWidth: 80, memCacheHeight: 80, fit: BoxFit.cover, placeholder: (_, __) => CircleAvatar(radius: 20, backgroundColor: Colors.grey[200]), errorWidget: (_, __, ___) => CircleAvatar(radius: 20, backgroundColor: Colors.grey[300], child: Text((post.userName != null && post.userName!.trim().isNotEmpty) ? post.userName!.trim()[0].toUpperCase() : 'M', style: const TextStyle(fontWeight: FontWeight.bold)))))
                            : CircleAvatar(
                                radius: 20,
                                child: Text(
                                  (post.userName != null && post.userName!.trim().isNotEmpty) ? post.userName!.trim()[0].toUpperCase() : 'M',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(post.userName ?? "User", style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                formatTimeAgo(post.createdAt),
                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Icon(LucideIcons.moreHorizontal),
              ],
            ),
          ),
          if (post.images.isNotEmpty)
            PostImageCarousel(images: post.images)
          else if (post.mediaUrl != null && post.mediaType == 'image')
            PostImageCarousel(images: [post.mediaUrl!]),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.content != null && post.content!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(post.content!, style: const TextStyle(fontSize: 14)),
                  ),
                SocialPostActions(post: post, onCommentTap: onCommentTap, onShareTap: onShareTap),
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
  late int _commentsCount;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likesCount;
    _commentsCount = widget.post.commentsCount;
    _loadLikeState();
  }

  Future<void> _loadLikeState() async {
    final service = ref.read(socialServiceProvider);
    final liked = await service.hasLiked(widget.post.id);
    if (mounted) setState(() => _liked = liked);
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
          onTap: () {
            setState(() => _saved = !_saved);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_saved ? "Post saved!" : "Post unsaved!"),
                backgroundColor: _saved ? Theme.of(context).primaryColor : Colors.grey,
              ),
            );
          },
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
