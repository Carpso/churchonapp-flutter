import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import '../data/game_service.dart';
import '../../bible_quiz/presentation/bible_quiz_hub_screen.dart';
import 'engines/game_engines.dart';

class KingdomGameArenaScreen extends ConsumerStatefulWidget {
  final KingdomGame game;
  const KingdomGameArenaScreen({super.key, required this.game});

  @override
  ConsumerState<KingdomGameArenaScreen> createState() => _KingdomGameArenaScreenState();
}

class _KingdomGameArenaScreenState extends ConsumerState<KingdomGameArenaScreen> {
  bool _isSearching = false;
  bool _isMatchFound = false;
  String? _opponentName;
  String? _opponentAvatar;
  int _countdown = 3;
  bool _isPlaying = false;
  String _selectedLevel = "Level 1";
  bool _isSolo = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: _isPlaying ? _buildGamePlay() : _buildSetup(),
    );
  }

  void _startSolo() {
    setState(() {
      _isSolo = true;
      _isPlaying = true;
    });
  }

  void _startMultiplayer() async {
    setState(() {
      _isSolo = false;
      _isSearching = true;
    });

    final opponent = await ref.read(kingdomGameServiceProvider).findMatch();
    
    if (mounted) {
      setState(() {
        _isSearching = false;
        _isMatchFound = true;
        _opponentName = opponent['name'];
        _opponentAvatar = opponent['avatar'];
      });
      _startCountdown();
    }
  }

  void _startCountdown() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_countdown == 1) {
        timer.cancel();
        setState(() => _isPlaying = true);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Widget _buildSetup() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.brown.shade900, Colors.black],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  IconButton(icon: const Icon(LucideIcons.chevronLeft, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  const Spacer(),
                  const Text("GAME ARENA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            const Spacer(),
            if (!_isSearching && !_isMatchFound) ...[
              Hero(
                tag: widget.game.id,
                child: Container(
                  padding: const EdgeInsets.all(30),
                  decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
                  child: const Icon(LucideIcons.gamepad2, size: 60, color: Colors.amber),
                ),
              ),
              const SizedBox(height: 20),
              Text(widget.game.name, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
              Text(widget.game.category, style: const TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              _buildDifficultySelector(),
              const SizedBox(height: 40),
              _buildLargeButton("SOLO CHALLENGE", LucideIcons.user, Colors.white10, _startSolo),
              const SizedBox(height: 15),
              _buildLargeButton("P2P MULTIPLAYER", LucideIcons.users, Theme.of(context).primaryColor.withValues(alpha: 0.2), _startMultiplayer),
            ] else if (_isSearching) ...[
              _buildMatchmakingUI(),
            ] else if (_isMatchFound) ...[
              _buildMatchFoundUI(),
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildDifficultySelector() {
    return Column(
      children: [
        const Text("SELECT DIFFICULTY", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 15),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: widget.game.levels.map((lvl) {
              final isSelected = _selectedLevel == lvl;
              return GestureDetector(
                onTap: () => setState(() => _selectedLevel = lvl),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.amber : Colors.white10,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(lvl, style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.bold)),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildLargeButton(String title, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 65),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white12)),
        ),
      ),
    );
  }

  Widget _buildMatchmakingUI() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPlayerCircle("You", '', isMe: true),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text("VS", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
            ),
            _buildSearchingLoader(),
          ],
        ),
        const SizedBox(height: 40),
        const CircularProgressIndicator(color: Colors.amber),
        const SizedBox(height: 20),
        const Text("FINDING OPPONENT...", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMatchFoundUI() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPlayerCircle("You", '', isMe: true),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text("VS", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
            ),
            _buildPlayerCircle(_opponentName!, _opponentAvatar!),
          ],
        ),
        const SizedBox(height: 60),
        const Text("MATCH FOUND!", style: TextStyle(color: Colors.greenAccent, fontSize: 24, fontWeight: FontWeight.w900)),
        Text("Starting in $_countdown...", style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildPlayerCircle(String name, String avatar, {bool isMe = false}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: isMe ? Theme.of(context).primaryColor : Theme.of(context).primaryColor.withValues(alpha: 0.5), width: 3)),
          child: CircleAvatar(radius: 40, backgroundImage: NetworkImage(avatar)),
        ),
        const SizedBox(height: 15),
        Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildSearchingLoader() {
    return Column(
      children: [
        Container(
          width: 80, height: 80, 
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05)), 
          child: const Center(child: Icon(LucideIcons.user, color: Colors.white24, size: 40))
        ),
        const SizedBox(height: 15),
        const Text("???", style: TextStyle(color: Colors.white24, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildGamePlay() {
    return GameEngineLauncher(game: widget.game, level: _selectedLevel, isSolo: _isSolo, opponentName: _opponentName);
  }
}

class GameEngineLauncher extends StatelessWidget {
  final KingdomGame game;
  final String level;
  final bool isSolo;
  final String? opponentName;

  const GameEngineLauncher({super.key, required this.game, required this.level, required this.isSolo, this.opponentName});

  @override
  Widget build(BuildContext context) {
    if (game.id == 'bible_quiz') {
      return BibleQuizHubScreen();
    }
    switch (game.id) {
      case 'emoji':
        return EmojiChallengeGame(game: game, level: level, isSolo: isSolo, opponentName: opponentName);
      case 'rap':
        return GospelRapGame(game: game, level: level, isSolo: isSolo, opponentName: opponentName);
      case 'dilemma':
        return ProphetsDilemmaGame(game: game, level: level, isSolo: isSolo, opponentName: opponentName);
      case 'dove':
        return SpiritDoveGame(game: game, level: level, isSolo: isSolo, opponentName: opponentName);
      case 'sling':
        return DavidsSlingGame(game: game, level: level, isSolo: isSolo, opponentName: opponentName);
      case 'charades':
        return BibleCharadesGame(game: game, level: level, isSolo: isSolo, opponentName: opponentName);
      case 'breaker':
        return JerichoBreakerGame(game: game, level: level, isSolo: isSolo, opponentName: opponentName);
      case 'keys':
        return GospelKeysGame(game: game, level: level, isSolo: isSolo, opponentName: opponentName);
      case 'fisher':
        return FisherOfWordsGame(game: game, level: level, isSolo: isSolo, opponentName: opponentName);
      case 'hangman':
        return BibleHangmanGame(game: game, level: level, isSolo: isSolo, opponentName: opponentName);
      case 'sidom':
        return SidomPatternGame(game: game, level: level, isSolo: isSolo, opponentName: opponentName);
      case 'hunt':
        return WordHuntGame(game: game, level: level, isSolo: isSolo, opponentName: opponentName);
      case 'v_match':
        return VerseMatchGame(game: game, level: level, isSolo: isSolo, opponentName: opponentName);
      case 'fill_verse':
        return FillVerseGame(game: game, level: level, isSolo: isSolo, opponentName: opponentName);
      default:
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(game.name),
            leading: IconButton(icon: const Icon(LucideIcons.x), onPressed: () => Navigator.pop(context)),
          ),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.swords, size: 80, color: Theme.of(context).primaryColor),
                const SizedBox(height: 20),
                Text("Coming Soon", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                const Text("Bible Quizzing Arena is currently available.", style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        );
    }
  }
}

