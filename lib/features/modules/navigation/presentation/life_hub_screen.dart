import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/modules/media/presentation/radio_screen.dart';
import 'package:church_on_app/features/connect/presentation/testimonies_screen.dart';
import 'package:church_on_app/features/connect/presentation/prayer_wall_screen.dart';

class LifeHubScreen extends StatelessWidget {
  const LifeHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Life", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(25),
        children: [
          _buildHubItem(
            context,
            "Radio",
            "24/7 Gospel Broadcast",
            LucideIcons.radio,
            Colors.orange,
            () => _navigateSafely(context, const RadioScreen()),
          ),
          const SizedBox(height: 15),
          _buildHubItem(
            context,
            "Testimonies",
            "Praise Reports & Miracles",
            LucideIcons.flame,
            Colors.red,
            () => _navigateSafely(context, const TestimoniesScreen()),
          ),
          const SizedBox(height: 15),
          _buildHubItem(
            context,
            "Prayer Wall",
            "Intercede for the Brethren",
            LucideIcons.helpingHand,
            Colors.blue,
            () => _navigateSafely(context, const PrayerWallScreen()),
          ),
        ],
      ),
    );
  }

  void _navigateSafely(BuildContext context, Widget screen) {
    try {
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to open this feature")),
      );
    }
  }

  Widget _buildHubItem(BuildContext context, String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
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
}
