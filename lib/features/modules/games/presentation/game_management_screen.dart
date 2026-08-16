import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/providers/profile_provider.dart';
import '../../bible_quiz/presentation/quiz_event_host_screen.dart';
import '../data/game_service.dart';

class GameManagementScreen extends ConsumerWidget {
  const GameManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final isAllowed = profile?.isSuperadmin == true || profile?.isEmployee == true;

    if (!isAllowed) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        appBar: _buildAppBar(context),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.lock, size: 48, color: Colors.white24),
              SizedBox(height: 16),
              Text('Access restricted',
                  style: TextStyle(color: Colors.white54, fontSize: 16)),
              SizedBox(height: 8),
              Text('Superadmin & Employee only',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final games = ref.watch(kingdomGameServiceProvider).games;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: _buildAppBar(context),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Stats overview
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor.withAlpha(40),
                  Theme.of(context).primaryColor.withAlpha(20),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Games Management',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  '${games.length} games • ${games.where((g) => g.id != 'bible_quiz').length} coming soon',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Quick actions
          const Text('Quick Actions',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionCard(
                  context,
                  LucideIcons.trophy,
                  'Bible Quiz',
                  Colors.amberAccent,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const QuizEventHostScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionCard(
                  context,
                  LucideIcons.settings,
                  'Game Settings',
                  Theme.of(context).primaryColor,
                  () => _showSettingsDialog(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _actionCard(
                  context,
                  LucideIcons.barChart3,
                  'Analytics',
                  Colors.greenAccent,
                  () => _showAnalytics(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionCard(
                  context,
                  LucideIcons.filePlus,
                  'Seed Questions',
                  Colors.orangeAccent,
                  () => _seedQuestions(context, ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // All games list
          const Text('All Games',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...games.map((game) => _gameTile(context, game, ref)),
        ],
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: const Text('Games Control',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }

  Widget _actionCard(
      BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF151A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _gameTile(BuildContext context, KingdomGame game, WidgetRef ref) {
    final isQuiz = game.id == 'bible_quiz';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isQuiz ? Colors.amberAccent.withAlpha(30) : Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _iconFor(game.id),
              size: 20,
              color: isQuiz ? Colors.amberAccent : Colors.white38,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.name,
                  style: TextStyle(
                    color: isQuiz ? Colors.amberAccent : Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  game.category,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          if (isQuiz)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('ACTIVE',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('COMING SOON',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(width: 8),
          Switch(
            value: isQuiz,
            activeThumbColor: Colors.greenAccent,
            onChanged: null, // Placeholder for future enable/disable
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String id) {
    switch (id) {
      case 'emoji':
        return LucideIcons.smile;
      case 'rap':
        return LucideIcons.music;
      case 'dilemma':
        return LucideIcons.scale;
      case 'dove':
        return LucideIcons.twitter;
      case 'charades':
        return LucideIcons.users;
      case 'breaker':
        return LucideIcons.castle;
      case 'keys':
        return LucideIcons.music;
      case 'fisher':
        return LucideIcons.fish;
      case 'hangman':
        return LucideIcons.helpCircle;
      case 'sidom':
        return LucideIcons.brain;
      case 'hunt':
        return LucideIcons.search;
      case 'v_match':
        return LucideIcons.bookOpen;
      case 'fill_verse':
        return LucideIcons.edit3;
      default:
        return LucideIcons.gamepad2;
    }
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Game Settings',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Per-game settings (enable/disable per church, difficulty presets) coming soon.',
          style: TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showAnalytics(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Game Analytics',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Detailed analytics (total plays, top players, category performance) coming soon.',
          style: TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _seedQuestions(BuildContext context, WidgetRef ref) async {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use the Bible Quiz Hub admin panel to seed questions')),
      );
    }
  }
}
