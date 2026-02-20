import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'kingdom_klips_screen.dart';
import 'chat_screen.dart';
// Theme imported via context

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  bool _showKlips = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _showKlips ? const KingdomKlipsScreen() : _buildCommunityList(),
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildToggleButton("KINGDOM KLIPS", _showKlips, true),
                const SizedBox(width: 10),
                _buildToggleButton("COMMUNITIES", !_showKlips, false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, bool isActive, bool mode) {
    return GestureDetector(
      onTap: () => setState(() => _showKlips = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Theme.of(context).primaryColor : Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? Colors.transparent : Colors.white.withOpacity(0.3)),
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

  Widget _buildCommunityList() {
    return Container(
      color: const Color(0xFFFFFAEB),
      padding: const EdgeInsets.only(top: 110),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildCommunityItem("General Grace Group", "Pastor James: God bless you...", "12:45", 3, 'general'),
          _buildCommunityItem("Youth Ministry", "Sarah: See you at 4pm!", "Yesterday", 0, 'youth'),
          _buildCommunityItem("Worship Team", "David: Rehearsal tonight.", "2 days ago", 12, 'worship'),
          _buildCommunityItem("Sunday School Teachers", "Mary: Lesson plans ready.", "Mon", 0, 'teachers'),
        ],
      ),
    );
  }

  Widget _buildCommunityItem(String title, String lastMsg, String time, int badgeCount, String channelId) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChatScreen(chatTitle: title, channelId: channelId)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
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
