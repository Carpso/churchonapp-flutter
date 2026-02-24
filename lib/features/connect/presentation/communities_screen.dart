import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'chat_messenger_screen.dart';
import '../../modules/media/presentation/kingdom_events_screen.dart';

class CommunitiesScreen extends StatelessWidget {
  const CommunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Kingdom Communities", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 30),
            const Text("STRATEGIC MISSIONS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.grey)),
            const SizedBox(height: 15),
            _buildEventGateway(context),
            const SizedBox(height: 30),
            const Text("INTER-CHURCH HUBS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.grey)),
            const SizedBox(height: 15),
            _buildHubTile(
              context,
              "Zambian Apostolic Network",
              "Unity in the spirit across 50+ congregations",
              "https://images.unsplash.com/photo-1544427920-c49ccfb85579?w=800&q=80",
              "apostolic-network-id",
            ),
            _buildHubTile(
              context,
              "National Prayer Group",
              "Collective intercession for the nation",
              "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=800&q=80",
              "national-prayer-id",
            ),
            _buildHubTile(
              context,
              "Kingdom Youth Alliance",
              "Empowering the next generation of leaders",
              "https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=800&q=80",
              "youth-alliance-id",
            ),
            const SizedBox(height: 30),
            const Text("LOCAL CONGREGATION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.grey)),
            const SizedBox(height: 15),
            _buildHubTile(
              context,
              "Worship Team Coordination",
              "Internal prep for Sunday missions",
              "https://images.unsplash.com/photo-1514525253361-b83f859b73c0?w=800&q=80",
              "worship-team-id",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: const Row(
        children: [
          Icon(LucideIcons.users, color: Colors.white, size: 40),
          SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Unified Presence", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                Text("Real-time collaboration across the Kingdom.", style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventGateway(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const KingdomEventsScreen())),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
              child: const Icon(LucideIcons.ticket, color: Colors.black, size: 24),
            ),
            const SizedBox(width: 20),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Multi-Church Ticketing", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("Secure your spot for conferences & worship nights.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            const Icon(LucideIcons.arrowRight, color: Colors.amber),
          ],
        ),
      ),
    );
  }

  Widget _buildHubTile(BuildContext context, String title, String subtitle, String imageUrl, String hubId) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatMessengerScreen(
              userName: title,
              userAvatar: imageUrl,
              groupId: hubId,
              isGroup: true,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
        ),
        child: Row(
          children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                image: DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}
