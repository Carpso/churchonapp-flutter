import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../data/social_service.dart';
import 'widgets/social_post_card.dart';
import 'kingdom_klips_screen.dart';
import 'community_hub_screen.dart';
import 'create_social_post_screen.dart';
import 'interchurch_network_screen.dart';
import 'network_activity_screen.dart';
import 'pastors_corner_screen.dart';
import 'package:church_on_app/features/modules/bible_quiz/presentation/bible_quiz_hub_screen.dart';
import '../../../core/utils/connectivity_util.dart';
import 'package:church_on_app/features/navigation/presentation/main_navigation_shell.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: 0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final fab = FloatingActionButton(
      heroTag: null,
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateSocialPostScreen())),
      backgroundColor: Theme.of(context).primaryColor,
      child: Icon(LucideIcons.plus, color: Theme.of(context).colorScheme.onPrimary),
    );
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(88),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, bottom: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: false,
            indicatorSize: TabBarIndicatorSize.label,
            indicatorColor: Theme.of(context).primaryColor,
            dividerColor: Colors.transparent,
            labelColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            tabs: [
              Tab(icon: Icon(LucideIcons.rss, size: 20), text: "Feed"),
              Tab(icon: Icon(LucideIcons.users, size: 20), text: "Communities"),
              Tab(icon: Icon(LucideIcons.video, size: 20), text: "Klips"),
              Tab(icon: Icon(LucideIcons.trophy, size: 20), text: "Quiz"),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(socialPostsProvider);
        },
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  TabBarView(
                    controller: _tabController,
                    children: [
                      _buildChurchSocial(),
                      const CommunityHubScreen(),
                      const KingdomKlipsScreen(),
                      const BibleQuizHubScreen(),
                    ],
                  ),
                  const Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: OfflineBanner(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: fab,
    );
  }

  Widget _buildChurchSocial() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Expanded(
            child: Consumer(
              builder: (context, ref, child) {
                final postsAsync = ref.watch(socialPostsProvider);
                final socialItems = <Widget>[
                  _buildChurchSocialHeader(ref),
                  const SizedBox(height: 20),
                  postsAsync.when(
                      data: (posts) => posts.isEmpty 
                      ? _buildEmptySocialState()
                      : Column(children: posts.map((p) => SocialPostCard(
                        post: p,
                        formatTimeAgo: _formatTimeAgo,
                        onCommentTap: () => _showCommentsSheet(context, p.id, ref),
                        onShareTap: () => _sharePost(p.id),
                      )).toList()),
                    loading: () => Column(
                      children: List.generate(3, (_) => Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _buildPostShimmer(),
                      )),
                    ),
                    error: (e, s) => _buildSocialErrorState(e.toString()),
                  ),
                ];

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(socialPostsProvider);
                  },
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollUpdateNotification && notification.dragDetails != null) {
                        final delta = notification.scrollDelta ?? 0;
                        if (delta > 0) {
                          ref.read(navBarVisibleProvider.notifier).hide();
                        } else if (delta < 0) {
                          ref.read(navBarVisibleProvider.notifier).show();
                        }
                      }
                      return false;
                    },
                    child: ListView.builder(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom + 90),
                      itemCount: socialItems.length,
                      itemBuilder: (context, index) => socialItems[index],
                    ),
                  ),
                );
              }
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostShimmer() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ShimmerLoader.rectangular(width: 40, height: 40),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerLoader.rectangular(width: 100, height: 14),
                  const SizedBox(height: 4),
                  ShimmerLoader.rectangular(width: 60, height: 10),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const ShimmerLoader.rectangular(height: 200),
          const SizedBox(height: 12),
          Row(
            children: [
              ShimmerLoader.rectangular(width: 24, height: 24),
              const SizedBox(width: 20),
              ShimmerLoader.rectangular(width: 24, height: 24),
              const SizedBox(width: 20),
              ShimmerLoader.rectangular(width: 24, height: 24),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSocialErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(LucideIcons.wifiOff, size: 50, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2)),
            const SizedBox(height: 10),
            Text("Could not load posts", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(error, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 15),
            TextButton.icon(
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text("Retry"),
              onPressed: () => ref.invalidate(socialPostsProvider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySocialState() {
     return Center(
      child: Column(
        children: [
          Icon(LucideIcons.messageSquare, size: 50, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 10),
          Text("No posts in the community yet.", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
          const SizedBox(height: 10),
          Text("Be the first to share!", style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  Widget _buildChurchSocialHeader(WidgetRef ref) {
    final currentFilter = ref.watch(socialFilterProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text("Church Social", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: Icon(LucideIcons.plusSquare, color: Theme.of(context).primaryColor),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateSocialPostScreen()));
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildComposerBar(),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildFilterChip(ref, "All", SocialFeedFilter.all, currentFilter),
            const SizedBox(width: 8),
            _buildFilterChip(ref, "My Church", SocialFeedFilter.church, currentFilter),
            const SizedBox(width: 8),
            _buildFilterChip(ref, "Friends", SocialFeedFilter.friends, currentFilter),
            const Spacer(),
            IconButton(
              tooltip: "Interchurch Network",
              icon: const Icon(LucideIcons.network, size: 20),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const InterchurchNetworkScreen()));
              },
            ),
            IconButton(
              tooltip: "Network Activity",
              icon: const Icon(LucideIcons.activity, size: 20),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const NetworkActivityScreen()));
              },
            ),
            IconButton(
              tooltip: "Pastors Corner",
              icon: const Icon(LucideIcons.mic2, size: 20),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PastorsCornerScreen()));
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildComposerBar() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(LucideIcons.user, size: 18, color: Theme.of(context).primaryColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateSocialPostScreen()));
            },
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                "Share a testimony, prayer or update...",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateSocialPostScreen()));
          },
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(LucideIcons.camera, size: 18, color: Theme.of(context).colorScheme.onPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(WidgetRef ref, String label, SocialFeedFilter filterValue, SocialFeedFilter currentFilter) {
    final isSelected = currentFilter == filterValue;
    return GestureDetector(
      onTap: () {
        ref.read(socialFilterProvider.notifier).setFilter(filterValue);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Theme.of(context).primaryColor : Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  void _showCommentsSheet(BuildContext context, String postId, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsSheet(postId: postId),
    );
  }

  void _sharePost(String postId) {
    Clipboard.setData(ClipboardData(text: "https://churchonapp.com/posts/$postId"));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Post link copied to clipboard!"), backgroundColor: Colors.green),
    );
  }
}

class CommentsSheet extends ConsumerStatefulWidget {
  final String postId;
  const CommentsSheet({super.key, required this.postId});

  @override
  ConsumerState<CommentsSheet> createState() => CommentsSheetState();
}

class CommentsSheetState extends ConsumerState<CommentsSheet> {
  final _commentCtrl = TextEditingController();
  List<SocialComment> _comments = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    final service = ref.read(socialServiceProvider);
    final comments = await service.fetchComments(widget.postId);
    if (mounted) setState(() { _comments = comments; _loading = false; });
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final service = ref.read(socialServiceProvider);
      await service.addComment(widget.postId, text);
      _commentCtrl.clear();
      await _loadComments();

    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text("Comments", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const Divider(height: 20),
          Expanded(
            child: _loading
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(3, (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const ShimmerLoader.circular(width: 36, height: 36),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ShimmerLoader.rectangular(width: 60.0 + i * 20, height: 12),
                                    const SizedBox(height: 8),
                                    const ShimmerLoader.rectangular(height: 12),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )),
                      ),
                    ),
                  )
                : _comments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.messageCircle, size: 40, color: Colors.grey[300]),
                            const SizedBox(height: 10),
                            const Text("No comments yet. Be the first!", style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _comments.length,
                        itemBuilder: (context, index) {
                          final c = _comments[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                c.userAvatar != null && c.userAvatar!.isNotEmpty
                                    ? ClipOval(child: CachedNetworkImage(imageUrl: c.userAvatar!, width: 36, height: 36, memCacheWidth: 72, memCacheHeight: 72, fit: BoxFit.cover, placeholder: (_, __) => CircleAvatar(radius: 18, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest), errorWidget: (_, __, ___) => CircleAvatar(radius: 18, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest, child: Text((c.userName ?? '').isNotEmpty ? c.userName![0] : 'M'))))
                                    : CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        child: Text((c.userName ?? '').isNotEmpty ? c.userName![0] : 'M'),
                                      ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(c.userName ?? 'User', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
                                        const SizedBox(height: 4),
                                        Text(c.content, style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    decoration: InputDecoration(
                      hintText: "Write a comment...",
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendComment(),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _sendComment,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
                    child: _sending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : Icon(LucideIcons.send, color: Theme.of(context).colorScheme.onPrimary, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
