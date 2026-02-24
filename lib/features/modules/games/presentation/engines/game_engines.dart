import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'dart:math';
import '../../data/game_service.dart';

abstract class KingdomGameEngine extends StatefulWidget {
  final KingdomGame game;
  final String level;
  final bool isSolo;
  final String? opponentName;

  const KingdomGameEngine({
    super.key,
    required this.game,
    required this.level,
    required this.isSolo,
    this.opponentName,
  });
}

abstract class KingdomGameEngineState<T extends KingdomGameEngine> extends State<T> {
  int score = 0;
  int opponentScore = 0;
  bool isGameOver = false;
  final AudioPlayer audioPlayer = AudioPlayer();

  void playSound(String path) async {
    // Simulated Sound
  }

  void endMatch() {
    if (isGameOver) return;
    setState(() => isGameOver = true);
    _showCelebration();
  }

  void _showCelebration() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D3F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.crown, color: Colors.amber, size: 80),
            const SizedBox(height: 20),
            const Text("DIVINE VICTORY!", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text("Score: $score", style: const TextStyle(color: Colors.white70, fontSize: 18)),
            const SizedBox(height: 30),
            _buildChestReward(),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () { 
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Exit arena
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 50)),
              child: const Text("REDEMPTION COMPLETE", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChestReward() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber.withValues(alpha: 0.3))),
      child: const Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.package2, color: Colors.amber),
              SizedBox(width: 15),
              Text("Unlocked Biblical Chest!", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 8),
          Text("+50 Church Coins Earned", style: TextStyle(color: Colors.white70, fontSize: 12)),
          Text("(In-app activity points, no cash value)", style: TextStyle(color: Colors.white38, fontSize: 8)),
        ],
      ),
    );
  }
}

// 1. Emoji Challenge
class EmojiChallengeGame extends KingdomGameEngine {
  const EmojiChallengeGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<EmojiChallengeGame> createState() => _EmojiChallengeState();
}
class _EmojiChallengeState extends KingdomGameEngineState<EmojiChallengeGame> {
  final List<Map<String, dynamic>> _data = [
    {'emojis': '🍎🐍👫', 'answer': 'Adam and Eve'},
    {'emojis': '🚢🌊🦁', 'answer': 'Noah\'s Ark'},
    {'emojis': '👑💡📜', 'answer': 'Solomon'},
  ];
  int _index = 0;
  final TextEditingController _controller = TextEditingController();
  void _check() {
    if (_controller.text.trim().toLowerCase() == _data[_index]['answer'].toString().toLowerCase()) {
      setState(() {
        score += 100;
        if (_index < _data.length - 1) { _index++; _controller.clear(); } else { endMatch(); }
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.game.name)),
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text("Guess the Story", style: TextStyle(color: Colors.grey)),
          Text(_data[_index]['emojis'], style: const TextStyle(fontSize: 80)),
          const SizedBox(height: 40),
          TextField(controller: _controller, decoration: InputDecoration(hintText: "Your answer...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(20))), onSubmitted: (_) => _check()),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _check, child: const Text("SUBMIT")),
        ]),
      ),
    );
  }
}

// 2. Gospel Keys
class GospelKeysGame extends KingdomGameEngine {
  const GospelKeysGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<GospelKeysGame> createState() => _GospelKeysState();
}
class _GospelKeysState extends KingdomGameEngineState<GospelKeysGame> {
  final List<int> _activeKeys = [];
  Timer? _timer;
  @override
  void initState() { super.initState(); _startGame(); }
  void _startGame() {
    _timer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (!mounted) return;
      setState(() { _activeKeys.add(Random().nextInt(4)); if (_activeKeys.length > 12) { timer.cancel(); endMatch(); } });
    });
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.black, body: Row(children: List.generate(4, (i) => Expanded(child: GestureDetector(
      onTap: () { if (_activeKeys.contains(i)) setState(() { score += 50; _activeKeys.remove(i); }); },
      child: Container(margin: const EdgeInsets.all(2), color: _activeKeys.contains(i) ? Colors.blue : Colors.white10, child: const Center(child: Icon(LucideIcons.music, color: Colors.white24))),
    )))));
  }
}

// 3. David's Sling
class DavidsSlingGame extends KingdomGameEngine {
  const DavidsSlingGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<DavidsSlingGame> createState() => _DavidsSlingState();
}
class _DavidsSlingState extends KingdomGameEngineState<DavidsSlingGame> {
  double _tx = 0.5, _ty = 0.3; int _h = 0;
  void _move() => setState(() { _tx = Random().nextDouble(); _ty = 0.1 + Random().nextDouble() * 0.5; });
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.green.shade900, body: Stack(children: [
      Positioned(left: MediaQuery.of(context).size.width * _tx - 25, top: MediaQuery.of(context).size.height * _ty, child: IconButton(icon: const Icon(LucideIcons.ghost, size: 50, color: Colors.white70), onPressed: () {
        setState(() { score += 200; _h++; if (_h >= 8) endMatch(); else _move(); });
      })),
      const Positioned(bottom: 40, left: 0, right: 0, child: Icon(LucideIcons.shield, size: 120, color: Colors.brown)),
      Positioned(top: 60, left: 20, child: Text("Giants Slain: $_h / 8", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
    ]));
  }
}

// 4. Hangman
class BibleHangmanGame extends KingdomGameEngine {
  const BibleHangmanGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<BibleHangmanGame> createState() => _BibleHangmanState();
}
class _BibleHangmanState extends KingdomGameEngineState<BibleHangmanGame> {
  final String _word = "PENTECOST";
  List<String> _guessed = [];
  int _wrongs = 0;
  void _guess(String l) {
    if (_guessed.contains(l)) return;
    setState(() { _guessed.add(l); if (!_word.contains(l)) _wrongs++; if (_wrongs >= 6 || _word.split('').every((e) => _guessed.contains(e))) endMatch(); });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("Bible Hangman")), body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text("Mistakes: $_wrongs / 6", style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 40),
      Text(_word.split('').map((e) => _guessed.contains(e) ? e : "_").join(" "), style: const TextStyle(fontSize: 32, letterSpacing: 5)),
      const SizedBox(height: 40),
      Wrap(children: "ABCDEFGHIJKLMNOPQRSTUVWXYZ".split('').map((l) => TextButton(onPressed: () => _guess(l), child: Text(l))).toList()),
    ])));
  }
}

// 5. Spirit Dove (Runner)
class SpiritDoveGame extends KingdomGameEngine {
  const SpiritDoveGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<SpiritDoveGame> createState() => _SpiritDoveState();
}
class _SpiritDoveState extends KingdomGameEngineState<SpiritDoveGame> {
  double _y = 0;
  Timer? _t;
  @override
  void initState() { super.initState(); _t = Timer.periodic(const Duration(milliseconds: 50), (t) => setState(() { _y += 0.02; if (_y > 1) endMatch(); score += 5; })); }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: () => setState(() => _y -= 0.15), child: Scaffold(backgroundColor: Colors.lightBlue.shade100, body: Stack(children: [
      Positioned(left: 50, top: MediaQuery.of(context).size.height * _y, child: const Icon(LucideIcons.bird, size: 50, color: Colors.white)),
      Positioned(top: 50, left: 20, child: Text("Anointing Level: $score", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
    ])));
  }
}

// 6. Verse Match
class VerseMatchGame extends KingdomGameEngine {
  const VerseMatchGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<VerseMatchGame> createState() => _VerseMatchState();
}
class _VerseMatchState extends KingdomGameEngineState<VerseMatchGame> {
  final List<String> _refs = ["John 3:16", "Gen 1:1", "Psalm 23:1"];
  final List<String> _texts = ["In the beginning...", "The Lord is my shepherd...", "For God so loved..."];
  String? _selRef, _selTxt;
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("Verse Match")), body: Row(children: [
      Expanded(child: ListView(children: _refs.map((r) => ListTile(title: Text(r), selected: _selRef == r, onTap: () => setState(() => _selRef = r))).toList())),
      Expanded(child: ListView(children: _texts.map((t) => ListTile(title: Text(t), selected: _selTxt == t, onTap: () {
        setState(() { _selTxt = t; if (_selRef != null) { score += 500; if (score >= 1500) endMatch(); else { _selRef = null; _selTxt = null; } } });
      })).toList())),
    ]));
  }
}

// 7. Fisher of Words
class FisherOfWordsGame extends KingdomGameEngine {
  const FisherOfWordsGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<FisherOfWordsGame> createState() => _FisherOfWordsState();
}
class _FisherOfWordsState extends KingdomGameEngineState<FisherOfWordsGame> {
  List<String> _words = ["Faith", "Hope", "Love", "Grace", "Sin"];
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.blue.shade900, body: Stack(children: _words.map((w) => Positioned(
      left: Random().nextDouble() * 300, top: Random().nextDouble() * 600,
      child: ActionChip(label: Text(w), onPressed: () {
        setState(() { if (w != "Sin") score += 300; else score -= 500; _words.remove(w); if (_words.isEmpty) endMatch(); });
      }),
    )).toList()));
  }
}

// 8. Jericho Breaker
class JerichoBreakerGame extends KingdomGameEngine {
  const JerichoBreakerGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<JerichoBreakerGame> createState() => _JerichoBreakerState();
}
class _JerichoBreakerState extends KingdomGameEngineState<JerichoBreakerGame> {
  int _hp = 20;
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(LucideIcons.castle, size: 150, color: Colors.brown),
      const SizedBox(height: 20),
      Text("Wall HP: $_hp", style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
      const SizedBox(height: 50),
      InkWell(onTap: () => setState(() { _hp--; score += 50; if (_hp <= 0) endMatch(); }), child: const CircleAvatar(radius: 50, child: Icon(LucideIcons.volume2, size: 50))),
      const Text("SHOUT / BLOW TRUMPET"),
    ])));
  }
}

// 9. Prophet's Dilemma
class ProphetsDilemmaGame extends KingdomGameEngine {
  const ProphetsDilemmaGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<ProphetsDilemmaGame> createState() => _ProphetsDilemmaState();
}
class _ProphetsDilemmaState extends KingdomGameEngineState<ProphetsDilemmaGame> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text("Prophetic Situation:", style: TextStyle(color: Colors.amber)),
      const Text("The King asks for a word but expects a lie. Do you:", textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 40),
      _opt("Speak Truth & Risk Jail", true),
      _opt("Flatter the King", false),
      _opt("Run away to Tarshish", false),
    ])));
  }
  Widget _opt(String t, bool c) => Padding(padding: const EdgeInsets.all(10), child: ElevatedButton(onPressed: () { if (c) score += 1000; endMatch(); }, child: Text(t)));
}

// 10. Bible Word Hunt
class WordHuntGame extends KingdomGameEngine {
  const WordHuntGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<WordHuntGame> createState() => _WordHuntState();
}
class _WordHuntState extends KingdomGameEngineState<WordHuntGame> {
  final List<String> _letters = ["G", "R", "A", "C", "E", "L", "O", "V", "E"];
  final List<String> _found = [];
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: GridView.count(crossAxisCount: 3, children: _letters.map((l) => Center(child: ActionChip(label: Text(l), onPressed: () {
      setState(() { _found.add(l); score += 100; if (_found.length >= 5) endMatch(); });
    }))).toList()));
  }
}

// 11. Sidom Pattern (Memory)
class SidomPatternGame extends KingdomGameEngine {
  const SidomPatternGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<SidomPatternGame> createState() => _SidomPatternState();
}
class _SidomPatternState extends KingdomGameEngineState<SidomPatternGame> {
  List<int> _p = [0, 2, 1, 3], _u = [];
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: GridView.count(crossAxisCount: 2, children: List.generate(4, (i) => GestureDetector(onTap: () {
      setState(() { _u.add(i); if (_u.length == _p.length) { if (_u.join() == _p.join()) score += 2000; endMatch(); } });
    }, child: Container(margin: const EdgeInsets.all(5), color: _u.contains(i) ? Colors.amber : Colors.grey)))));
  }
}

// 12. Gospel Rap
class GospelRapGame extends KingdomGameEngine {
  const GospelRapGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<GospelRapGame> createState() => _GospelRapState();
}
class _GospelRapState extends KingdomGameEngineState<GospelRapGame> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text("Finish the Rhyme:", style: TextStyle(fontSize: 18)),
      const Text("'I was lost but now I\'m found...'"),
      const SizedBox(height: 20),
      ElevatedButton(onPressed: () { score += 1000; endMatch(); }, child: const Text("'Amazing Grace, how sweet the sound'")),
      ElevatedButton(onPressed: () => endMatch(), child: const Text("'Testing testing 1 2 3'")),
    ])));
  }
}

// 13. Charades (Social)
class BibleCharadesGame extends KingdomGameEngine {
  const BibleCharadesGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<BibleCharadesGame> createState() => _BibleCharadesState();
}
class _BibleCharadesState extends KingdomGameEngineState<BibleCharadesGame> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text("ACT IT OUT:", style: TextStyle(color: Colors.grey)),
      const Text("PARTING THE RED SEA", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
      const SizedBox(height: 50),
      ElevatedButton(onPressed: () { score += 500; endMatch(); }, child: const Text("GUESSED CORRECTLY!")),
    ])));
  }
}

// 14. Fill the Verse
class FillVerseGame extends KingdomGameEngine {
  const FillVerseGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<FillVerseGame> createState() => _FillVerseState();
}
class _FillVerseState extends KingdomGameEngineState<FillVerseGame> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text("Fill in the blank:", style: TextStyle(fontSize: 18)),
      const Text("'Thy ____ is a lamp unto my feet'"),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        ActionChip(label: const Text("Word"), onPressed: () { score += 1000; endMatch(); }),
        const SizedBox(width: 10),
        ActionChip(label: const Text("Love"), onPressed: () => endMatch()),
      ]),
    ])));
  }
}
