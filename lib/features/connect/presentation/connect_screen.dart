import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/social_service.dart';
import 'kingdom_klips_screen.dart';
import 'chat_messenger_screen.dart';
import '../../modules/media/presentation/kingdom_radio_screen.dart';
import 'testimonies_screen.dart';
import 'prayer_wall_screen.dart';
import 'communities_screen.dart';
import 'create_social_post_screen.dart';
import '../../modules/games/presentation/game_hub_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  int _activeTab = 0; // 0: Klips, 1: Communities, 2: Kingdom Life, 3: Kingdom Games

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildContent(),
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildToggleButton("KINGDOM KLIPS", _activeTab == 0, 0),
                  const SizedBox(width: 10),
                  _buildToggleButton("COMMUNITIES", _activeTab == 1, 1),
                  const SizedBox(width: 10),
                  _buildToggleButton("KINGDOM LIFE", _activeTab == 2, 2),
                  const SizedBox(width: 10),
                  _buildToggleButton("KINGDOM GAMES", _activeTab == 3, 3),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateSocialPostScreen())),
        backgroundColor: Theme.of(context).primaryColor,
        child: Icon(LucideIcons.plus, color: Theme.of(context).colorScheme.secondary),
      ),
    );
  }

  Widget _buildContent() {
    switch (_activeTab) {
      case 0:
        return const KingdomKlipsScreen();
      case 1:
        return const CommunitiesScreen();
      case 2:
        return _buildKingdomLife();
      case 3:
        return const KingdomGamesHubScreen();
      default:
        return const KingdomKlipsScreen();
    }
  }

  Widget _buildToggleButton(String label, bool isActive, int index) {
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Theme.of(context).primaryColor : Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? Colors.transparent : Colors.white.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Theme.of(context).colorScheme.secondary : Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _buildKingdomLife() {
    return Container(
      color: const Color(0xFFFFFAEB),
      padding: const EdgeInsets.only(top: 110),
      child: Consumer(
        builder: (context, ref, child) {
          final postsAsync = ref.watch(socialPostsProvider);

          return ListView(
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
              const SizedBox(height: 20),
              _buildKingdomLifeFeature(
                "Kingdom Radio",
                "24/7 Gospel Broadcast",
                LucideIcons.radio,
                Colors.orange,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const KingdomRadioScreen()))
              ),
              const SizedBox(height: 15),
              _buildKingdomLifeFeature(
                "Testimonies",
                "Praise Reports & Miracles",
                LucideIcons.flame,
                Colors.red,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const TestimoniesScreen()))
              ),
              const SizedBox(height: 15),
              _buildKingdomLifeFeature(
                "Prayer Wall",
                "Intercede for the Brethren",
                LucideIcons.helpingHand,
                Colors.blue,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PrayerWallScreen()))
              ),
            ],
          );
        }
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
          if (post.mediaUrl != null && post.mediaType == 'image')
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
                Row(
                  children: [
                    const Icon(LucideIcons.heart, size: 24, color: Colors.red),
                    const SizedBox(width: 6),
                    Text("${post.likesCount}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(width: 15),
                    const Icon(LucideIcons.messageCircle, size: 24),
                    const SizedBox(width: 15),
                    const Icon(LucideIcons.send, size: 24),
                    const Spacer(),
                    const Icon(LucideIcons.bookmark, size: 24),
                  ],
                ),
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
    return Row(
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
    );
  }

  Widget _buildKingdomLifeFeature(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildChatHub() {
    return Container(
      color: const Color(0xFFFFFAEB),
      padding: const EdgeInsets.only(top: 110),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text("Communities", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          _buildCommunityItem("General Grace Group", "Pastor James: God bless you...", "12:45", 3, 'general_grace'),
          _buildCommunityItem("Youth Ministry", "Sarah: See you at 4pm!", "Yesterday", 0, 'youth_ministry'),
          const SizedBox(height: 30),
          const Text("Direct Messages", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Consumer(
            builder: (context, ref, child) {
              return FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchRecentUsers(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.amber));
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(LucideIcons.users, size: 40, color: Colors.grey[300]),
                            const SizedBox(height: 8),
                            const Text("No members found yet", style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    );
                  }
                  final users = snapshot.data!;
                  return Column(
                    children: users.map((u) => _buildUserChatItem(
                      u['full_name'] ?? 'Member',
                      u['last_msg'] ?? "Say Shalom!",
                      "10:30",
                      0,
                      u['id'] ?? '',
                    )).toList(),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchRecentUsers() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return [];
      
      final res = await Supabase.instance.client
          .from('profiles')
          .select('full_name, id')
          .neq('id', currentUserId)
          .limit(5);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Error fetching users: $e');
      return [];
    }
  }

  Widget _buildUserChatItem(String name, String lastMsg, String time, int badgeCount, String userId) {
    String avatar = "https://i.pravatar.cc/150?u=$userId";
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChatMessengerScreen(
            userName: name, 
            userAvatar: avatar,
            receiverId: userId,
          )),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
        ),
        child: Row(
          children: [
            CircleAvatar(radius: 25, backgroundImage: NetworkImage(avatar)),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(lastMsg, style: const TextStyle(color: Colors.grey, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Text(time, style: const TextStyle(color: Colors.grey, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildCommunityItem(String title, String lastMsg, String time, int badgeCount, String channelId) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChatMessengerScreen(
            userName: title, 
            userAvatar: "https://i.pravatar.cc/150?img=${title.length % 50}",
            receiverId: channelId,
          )),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              child: Icon(LucideIcons.users, color: Theme.of(context).primaryColor),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.secondary)),
                  const SizedBox(height: 4),
                  Text(lastMsg, style: const TextStyle(color: Colors.grey, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(time, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                const SizedBox(height: 8),
                if (badgeCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
                    child: Text(badgeCount.toString(), style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
