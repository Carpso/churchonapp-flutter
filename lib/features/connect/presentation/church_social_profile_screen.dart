import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/social_service.dart';
import 'connect_screen.dart' show CommentsSheet;
import 'widgets/social_post_card.dart';

final churchSocialPostsProvider =
    StreamProvider.autoDispose.family<List<SocialPost>, String>((ref, tenantId) {
  return ref.watch(socialServiceProvider).streamPosts(tenantId: tenantId);
});

final churchSocialTenantProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>(
        (ref, tenantId) async {
  final client = Supabase.instance.client;
  try {
    final tenant = await client
        .from('tenants')
        .select('id, name, logo_url')
        .filter('id::text', 'eq', tenantId)
        .maybeSingle();
    if (tenant == null) return null;
    final count = await client
        .from('profiles')
        .select('id')
        .eq('tenant_id', tenantId);
    final members = (count as List).length;
    return {
      'name': tenant['name'] ?? 'Church',
      'logo_url': tenant['logo_url'] ?? '',
      'members': members,
    };
  } catch (e) {
    debugPrint('church social: tenant fetch error: $e');
    return null;
  }
});

class ChurchSocialProfileScreen extends ConsumerWidget {
  final String tenantId;
  const ChurchSocialProfileScreen({super.key, required this.tenantId});

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  void _sharePost(BuildContext context, String postId) {
    Clipboard.setData(
        ClipboardData(text: "https://churchonapp.com/posts/$postId"));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Post link copied to clipboard!"),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final postsAsync = ref.watch(churchSocialPostsProvider(tenantId));
    final tenantAsync = ref.watch(churchSocialTenantProvider(tenantId));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Church Social"),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(churchSocialPostsProvider(tenantId));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
          children: [
            tenantAsync.when(
              data: (tenant) => _buildTenantHeader(theme, tenant),
              loading: () => Container(
                height: 100,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (_, __) => Container(
                height: 100,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(
                    "Church not found",
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            postsAsync.when(
              data: (posts) {
                if (posts.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Icon(LucideIcons.rss,
                            size: 44,
                            color:
                                theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        Text(
                          "No posts from this church yet",
                          style: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Posts shared by church members will appear here.",
                          style: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: posts
                      .map((p) => SocialPostCard(
                            post: p,
                            formatTimeAgo: _formatTimeAgo,
                            onCommentTap: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => CommentsSheet(postId: p.id),
                            ),
                            onShareTap: () => _sharePost(context, p.id),
                          ))
                      .toList(),
                );
              },
              loading: () => Column(
                children: List.generate(3, (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                )),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(LucideIcons.wifiOff,
                          size: 50,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.2)),
                      const SizedBox(height: 10),
                      Text(
                        "Could not load posts",
                        style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextButton.icon(
                        icon: const Icon(LucideIcons.refreshCw, size: 16),
                        label: const Text("Retry"),
                        onPressed: () => ref
                            .invalidate(churchSocialPostsProvider(tenantId)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTenantHeader(ThemeData theme, Map<String, dynamic>? tenant) {
    final name = tenant?['name']?.toString() ?? 'Church';
    final logo = tenant?['logo_url']?.toString() ?? '';
    final members = (tenant?['members'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.2),
              image: logo.isNotEmpty
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(logo),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: logo.isEmpty
                ? Center(
                    child: Text(
                      name.isNotEmpty ? name.trim()[0].toUpperCase() : 'C',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  "$members members · Community feed",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
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