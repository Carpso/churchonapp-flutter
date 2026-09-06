import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/social_service.dart';
import 'widgets/social_post_card.dart';

class SavedPostsScreen extends ConsumerWidget {
  const SavedPostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text("Saved Posts", style: TextStyle(fontWeight: FontWeight.bold))),
      body: FutureBuilder<List<SocialPost>>(
        future: _fetchSaved(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          final posts = snapshot.data ?? [];
          if (posts.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.bookmark, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                const Text("No saved posts yet", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text("Tap the bookmark on any post to save it", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ]),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 1),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              final image = post.images.isNotEmpty ? post.images.first : post.mediaUrl;
              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text("Post")), body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: SocialPostCard(post: post, formatTimeAgo: (_) => ""))))),
                child: Container(
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                  clipBehavior: Clip.antiAlias,
                  child: image != null && image.isNotEmpty
                      ? Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(LucideIcons.image, color: Colors.grey))
                      : const Icon(LucideIcons.fileText, color: Colors.grey),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<SocialPost>> _fetchSaved() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];
    final res = await Supabase.instance.client
        .from('saved_posts')
        .select('post:social_posts(*, profiles(full_name, avatar_url, role))')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    final list = (res as List).map((row) {
      final postMap = row['post'];
      if (postMap is Map<String, dynamic>) return SocialPost.fromMap(postMap);
      return null;
    }).whereType<SocialPost>().toList();
    return list;
  }
}
