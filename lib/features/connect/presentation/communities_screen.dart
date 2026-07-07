import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/chat_service.dart';
import 'chat_messenger_screen.dart';
import '../../modules/media/presentation/kingdom_events_screen.dart';

class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  ConsumerState<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen> {
  List<Map<String, dynamic>> _churchMembers = [];
  bool _loadingMembers = true;

  // ── Church groups definition ───────────────────────────────────────────────
  static const List<Map<String, dynamic>> _churchGroups = [
    {
      'title': 'Worship Team',
      'subtitle': 'Internal prep for Sunday missions',
      'image': 'https://images.unsplash.com/photo-1514525253361-b83f859b73c0?w=800&q=80',
      'groupId': 'worship-team-id',
      'badge': 'LIVE',
      'count': 12,
    },
    {
      'title': 'General Grace Group',
      'subtitle': 'Whole church community chat',
      'image': 'https://images.unsplash.com/photo-1544427920-c49ccfb85579?w=800&q=80',
      'groupId': 'general_grace',
      'badge': null,
      'count': 154,
    },
    {
      'title': 'Youth Ministry',
      'subtitle': 'Empowering the next generation',
      'image': 'https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=800&q=80',
      'groupId': 'youth_ministry',
      'badge': null,
      'count': 47,
    },
    {
      'title': 'Prayer Warriors',
      'subtitle': 'Collective intercession for the nation',
      'image': 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=800&q=80',
      'groupId': 'national-prayer-id',
      'badge': null,
      'count': 89,
    },
    {
      'title': 'Zambian Apostolic Network',
      'subtitle': 'Unity across 50+ congregations',
      'image': 'https://images.unsplash.com/photo-1544427920-c49ccfb85579?w=800&q=80',
      'groupId': 'apostolic-network-id',
      'badge': null,
      'count': 312,
    },
    {
      'title': 'Kingdom Youth Alliance',
      'subtitle': 'Cross-church youth empowerment',
      'image': 'https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=800&q=80',
      'groupId': 'youth-alliance-id',
      'badge': null,
      'count': 98,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _loadingMembers = true);
    final members = await ref.read(chatServiceProvider).fetchChurchMembers(limit: 30);
    if (mounted) {
      setState(() {
        _churchMembers = members;
        _loadingMembers = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFFFAEB),
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

          // Church Groups list
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final group = _churchGroups[index];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _buildGroupTile(context, group),
                );
              },
              childCount: _churchGroups.length,
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
                  child: CircularProgressIndicator(color: Color(0xFF075E54)),
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
        color: const Color(0xFF075E54),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF075E54).withValues(alpha: 0.35),
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
                Text('Kingdom Communities',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                SizedBox(height: 4),
                Text('Real-time collaboration across the Kingdom.',
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
          context, MaterialPageRoute(builder: (_) => const KingdomEventsScreen())),
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

  Widget _buildGroupTile(BuildContext context, Map<String, dynamic> group) {
    final memberCount = group['count'] as int;
    final badge = group['badge'] as String?;

    // Generate some fake member avatars for the stack
    final avatarCount = memberCount > 4 ? 4 : memberCount;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatMessengerScreen(
            userName: group['title']!,
            userAvatar: group['image']!,
            groupId: group['groupId']!,
            isGroup: true,
          ),
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
            // Group image
            Stack(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    image: DecorationImage(
                      image: NetworkImage(group['image']!),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                if (badge != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(badge,
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group['title']!,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(group['subtitle']!,
                      style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 8),
                  // Member avatar stack
                  Row(
                    children: [
                      _buildAvatarStack(avatarCount),
                      const SizedBox(width: 8),
                      Text(
                        '$memberCount members',
                        style: const TextStyle(
                            color: Color(0xFF075E54), fontSize: 11, fontWeight: FontWeight.w600),
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

  Widget _buildAvatarStack(int count) {
    return SizedBox(
      width: 16.0 * count + 22,
      height: 26,
      child: Stack(
        children: List.generate(count, (i) {
          return Positioned(
            left: i * 16.0,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: CircleAvatar(
                radius: 11,
                backgroundImage: NetworkImage('https://i.pravatar.cc/60?img=${i + 20}'),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMemberTile(BuildContext context, Map<String, dynamic> member) {
    final name = member['full_name'] as String? ?? 'Member';
    final id = member['id'] as String? ?? '';
    final avatar = member['avatar_url'] as String? ?? 'https://i.pravatar.cc/100?u=$id';
    final role = member['role'] as String? ?? 'member';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatMessengerScreen(
            userName: name,
            userAvatar: avatar,
            receiverId: id,
          ),
        ),
      ),
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
                CircleAvatar(radius: 24, backgroundImage: NetworkImage(avatar)),
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
                _buildQuickAction(LucideIcons.phone, const Color(0xFF075E54), () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatMessengerScreen(
                        userName: name,
                        userAvatar: avatar,
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
                        userAvatar: avatar,
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
      case 'pastor': return '🎤 Pastor';
      case 'admin': return '⚙️ Admin';
      case 'leader': return '👑 Leader';
      case 'worship': return '🎵 Worship Team';
      default: return '🙏 Church Member';
    }
  }
}
