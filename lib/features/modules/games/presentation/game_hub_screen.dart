import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/game_service.dart';
import 'game_arena_screen.dart';

class KingdomGamesHubScreen extends ConsumerWidget {
  const KingdomGamesHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(kingdomGameServiceProvider);
    final games = service.games;

    return Container(
      color: const Color(0xFFFDEFD5), // Warm parchment feel
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 100), // Height for the top toggle
          const Row(
            children: [
              Icon(LucideIcons.gamepad2, color: Colors.brown, size: 32),
              SizedBox(width: 15),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Kingdom Games", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.brown)),
                  Text("Pure edifying entertainment", style: TextStyle(fontSize: 12, color: Colors.brown, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 30),
          Expanded(
            child: ListView.builder(
              itemCount: games.length,
              itemBuilder: (context, index) {
                final game = games[index];
                return _buildGameCard(context, game);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameCard(BuildContext context, KingdomGame game) {
    // Map icons from strings
    IconData icon;
    Color color;

    switch (game.id) {
      case 'emoji': icon = LucideIcons.smile; color = Colors.orange; break;
      case 'rap': icon = LucideIcons.mic; color = Colors.purple; break;
      case 'dilemma': icon = LucideIcons.flame; color = Colors.red; break;
      case 'dove': icon = LucideIcons.bird; color = Colors.blue; break;
      case 'sling': icon = LucideIcons.target; color = Colors.green; break;
      case 'charades': icon = LucideIcons.users2; color = Colors.indigo; break;
      case 'breaker': icon = LucideIcons.hammer; color = Colors.deepOrange; break;
      case 'keys': icon = LucideIcons.music; color = Colors.pink; break;
      case 'fisher': icon = LucideIcons.anchor; color = Colors.teal; break;
      case 'hangman': icon = LucideIcons.helpCircle; color = Colors.brown; break;
      case 'sidom': icon = LucideIcons.grid; color = Colors.cyan; break;
      case 'hunt': icon = LucideIcons.search; color = Colors.amber; break;
      case 'v_match': icon = LucideIcons.link; color = Colors.lightBlue; break;
      case 'fill_verse': icon = LucideIcons.edit3; color = Colors.deepPurple; break;
      default: icon = LucideIcons.gamepad2; color = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 15, offset: const Offset(0, 5))],
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => KingdomGameArenaScreen(game: game)),
            );
          },
          borderRadius: BorderRadius.circular(25),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(game.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        ],
                      ),
                      Text(game.description, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(LucideIcons.playCircle, color: Colors.black26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
