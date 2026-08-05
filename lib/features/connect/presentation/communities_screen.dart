import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import '../data/chat_service.dart';
import '../data/community_service.dart';
import 'chat_messenger_screen.dart';
import 'group_details_screen.dart';
import '../../modules/media/presentation/events_list_screen.dart';
import '../../../core/widgets/shimmer_loader.dart';

class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  ConsumerState<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen> {
  List<Map<String, dynamic>> _churchMembers = [];
  bool _loadingMembers = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _loadingMembers = true);
    final profile = ref.read(profileProvider).value;
    final members = await ref.read(chatServiceProvider).fetchChurchMembers(
      limit: 30,
      tenantId: profile?.tenantId,
    );
    if (mounted) {
      setState(() {
        _churchMembers = members;
        _loadingMembers = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(communityGroupsProvider);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 25),
                  _buildEventGateway(context),
                  const SizedBox(height: 30),
                  _buildSectionLabel('CHURCH GROUPS'),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Church Groups — from real Supabase data
          groupsAsync.when(
            data: (groups) {
              if (groups.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(LucideIcons.users, size: 48, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('No groups available yet', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: _buildGroupTile(context, groups[index]),
                  ),
                  childCount: groups.length,
                ),
              );
            },
            loading: () => SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, __) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _buildGroupShimmer(),
                ),
                childCount: 4,
              ),
            ),
            error: (e, s) => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('Failed to load groups')),
              ),
            ),
          ),

          // Direct Messages section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: _buildSectionLabel('DIRECT MESSAGES — CHURCH MEMBERS'),
            ),
          ),

          if (_loadingMembers)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(color: Color(0xFF1A1A1A)),
                ),
              ),
            )
          else if (_churchMembers.isEmpty)
            SliverToBoxAdapter(child: _buildEmptyMembers())
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final member = _churchMembers[index];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: _buildMemberTile(context, member),
                  );
                },
                childCount: _churchMembers.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A1A).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.users, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Communities',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                SizedBox(height: 4),
                Text('Real-time collaboration across the community.',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventGateway(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const EventsListScreen())),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
              child: const Icon(LucideIcons.ticket, color: Colors.black, size: 22),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Multi-Church Ticketing',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('Secure your spot for conferences & worship nights.',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            const Icon(LucideIcons.arrowRight, color: Colors.amber),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupShimmer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          const ShimmerLoader.rectangular(width: 56, height: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerLoader.rectangular(width: 120, height: 14),
                const SizedBox(height: 8),
                ShimmerLoader.rectangular(width: 180, height: 10),
                const SizedBox(height: 8),
                ShimmerLoader.rectangular(width: 80, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupTile(BuildContext context, Map<String, dynamic> group) {
    final title = group['title'] as String? ?? '';
    final subtitle = group['subtitle'] as String? ?? '';
    final imageUrl = group['image'] as String? ?? '';
    final memberCount = group['count'] as int? ?? 0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupDetailsScreen(group: group),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            // Group image — CachedNetworkImage
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: 56,
                height: 56,
                memCacheWidth: 112,
                memCacheHeight: 112,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 56,
                  height: 56,
                  color: Colors.grey[200],
                  child: const Icon(LucideIcons.users, color: Colors.grey, size: 24),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 56,
                  height: 56,
                  color: Colors.grey[200],
                  child: const Icon(LucideIcons.users, color: Colors.grey, size: 24),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(LucideIcons.users, size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        '$memberCount members',
                        style: const TextStyle(
                            color: Color(0xFF1A1A1A), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberTile(BuildContext context, Map<String, dynamic> member) {
    final name = member['full_name'] as String? ?? member['username'] as String? ?? 'User';
    final id = member['id'] as String? ?? '';
    final avatar = member['avatar_url'] as String?;
    final role = member['role'] as String? ?? 'member';

    return GestureDetector(
      onTap: () => context.push('/profile-by-id/$id'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8),
          ],
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF1A1A1A),
                  backgroundImage: avatar != null && avatar.isNotEmpty
                      ? CachedNetworkImageProvider(avatar)
                      : null,
                  child: avatar == null || avatar.isEmpty
                      ? Text(
                          (name.isNotEmpty ? name[0] : 'M').toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(
                    _formatRole(role),
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                _buildQuickAction(LucideIcons.phone, const Color(0xFF1A1A1A), () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatMessengerScreen(
                        userName: name,
                        userAvatar: avatar ?? '',
                        receiverId: id,
                      ),
                    ),
                  );
                }),
                const SizedBox(width: 8),
                _buildQuickAction(LucideIcons.messageSquare, Colors.amber, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatMessengerScreen(
                        userName: name,
                        userAvatar: avatar ?? '',
                        receiverId: id,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  Widget _buildEmptyMembers() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(LucideIcons.users, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            const Text('No church members found yet', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Refresh'),
              onPressed: _loadMembers,
            ),
          ],
        ),
      ),
    );
  }

  String _formatRole(String role) {
    switch (role) {
      case 'pastor': return 'Pastor';
      case 'admin': return 'Admin';
      case 'leader': return 'Leader';
      case 'worship': return 'Worship Team';
      default: return 'Church Member';
    }
  }
}
