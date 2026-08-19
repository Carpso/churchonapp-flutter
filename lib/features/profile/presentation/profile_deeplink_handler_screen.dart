import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/providers/profile_provider.dart';
import '../../connect/data/social_service.dart';
import '../../connect/presentation/widgets/social_post_card.dart';
import 'profile_screen.dart';

class ProfileDeepLinkHandlerScreen extends ConsumerWidget {
  final String userId;
  const ProfileDeepLinkHandlerScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(profileProvider).value;
    if (current != null && current.id == userId) {
      return const ProfileScreen();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text('Member Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ref.watch(_publicProfileProvider(userId)).when(
            data: (data) => _buildProfile(context, data),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _buildError(context, e.toString()),
          ),
    );
  }

  Widget _buildProfile(BuildContext context, Map<String, dynamic>? data) {
    if (data == null) return _buildError(context, 'User not found.');

    final name = (data['full_name'] as String?)?.trim().isNotEmpty == true
        ? data['full_name'] as String
        : 'Believer';
    final avatar = data['avatar_url'] as String? ?? '';
    final role = (data['role'] as String? ?? 'member').toUpperCase();
    final churchName = data['tenant_name'] as String? ?? '';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 20),
        Center(
          child: CircleAvatar(
            radius: 48,
            backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
            child: avatar.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            role,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
          ),
        ),
        if (churchName.isNotEmpty) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              churchName,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
        ],
        const SizedBox(height: 32),
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _stat(context, 'Coins', (data['coins'] ?? 0).toString()),
                const SizedBox(width: 12),
                _stat(context, 'Level', (data['level'] ?? 'Beginner').toString()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildPostsSection(context, data['id']?.toString() ?? ''),
        const SizedBox(height: 24),
        if (current != null && current.id == data['id']) ...[
          const Center(
            child: Text(
              'Tap below to view your own profile',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
              },
              icon: const Icon(Icons.person),
              label: const Text('My Profile'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPostsSection(BuildContext context, String userId) {
    final postsAsync = ref.watch(_memberPostsProvider(userId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('POSTS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 16),
        postsAsync.when(
          data: (posts) {
            if (posts.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(LucideIcons.messageSquareText, size: 32, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'No posts yet. Share what God is doing in your life on the Connect tab!',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: posts.map((post) {
                return SocialPostCard(
                  post: post,
                  formatTimeAgo: (time) {
                    final diff = DateTime.now().difference(time);
                    if (diff.inMinutes < 1) return 'Just now';
                    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
                    if (diff.inDays < 1) return '${diff.inHours}h ago';
                    if (diff.inDays < 7) return '${diff.inDays}d ago';
                    return '${time.day}/${time.month}/${time.year}';
                  },
                );
              }).toList(),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Text(
                'Could not load posts',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}

final _publicProfileProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) async {
  if (userId.isEmpty) return null;
  final client = Supabase.instance.client;
  final profile = await client
      .from('profiles')
      .select('id, full_name, avatar_url, role, coins, level, tenant_id')
      .eq('id', userId)
      .maybeSingle();
  if (profile == null) return null;

  final tenantId = profile['tenant_id'];
  String? tenantName;
  if (tenantId != null) {
    try {
      final tenant = await client.from('tenants').select('name').eq('id', tenantId).maybeSingle();
      tenantName = tenant?['name'] as String?;
    } catch (_) {
      // tenant_id may be text or the tenant may not exist
    }
  }

  return {...profile, 'tenant_name': tenantName};
});

final _memberPostsProvider = FutureProvider.family<List<SocialPost>, String>((ref, userId) async {
  if (userId.isEmpty) return const [];
  return ref.read(socialServiceProvider).fetchUserPosts(userId);
});
