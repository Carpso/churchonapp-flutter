import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/social_service.dart';
import 'kingdom_klips_screen.dart';
import 'communities_screen.dart';
import 'create_social_post_screen.dart';
import '../../modules/games/presentation/game_hub_screen.dart';
import '../../../core/utils/connectivity_util.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
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
              indicatorColor: Colors.amber,
              dividerColor: Colors.transparent,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
              tabs: const [
                Tab(text: "KINGDOM KLIPS"),
                Tab(text: "COMMUNITIES"),
                Tab(text: "CHURCH SOCIAL"),
                Tab(text: "KINGDOM GAMES"),
              ],
            ),
          ),
        ),
        body: Stack(
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
          _buildStoryBar(),
          Expanded(
            child: Consumer(
              builder: (context, ref, child) {
                final postsAsync = ref.watch(socialPostsProvider);

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(socialPostsProvider);
                  },
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildChurchSocialHeader(ref),
                      const SizedBox(height: 20),
                      postsAsync.when(
                        data: (posts) => posts.isEmpty 
                          ? _buildEmptySocialState()
                          : Column(children: posts.map((p) => _buildRealSocialPost(p)).toList()),
                        loading: () => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(color: Colors.amber),
                          ),
                        ),
                        error: (e, s) => _buildSocialErrorState(e.toString()),
                      ),
                    ],
                  ),
                );
              }
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryBar() {
    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        itemCount: 8, // Mock count
        itemBuilder: (context, index) {
          final isMe = index == 0;
          return Padding(
            padding: const EdgeInsets.only(right: 15),
            child: GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const KingdomKlipsScreen()));
              },
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFFD700), // Sunflower Yellow
                        width: 2.5,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 30,
                      backgroundImage: NetworkImage("https://i.pravatar.cc/150?img=${index + 10}"),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    isMe ? "Your Klip" : "Member ${index + 1}",
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );
        },
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

  Widget _buildRealSocialPost(SocialPost post) {
    return Container(
      margin: const EdgeInsets.only(bottom: 25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20, 
                  backgroundImage: post.userAvatar != null 
                    ? NetworkImage(post.userAvatar!) 
                    : null,
                  child: post.userAvatar == null
                    ? Text(
                        (post.userName ?? 'M')[0].toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      )
                    : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post.userName ?? "Member", style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        _formatTimeAgo(post.createdAt),
                        style: const TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const Icon(LucideIcons.moreHorizontal),
              ],
            ),
          ),
          if (post.images.isNotEmpty)
            SizedBox(
              height: 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: post.images.length,
                itemBuilder: (context, index) => Container(
                  width: MediaQuery.of(context).size.width - 30,
                  margin: const EdgeInsets.only(right: 4),
                  child: Image.network(
                    post.images[index], 
                    width: double.infinity, 
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey[200],
                      child: const Center(child: Icon(LucideIcons.imageOff, size: 40, color: Colors.grey)),
                    ),
                  ),
                ),
              ),
            )
          else if (post.mediaUrl != null && post.mediaType == 'image')
            SizedBox(
              height: 250,
              child: Image.network(
                post.mediaUrl!, 
                width: double.infinity, 
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey[200],
                  child: const Center(child: Icon(LucideIcons.imageOff, size: 40, color: Colors.grey)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SocialPostActions(post: post),
                const SizedBox(height: 10),
                if (post.content != null && post.content!.isNotEmpty)
                  Text(post.content!, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
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
}

/// Stateful widget per post for independent like/comment state management
class _SocialPostActions extends ConsumerStatefulWidget {
  final SocialPost post;
  const _SocialPostActions({required this.post});

  @override
  ConsumerState<_SocialPostActions> createState() => _SocialPostActionsState();
}

class _SocialPostActionsState extends ConsumerState<_SocialPostActions> {
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

  void _showCommentsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(
        postId: widget.post.id,
        onCommentAdded: () {
          setState(() {
            _commentsCount = (_commentsCount + 1).clamp(0, 999999);
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: _handleLike,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _liked ? LucideIcons.heart : LucideIcons.heart,
              key: ValueKey(_liked),
              size: 24,
              color: _liked ? Colors.red : Colors.grey,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text("$_likeCount", style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: _showCommentsSheet,
          child: Row(
            children: [
              const Icon(LucideIcons.messageCircle, size: 24, color: Colors.grey),
              const SizedBox(width: 6),
              Text("$_commentsCount", style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: "https://churchonapp.com/posts/${widget.post.id}"));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Post link copied to clipboard!"), backgroundColor: Colors.green),
            );
          },
          child: const Icon(LucideIcons.send, size: 24, color: Colors.grey),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () {
            setState(() {
              _saved = !_saved;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_saved ? "Post saved to bookmarks!" : "Post removed from bookmarks!"),
                backgroundColor: _saved ? Colors.indigo : Colors.grey,
              ),
            );
          },
          child: Icon(
            _saved ? LucideIcons.bookmark : LucideIcons.bookmark,
            size: 24,
            color: _saved ? Colors.amber : Colors.grey,
          ),
        ),
      ],
    );
  }
}

/// Comments bottom sheet with live loading and add-comment input
class _CommentsSheet extends ConsumerStatefulWidget {
  final String postId;
  final VoidCallback? onCommentAdded;
  const _CommentsSheet({required this.postId, this.onCommentAdded});

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
      if (widget.onCommentAdded != null) {
        widget.onCommentAdded!();
      }
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
                ? const Center(child: CircularProgressIndicator(color: Colors.amber))
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
                                CircleAvatar(
                                  radius: 18,
                                  backgroundImage: c.userAvatar != null ? NetworkImage(c.userAvatar!) : null,
                                  child: c.userAvatar == null ? Text((c.userName ?? 'M')[0]) : null,
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

