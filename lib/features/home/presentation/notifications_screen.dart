import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Kingdom Alerts"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(25),
        children: [
          _buildNotificationItem(
            "Church-wide Fasting",
            "Join us for 3 days of prayer and fasting starting tomorrow.",
            "2 hours ago",
            LucideIcons.flame,
            Colors.orange,
            isNew: true,
          ),
          _buildNotificationItem(
            "New Sermon Uploaded",
            "Bishop John Mwansa: 'Walking in the Spirit' is now available.",
            "5 hours ago",
            LucideIcons.playCircle,
            Colors.blue,
            isNew: true,
          ),
          _buildNotificationItem(
            "Donation Verified",
            "Your Tithe of ₵ 1,200 has been successfully processed and verified.",
            "Yesterday",
            LucideIcons.checkCircle,
            Colors.green,
            isNew: false,
          ),
          _buildNotificationItem(
            "Event Reminder",
            "Youth Choir Rehearsal starts in 30 minutes at the Music Hall.",
            "Yesterday",
            LucideIcons.bell,
            Colors.purple,
            isNew: false,
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(String title, String body, String time, IconData icon, Color color, {bool isNew = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: isNew ? Border.all(color: color.withOpacity(0.3)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (isNew)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(body, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.4)),
                const SizedBox(height: 10),
                Text(time, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
