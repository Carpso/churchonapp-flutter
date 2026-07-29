import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/social_service.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  Map<String, dynamic>? _post;
  bool _isLoading = true;
  int _likesCount = 0;
  bool _isLiked = false;

  @override
  void initState() {
    super.initState();
    _fetchPost();
  }

  Future<void> _fetchPost() async {
    try {
      final data = await Supabase.instance.client
          .from('social_posts')
          .select('*, profiles(full_name, avatar_url)')
          .eq('id', widget.postId)
          .maybeSingle();
      if (data != null) {
        setState(() {
          _post = data;
          _likesCount = data['likes_count'] ?? 0;
        });
        _checkLiked();
      }
    } catch (e) {
      debugPrint('Failed to fetch post: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _checkLiked() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final res = await Supabase.instance.client
          .from('social_likes')
          .select('id')
          .eq('post_id', widget.postId)
          .eq('user_id', user.id)
          .maybeSingle();
      if (mounted) setState(() => _isLiked = res != null);
    } catch (e) {
      debugPrint('Failed to check like status: $e');
    }
  }

  Future<void> _toggleLike() async {
    final liked = await ref.read(socialServiceProvider).toggleLike(widget.postId);
    setState(() {
      _isLiked = liked;
      _likesCount += liked ? 1 : -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(title: const Text("Post")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : _post == null
              ? const Center(child: Text("Post not found"))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundImage: _post!['profiles'] is Map
                                ? CachedNetworkImageProvider((_post!['profiles'] as Map)['avatar_url'] ?? '')
                                : null,
                            radius: 22,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _post!['profiles'] is Map
                                    ? ((_post!['profiles'] as Map)['full_name'] ?? 'Member')
                                    : 'Member',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Text(
                                _post!['created_at'] != null
                                    ? _timeAgo(_post!['created_at'])
                                    : '',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_post!['content'] != null && (_post!['content'] as String).isNotEmpty)
                        Text(_post!['content'], style: const TextStyle(fontSize: 16, height: 1.5)),
                      if (_post!['media_url'] != null || (_post!['images'] as List?)?.isNotEmpty == true) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: CachedNetworkImage(
                            imageUrl: (_post!['images'] as List?)?.isNotEmpty == true
                                ? (_post!['images'] as List).first
                                : _post!['media_url'],
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 300,
                            memCacheWidth: 540,
                            memCacheHeight: 300,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _isLiked ? LucideIcons.heart : LucideIcons.heart,
                              color: _isLiked ? Colors.red : Colors.grey,
                              fill: _isLiked ? 1 : 0,
                            ),
                            onPressed: _toggleLike,
                          ),
                          Text("$_likesCount", style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  String _timeAgo(String createdAt) {
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${diff.inDays ~/ 7}w ago';
  }
}
