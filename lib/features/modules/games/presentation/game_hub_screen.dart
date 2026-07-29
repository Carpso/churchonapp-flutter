import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../bible_quiz/presentation/bible_quiz_hub_screen.dart';

class KingdomGamesHubScreen extends ConsumerWidget {
  const KingdomGamesHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;

    return Container(
      color: primary.withValues(alpha: 0.05),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        children: [
          Row(
            children: [
              Icon(LucideIcons.gamepad2, color: primary, size: 32),
              const SizedBox(width: 15),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Games", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: primary)),
                  Text("Pure edifying entertainment", style: TextStyle(fontSize: 12, color: primary.withValues(alpha: 0.7), fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 25),
          _buildQuizBanner(context, primary),
          const SizedBox(height: 15),
        ],
      ),
    );
  }

  Widget _buildQuizBanner(BuildContext context, Color primary) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BibleQuizHubScreen())),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [primary, primary.withValues(alpha: 0.7)]),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.trophy, color: Colors.amber, size: 30),
                const SizedBox(width: 10),
                Text("SEASON 1 OPEN", style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ],
            ),
            const SizedBox(height: 15),
            const Text("Bible Quizzing Arena", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            const Text("Join thousands of members in the international Bible competition.", style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 25),
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BibleQuizHubScreen())),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: primary,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("ENTER ARENA", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
