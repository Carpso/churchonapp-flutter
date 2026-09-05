import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/app_image.dart';
import '../data/community_service.dart';
import 'chat_messenger_screen.dart';

class GroupDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> group;

  const GroupDetailsScreen({super.key, required this.group});

  @override
  ConsumerState<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends ConsumerState<GroupDetailsScreen> {
  bool _isMember = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkMembership();
  }

  Future<void> _checkMembership() async {
    final groupId = widget.group['id'] as String? ?? widget.group['groupId'] as String? ?? '';
    if (groupId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final service = ref.read(communityServiceProvider);
    final member = await service.isMember(groupId);
    if (mounted) setState(() { _isMember = member; _loading = false; });
  }

  Future<void> _toggleMembership() async {
    final groupId = widget.group['id'] as String? ?? widget.group['groupId'] as String? ?? '';
    if (groupId.isEmpty) return;
    final service = ref.read(communityServiceProvider);
    if (_isMember) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Leave "${widget.group['title'] ?? 'Group'}"?'),
          content: const Text('Are you sure you want to leave this group? You will stop receiving messages from it.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final ok = await service.leaveGroup(groupId);
      if (ok && mounted) {
        setState(() => _isMember = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You left the group'), backgroundColor: Colors.orange),
        );
      }
    } else {
      final ok = await service.joinGroup(groupId);
      if (ok && mounted) setState(() => _isMember = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberCount = widget.group['count'] as int? ?? 0;
    final groupId = widget.group['id'] as String? ?? widget.group['groupId'] as String? ?? '';
    final groupTitle = widget.group['title'] as String? ?? 'Community';
    final groupSubtitle = widget.group['subtitle'] as String? ?? '';
    final groupImage = widget.group['image'] as String? ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  AppImage(groupImage, fit: BoxFit.cover),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(groupTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(LucideIcons.users, color: Colors.white70, size: 16),
                            const SizedBox(width: 6),
                            Text("$memberCount members", style: const TextStyle(color: Colors.white70, fontSize: 14)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("About", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text(groupSubtitle, style: TextStyle(fontSize: 15, height: 1.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75))),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      const Text("Group Members", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text("$memberCount total", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 15),
                ],
              ),
            ),
          ),
          _MembersList(groupId: groupId),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: Row(
          children: [
            if (!_loading)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _toggleMembership,
                  icon: Icon(_isMember ? LucideIcons.userMinus : LucideIcons.userPlus, size: 18),
                  label: Text(_isMember ? "LEAVE GROUP" : "JOIN GROUP"),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
            if (!_loading) const SizedBox(width: 15),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ChatMessengerScreen(
                      userName: groupTitle,
                      userAvatar: groupImage,
                      groupId: groupId,
                      isGroup: true,
                    ),
                  ));
                },
                icon: const Icon(LucideIcons.send, size: 18, color: Colors.white),
                label: const Text("OPEN CHAT"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MembersList extends ConsumerWidget {
  final String groupId;

  const _MembersList({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(_groupMembersProvider(groupId));

    return membersAsync.when(
      data: (members) {
        if (members.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: Text("No members yet", style: TextStyle(color: Colors.grey))),
            ),
          );
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final m = members[index];
              final profile = m['profiles'] as Map<String, dynamic>?;
              final avatarUrl = profile?['avatar_url'] as String? ?? '';
              final name = profile?['full_name'] as String? ?? 'User';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF1A1A1A),
                  backgroundImage: avatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'U',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text("Active in chat", style: TextStyle(color: Colors.grey, fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(LucideIcons.messageCircle, color: Color(0xFF1A1A1A), size: 18),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ChatMessengerScreen(
                        userName: name,
                        userAvatar: avatarUrl,
                        receiverId: m['user_id'] ?? '',
                      ),
                    ));
                  },
                ),
                onTap: () {
                  context.push('/profile-by-id/${m['user_id']}');
                },
              );
            },
            childCount: members.length,
          ),
        );
      },
      loading: () => SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, __) => ListTile(
            leading: CircleAvatar(backgroundColor: Colors.grey[200]),
            title: Container(height: 14, width: 100, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4))),
            subtitle: Container(height: 10, width: 80, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4))),
          ),
          childCount: 4,
        ),
      ),
      error: (e, _) => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: Text("Failed to load members", style: TextStyle(color: Colors.grey))),
        ),
      ),
    );
  }
}

final _groupMembersProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, groupId) async {
  final client = Supabase.instance.client;
  try {
    // community_group_members.user_id FKs to auth.users (not profiles.id), so
    // PostgREST cannot embed profiles directly. Fetch memberships, then a
    // separate profiles query, and shape as {user_id, profiles: {...}} to keep
    // the UI unchanged.
    final memberships = List<Map<String, dynamic>>.from(await client
        .from('community_group_members')
        .select('user_id')
        .eq('group_id', groupId)
        .limit(50));
    final userIds = memberships.map((m) => m['user_id']?.toString()).whereType<String>().toSet().toList();
    Map<String, Map<String, dynamic>> profileMap = {};
    if (userIds.isNotEmpty) {
      try {
        final res = await client
            .from('profiles')
            .select('id, full_name, avatar_url')
            .inFilter('id', userIds);
        for (final row in (res as List)) {
          profileMap[row['id']?.toString() ?? ''] = Map<String, dynamic>.from(row);
        }
      } catch (_) {}
    }
    return memberships.map((m) {
      final uid = m['user_id']?.toString() ?? '';
      return {
        'user_id': uid,
        'profiles': profileMap[uid],
      };
    }).toList();
  } catch (e) {
    debugPrint('Failed to load group members: $e');
    return [];
  }
});
