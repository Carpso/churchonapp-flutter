import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/utils/connectivity_util.dart';
import '../data/kids_service.dart';
import 'activity_details_page.dart';

class KidsZoneScreen extends ConsumerWidget {
  const KidsZoneScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wire KidsService into kids zone feature lifecycle
    ref.watch(kidsServiceProvider);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        title: const Text("Kids Zone", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
      ),
      body: OfflineAwareWrapper(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildHeaderBanner(theme),
            const SizedBox(height: 24),
            _buildSectionTitle("Activities"),
            const SizedBox(height: 12),
            _buildActivityGrid(context),
            const SizedBox(height: 24),
            _buildSectionTitle("Bible Stories"),
            const SizedBox(height: 12),
            _buildStoryList(),
            const SizedBox(height: 24),
            _buildSectionTitle("Progress"),
            const SizedBox(height: 12),
            _buildProgressCard(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.orange, Colors.deepOrange]),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Junior", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text("Earn points by learning verses and completing activities!", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.coins, color: Colors.amber, size: 16),
                      const SizedBox(width: 6),
                      Text("240 Points", style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.15)),
            child: const Icon(LucideIcons.smile, color: Colors.white, size: 44),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF2D1810)));
  }

  Widget _buildActivityGrid(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _activityCard(context, "Bible Trivia", LucideIcons.helpCircle, Colors.purple, "Answer fun questions")),
            const SizedBox(width: 12),
            Expanded(child: _activityCard(context, "Memory Verses", LucideIcons.book, Colors.blue, "Learn scripture")),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _activityCard(context, "Coloring Book", LucideIcons.penTool, Colors.pink, "Bible scenes")),
            const SizedBox(width: 12),
            Expanded(child: _activityCard(context, "Sunday School", LucideIcons.video, Colors.teal, "Watch & learn")),
          ],
        ),
      ],
    );
  }

  Widget _activityCard(BuildContext context, String title, IconData icon, Color color, String subtitle) {
    return GestureDetector(
      onTap: () {
        try {
          Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailsPage(title: title, icon: icon, color: color)));
        } catch (e) {
          debugPrint('Error navigating to activity details: $e');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(18)),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 10), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryList() {
    final stories = [
      {"title": "David and Goliath", "verses": "1 Samuel 17", "color": Colors.blue},
      {"title": "Jonah and the Whale", "verses": "Jonah 1-3", "color": Colors.teal},
      {"title": "Noah's Ark", "verses": "Genesis 6-9", "color": Colors.brown},
      {"title": "The Birth of Jesus", "verses": "Luke 2", "color": Colors.red},
    ];
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: stories.length,
        itemBuilder: (context, index) {
          final story = stories[index];
          return Container(
            width: 160,
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (story['color'] as Color).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(story['title'] as String, style: TextStyle(color: story['color'] as Color, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(story['verses'] as String, style: const TextStyle(color: Colors.grey, fontSize: 10)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProgressCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Weekly Progress", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text("3 of 5 done", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(value: 0.6, backgroundColor: Colors.grey.withValues(alpha: 0.1), valueColor: AlwaysStoppedAnimation(theme.primaryColor), minHeight: 8),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _dayChip("M", true, theme),
              _dayChip("T", true, theme),
              _dayChip("W", true, theme),
              _dayChip("Th", false, theme),
              _dayChip("F", false, theme),
              _dayChip("Sa", false, theme),
              _dayChip("Su", false, theme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayChip(String day, bool done, ThemeData theme) {
    return Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? theme.primaryColor : Colors.grey.withValues(alpha: 0.1),
      ),
      child: Center(child: Text(day, style: TextStyle(color: done ? Colors.white : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold))),
    );
  }
}
