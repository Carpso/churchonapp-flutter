import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'chat_messenger_screen.dart';

class GroupDetailsScreen extends ConsumerWidget {
  final Map<String, dynamic> group;

  const GroupDetailsScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberCount = group['count'] as int;
    final groupId = group['groupId'] as String;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(group['image'], fit: BoxFit.cover),
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
                        Text(group['title'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(LucideIcons.users, color: Colors.white70, size: 16),
                            const SizedBox(width: 6),
                            Text("$memberCount members", style: const TextStyle(color: Colors.white70, fontSize: 14)),
                            if (group['badge'] != null) ...[
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                                child: Text(group['badge'], style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                              ),
                            ],
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
                  Text(group['subtitle'], style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87)),
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
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final imgIndex = (index + 10) % 70;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage('https://i.pravatar.cc/60?img=$imgIndex'),
                  ),
                  title: Text("Member ${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text("Active in chat", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: const Icon(LucideIcons.messageCircle, color: Color(0xFF075E54), size: 18),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ChatMessengerScreen(
                        userName: "Member ${index + 1}",
                        userAvatar: 'https://i.pravatar.cc/60?img=$imgIndex',
                        receiverId: 'member-$imgIndex',
                      ),
                    ));
                  },
                );
              },
              childCount: memberCount > 20 ? 20 : memberCount,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(LucideIcons.userPlus, size: 18),
                label: const Text("JOIN GROUP"),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ChatMessengerScreen(
                      userName: group['title'],
                      userAvatar: group['image'],
                      groupId: groupId,
                      isGroup: true,
                    ),
                  ));
                },
                icon: const Icon(LucideIcons.send, size: 18, color: Colors.white),
                label: const Text("OPEN CHAT"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF075E54),
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
