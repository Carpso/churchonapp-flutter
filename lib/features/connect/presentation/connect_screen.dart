import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../data/social_service.dart';
import 'widgets/social_post_card.dart';
import 'kingdom_klips_screen.dart';
import 'communities_screen.dart';
import 'create_social_post_screen.dart';
import '../../modules/games/presentation/game_hub_screen.dart';
import '../../../core/utils/connectivity_util.dart';
import 'package:church_on_app/features/navigation/presentation/main_navigation_shell.dart';
import 'package:church_on_app/features/navigation/presentation/carpso_suggestion_card.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  bool _showCarpsoCard() {
    final day = DateTime.now().weekday;
    return day == DateTime.sunday || day == DateTime.wednesday || day == DateTime.friday;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFAEB),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Container(
            padding: const EdgeInsets.only(top: 50, bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
            ),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: Colors.amber,
              dividerColor: Colors.transparent,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
              tabs: const [
                Tab(text: "KLIPS"),
                Tab(text: "COMMUNITIES"),
                Tab(text: "CHURCH SOCIAL"),
                Tab(text: "GAMES"),
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
            if (_showCarpsoCard())
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SizedBox(
                  height: 48,
                  child: CarpsoSuggestionCard(contextType: 'connect'),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  TabBarView(
                    children: [
                      const KingdomKlipsScreen(),
                      const CommunitiesScreen(),
                      _buildChurchSocial(),
                      const KingdomGamesHubScreen(),
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
        floatingActionButton: FloatingActionButton(
          heroTag: null,
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateSocialPostScreen())),
          backgroundColor: Colors.amber,
          child: const Icon(LucideIcons.plus, color: Colors.black),
        ),
      ),
    );
  }

  Widget _buildChurchSocial() {
    return Container(
      color: const Color(0xFFFFFAEB),
      child: Column(
        children: [
          Expanded(
            child: Consumer(
              builder: (context, ref, child) {
                final postsAsync = ref.watch(socialPostsProvider);

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
                    child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
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
                    ],
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
        color: Colors.white,
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
            Icon(LucideIcons.wifiOff, size: 50, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            const Text("Could not load posts", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(error, style: const TextStyle(color: Colors.grey, fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 15),
            TextButton.icon(
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text("Retry"),
              onPressed: () => setState(() {}),
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
          Icon(LucideIcons.messageSquare, size: 50, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          const Text("No posts in the community yet.", style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 10),
          const Text("Be the first to share!", style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
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
              icon: const Icon(LucideIcons.plusSquare, color: Colors.amber),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateSocialPostScreen()));
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildFilterChip(ref, "All", SocialFeedFilter.all, currentFilter),
            const SizedBox(width: 8),
            _buildFilterChip(ref, "My Church", SocialFeedFilter.church, currentFilter),
            const SizedBox(width: 8),
            _buildFilterChip(ref, "Friends", SocialFeedFilter.friends, currentFilter),
          ],
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
          color: isSelected ? Colors.amber : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.amber : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.black : Colors.grey.shade600,
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
      builder: (_) => _CommentsSheet(postId: postId),
    );
  }

  void _sharePost(String postId) {
    Clipboard.setData(ClipboardData(text: "https://churchonapp.com/posts/$postId"));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Post link copied to clipboard!"), backgroundColor: Colors.green),
    );
  }
}

class _CommentsSheet extends ConsumerStatefulWidget {
  final String postId;
  const _CommentsSheet({required this.postId});

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
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
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
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
                                    ? ClipOval(child: CachedNetworkImage(imageUrl: c.userAvatar!, width: 36, height: 36, memCacheWidth: 72, memCacheHeight: 72, fit: BoxFit.cover, placeholder: (_, __) => CircleAvatar(radius: 18, backgroundColor: Colors.grey[200]), errorWidget: (_, __, ___) => CircleAvatar(radius: 18, backgroundColor: Colors.grey[300], child: Text((c.userName ?? 'M')[0]))))
                                    : CircleAvatar(
                                        radius: 18,
                                        child: Text((c.userName ?? 'M')[0]),
                                      ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(c.userName ?? 'Member', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                        const SizedBox(height: 4),
                                        Text(c.content, style: const TextStyle(fontSize: 14)),
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
                      fillColor: Colors.grey[100],
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
                    decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                    child: _sending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Icon(LucideIcons.send, color: Colors.black, size: 20),
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
