import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class KingdomGame {
  final String id;
  final String name;
  final String description;
  final String icon;
  final String category; // Brain Growth, Stress Reliever, Addictive
  final List<String> levels; // Level names/IDs

  KingdomGame({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.category,
    this.levels = const ['Level 1', 'Level 2', 'Level 3', 'Infinite'],
  });
}

class KingdomGameService {
  final SupabaseClient _client;

  KingdomGameService(this._client);

  final List<KingdomGame> games = [
    KingdomGame(id: 'emoji', name: 'Emoji Challenge', description: 'Guess the verse from emojis', icon: 'smile', category: 'Brain Growth'),
    KingdomGame(id: 'rap', name: 'Gospel Rap', description: 'Complete the rhyme in gospel lyrics', icon: 'mic', category: 'Addictive'),
    KingdomGame(id: 'dilemma', name: 'Prophet\'s Dilemma', description: 'Choose the right prophetic response', icon: 'flame', category: 'Brain Growth'),
    KingdomGame(id: 'dove', name: 'Spirit Dove', description: 'Guide the dove through obstacles', icon: 'bird', category: 'Stress Reliever'),
    KingdomGame(id: 'sling', name: 'David\'s Sling', description: 'Classic target aim and shoot', icon: 'target', category: 'Stress Reliever'),
    KingdomGame(id: 'charades', name: 'Charades', description: 'Gospel-themed charades game', icon: 'masks', category: 'Social'),
    KingdomGame(id: 'breaker', name: 'Jericho Breaker', description: 'Wall demolition rhythm game', icon: 'hammer', category: 'Addictive'),
    KingdomGame(id: 'keys', name: 'Gospel Keys', description: 'Magic piano tiles with hymns', icon: 'music', category: 'Stress Reliever'),
    KingdomGame(id: 'fisher', name: 'Fisher of Words', description: 'Catch the right words in the net', icon: 'anchor', category: 'Brain Growth'),
     KingdomGame(id: 'hangman', name: 'Hangman', description: 'Classic word guessing', icon: 'help-circle', category: 'Brain Growth'),
    KingdomGame(id: 'sidom', name: 'Sidom Pattern', description: 'Memory pattern matching', icon: 'grid', category: 'Brain Growth'),
    KingdomGame(id: 'hunt', name: 'Bible Word Hunt', description: 'Search for hidden scriptures', icon: 'search', category: 'Brain Growth'),
    KingdomGame(id: 'v_match', name: 'Verse Match', description: 'Pair corresponding verses', icon: 'link', category: 'Brain Growth'),
    KingdomGame(id: 'fill_verse', name: 'Fill the Verse', description: 'Fill in the blanks', icon: 'edit-3', category: 'Brain Growth'),
  ];

  Future<Map<String, dynamic>> findMatch() async {
    // Shared matchmaking simulator
    await Future.delayed(const Duration(seconds: 2));
    final users = [
      {'name': 'Brother Isaac', 'avatar': 'https://i.pravatar.cc/150?u=isaac'},
      {'name': 'Sister Mercy', 'avatar': 'https://i.pravatar.cc/150?u=mercy'},
      {'name': 'Elder Paul', 'avatar': 'https://i.pravatar.cc/150?u=paul'},
      {'name': 'Ruth the Believer', 'avatar': 'https://i.pravatar.cc/150?u=ruth'},
    ];
    return users[DateTime.now().millisecond % users.length];
  }

  Future<void> recordScore(String gameId, int score) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    
    // In real app, we would update a game_scores table
    // For now we just print for simulation
    debugPrint("Recording Score for $gameId: $score");
  }
}

final kingdomGameServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return KingdomGameService(client);
});

