import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import '../data/chat_service.dart';
import '../data/community_service.dart';
import '../data/presence_service.dart';
import 'chat_messenger_screen.dart';
import 'group_details_screen.dart';
import 'community_forms.dart';
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
  Set<String> _onlineIds = {};
  StreamSubscription<Set<String>>? _presenceSub;

  @override
  void initState() {
    super.initState();
    ref.read(presenceServiceProvider).startHeartbeat();
    _loadMembers();
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    super.dispose();
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
    _watchPresence(members);
  }

  void _watchPresence(List<Map<String, dynamic>> members) {
    _presenceSub?.cancel();
    final ids = members
        .map((m) => m['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    _presenceSub = ref
        .read(presenceServiceProvider)
        .watchOnlineIds(ids)
        .listen((online) {
      if (mounted) setState(() => _onlineIds = online);
    });
  }

  @override
  Widget build(BuildContext context) {
    final communitiesAsync = ref.watch(communitiesStreamProvider);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(communitiesStreamProvider);
          ref.invalidate(communityGroupsProvider);
        },
        child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 25),
                  _buildEventGateway(context),
                  const SizedBox(height: 30),
                  _buildGroupsHeader(context, ref),
                 ],
              ),
            ),
          ),

          // Church Groups — communities with their nested groups.
          communitiesAsync.when(
            data: (communities) {
              if (communities.isEmpty) {
                return SliverToBoxAdapter(child: _buildEmptyGroups(context, ref));
              }
              final widgets = <Widget>[];
              for (final c in communities) {
                widgets.add(_buildCommunityHeader(context, ref, c));
                final groups = ((c['groups'] as List?) ?? const [])
                    .cast<Map<String, dynamic>>();
                if (groups.isEmpty) {
                  widgets.add(_buildEmptyGroupRow(context, ref, c));
                } else {
                  for (final g in groups) {
                    widgets.add(Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: _buildGroupTile(context, g),
                    ));
                  }
                }
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => widgets[i],
                  childCount: widgets.length,
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
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildGroupsHeader(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        _buildSectionLabel('CHURCH GROUPS'),
        const Spacer(),
        TextButton.icon(
          onPressed: () => _promptCreate(context, ref),
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('NEW',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Future<void> _promptCreate(BuildContext context, WidgetRef ref) async {
    final choice = await showCreateCommunityMenu(context);
    if (choice == null || !context.mounted) return;
    if (choice == 'community') {
      await showCommunityForm(context, ref);
    } else {
      final communities =
          ref.read(communitiesStreamProvider).value ?? const [];
      if (communities.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Create a community first.')));
        return;
      }
      await showGroupForm(context, ref, communities: communities);
    }
    ref.invalidate(communitiesStreamProvider);
    ref.invalidate(communityGroupsProvider);
  }

  Widget _buildEmptyGroups(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Column(
          children: [
            const Icon(LucideIcons.users, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No communities yet',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _promptCreate(context, ref),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('CREATE COMMUNITY'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyGroupRow(
      BuildContext context, WidgetRef ref, Map<String, dynamic> community) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: OutlinedButton.icon(
        onPressed: () async {
          await showGroupForm(context, ref, communities: [community]);
          ref.invalidate(communitiesStreamProvider);
          ref.invalidate(communityGroupsProvider);
        },
        icon: const Icon(LucideIcons.plus, size: 16),
        label: const Text('ADD A GROUP', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 46)),
      ),
    );
  }

  Widget _buildCommunityHeader(
      BuildContext context, WidgetRef ref, Map<String, dynamic> c) {
    final theme = Theme.of(context);
    final manageable = canManageCommunity(ref, c);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 10),
      child: Row(
        children: [
          Icon(LucideIcons.layoutGrid, size: 16, color: theme.primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((c['name'] ?? 'Community').toString(),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w900)),
                if ((c['description'] ?? '').toString().isNotEmpty)
                  Text(c['description'].toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 11)),
              ],
            ),
          ),
          if (manageable)
            PopupMenuButton<String>(
              icon: Icon(LucideIcons.moreVertical,
                  size: 18, color: Colors.grey.shade500),
              onSelected: (v) => _handleCommunityAction(context, ref, c, v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'add_group', child: Text('Add group')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _handleCommunityAction(BuildContext context, WidgetRef ref,
      Map<String, dynamic> c, String action) async {
    if (action == 'edit') {
      await showCommunityForm(context, ref, existing: c);
    } else if (action == 'add_group') {
      await showGroupForm(context, ref, communities: [c]);
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Delete "${c['name'] ?? 'community'}"?'),
          content: const Text(
              'This also removes its groups. This cannot be undone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCEL')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child:
                    const Text('DELETE', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (ok == true) {
        try {
          await ref
              .read(communityServiceProvider)
              .deleteCommunity(c['id'].toString());
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
          }
        }
      }
    }
    ref.invalidate(communitiesStreamProvider);
    ref.invalidate(communityGroupsProvider);
  }

  Future<void> _handleGroupAction(
      BuildContext context, WidgetRef ref, Map<String, dynamic> g, String action) async {
    if (action == 'edit') {
      await showGroupForm(context, ref, existing: g);
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Delete "${g['title'] ?? 'group'}"?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCEL')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child:
                    const Text('DELETE', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (ok == true) {
        try {
          await ref
              .read(communityServiceProvider)
              .deleteGroup(g['id'].toString());
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
          }
        }
      }
    }
    ref.invalidate(communitiesStreamProvider);
    ref.invalidate(communityGroupsProvider);
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
    final theme = Theme.of(context);
    final hasImage = imageUrl.isNotEmpty;

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
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            // Group image with fallback icon for empty URLs
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: hasImage
                  ? AppImage(
                      imageUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        width: 56, height: 56,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(LucideIcons.users, color: theme.primaryColor, size: 24),
                      ),
                      errorWidget: (context, url) => Container(
                        width: 56, height: 56,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(LucideIcons.users, color: theme.primaryColor, size: 24),
                      ),
                    )
                  : Container(
                      width: 56, height: 56,
                      color: theme.primaryColor.withValues(alpha: 0.12),
                      child: Icon(LucideIcons.users, color: theme.primaryColor, size: 24),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, decoration: TextDecoration.none, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 3),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(LucideIcons.users, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.35)),
                      const SizedBox(width: 4),
                      Text(
                        '$memberCount members',
                        style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (canManageCommunity(ref, group))
              PopupMenuButton<String>(
                icon: Icon(LucideIcons.moreVertical,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    size: 18),
                onSelected: (v) => _handleGroupAction(context, ref, group, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              )
            else
              Icon(LucideIcons.chevronRight, color: theme.colorScheme.onSurface.withValues(alpha: 0.3), size: 18),
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
                  child: avatar != null && avatar.isNotEmpty
                      ? ClipOval(
                          child: AppImage(
                            avatar,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Text(
                          (name.isNotEmpty ? name[0] : 'M').toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _onlineIds.contains(id) ? Colors.green : Colors.grey,
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
                       style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, decoration: TextDecoration.none)),
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
