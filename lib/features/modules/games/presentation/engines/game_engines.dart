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
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(40), 
          side: BorderSide(color: Colors.amber.withValues(alpha: 0.2)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.crown, color: Colors.amber, size: 80),
            const SizedBox(height: 20),
            const Text("DIVINE VICTORY!", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
              child: Text("SCORE: $score", style: const TextStyle(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 30),
            _buildChestReward(),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () { 
                // Return to Hub specifically
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Exit arena
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber, 
                foregroundColor: Colors.black, 
                overlayColor: Colors.amber.shade200.withValues(alpha: 0.3),
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 10,
              ),
              child: const Text("RETURN TO HUB", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
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

// 1. Emoji Challenge (Professional Edition)
class EmojiChallengeGame extends KingdomGameEngine {
  const EmojiChallengeGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<EmojiChallengeGame> createState() => _EmojiChallengeState();
}

class _EmojiChallengeState extends KingdomGameEngineState<EmojiChallengeGame> {
  final List<Map<String, dynamic>> _data = [
    {'emojis': '🍎🐍👫', 'answer': 'Adam and Eve', 'hint': 'The first garden story'},
    {'emojis': '🚢🌊🦁', 'answer': 'Noahs Ark', 'hint': '40 days and nights'},
    {'emojis': '👑💡📜', 'answer': 'Solomon', 'hint': 'The wisest king'},
    {'emojis': '🔥🪵🐏', 'answer': 'Abraham', 'hint': 'A father of many nations'},
    {'emojis': '👴🏼🌊🏃🏾‍♂️', 'answer': 'Moses', 'hint': 'Parting the Red Sea'},
    {'emojis': '🦁🙏🏼👑', 'answer': 'Daniel', 'hint': 'The lions den'},
    {'emojis': '🐳🧔🏻🌊', 'answer': 'Jonah', 'hint': 'Swallowed by a fish'},
    {'emojis': '🏹🎯👑', 'answer': 'David', 'hint': 'Slayer of giants'},
    {'emojis': '⛪️💨🔥', 'answer': 'Pentecost', 'hint': 'The Holy Spirit decends'},
    {'emojis': '🎺🏰🧱', 'answer': 'Jericho', 'hint': 'Walls came tumbling down'},
  ];
  
  int _index = 0;
  final TextEditingController _controller = TextEditingController();
  bool _showHint = false;

  void _check() {
    String userAnswer = _controller.text.trim().toLowerCase().replaceAll("'", "");
    String correctAnswer = _data[_index]['answer'].toString().toLowerCase().replaceAll("'", "");
    
    if (userAnswer == correctAnswer) {
      setState(() {
        score += _showHint ? 50 : 100;
        if (_index < _data.length - 1) { 
          _index++; 
          _controller.clear();
          _showHint = false;
        } else { 
          endMatch(); 
        }
      });
    } else {
      // Shake animation or error feedback
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Try again, believer!"), duration: Duration(milliseconds: 500)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.5,
            colors: [Colors.amber.withValues(alpha: 0.05), Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(25),
                  child: Column(
                    children: [
                      _buildProgressIndicator(),
                      const SizedBox(height: 40),
                      _buildEmojiCard(),
                      const SizedBox(height: 40),
                      _buildAnswerSection(),
                      const SizedBox(height: 20),
                      if (_showHint) 
                        Text("HINT: ${_data[_index]['hint']}", style: const TextStyle(color: Colors.amber, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 20),
                      _buildActionButtons(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          IconButton(icon: const Icon(LucideIcons.x, color: Colors.white70), onPressed: () => Navigator.pop(context)),
          const Expanded(child: Center(child: Text("EMOJI CHALLENGE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2)))),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("SURVIVAL", style: TextStyle(color: Colors.amber.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.bold)),
            Text("${_index + 1}/${_data.length}", style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: (_index + 1) / _data.length,
            backgroundColor: Colors.white10,
            color: Colors.amber,
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _buildEmojiCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20)],
      ),
      child: Column(
        children: [
          const Text("DECODE THE REVELATION", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 20),
          Text(_data[_index]['emojis'], style: const TextStyle(fontSize: 70, shadows: [Shadow(color: Colors.amber, blurRadius: 20)])),
        ],
      ),
    );
  }

  Widget _buildAnswerSection() {
    return TextField(
      controller: _controller,
      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      textAlign: TextAlign.center,
      onSubmitted: (_) => _check(),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        hintText: "TYPE YOUR ANSWER",
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 14, letterSpacing: 2),
        contentPadding: const EdgeInsets.symmetric(vertical: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.amber, width: 2)),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _check,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 10,
            shadowColor: Colors.amber.withValues(alpha: 0.3),
          ),
          child: const Text("PROCLAIM ANSWER", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
        ),
        const SizedBox(height: 15),
        TextButton(
          onPressed: () => setState(() => _showHint = true),
          child: const Text("RECEIVE DIVINE HINT (-50 PTS)", style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// 2. Gospel Keys (Professional Edition)
class GospelKeysGame extends KingdomGameEngine {
  const GospelKeysGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<GospelKeysGame> createState() => _GospelKeysState();
}

class _GospelKeysState extends KingdomGameEngineState<GospelKeysGame> {
  final List<int> _activeKeys = [];
  Timer? _spawnTimer;
  Timer? _fallTimer;
  int _lives = 3;
  // ignore: unused_field
  double _speed = 5.0; // Fall speed

  @override
  void initState() {
    super.initState();
    _startGame();
  }

  void _startGame() {
    _spawnTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!mounted) return;
      setState(() {
        _activeKeys.add(Random().nextInt(4));
        if (score > 1000) _speed = 7.0;
        if (score > 2000) _speed = 9.0;
      });
    });
  }

  @override
  void dispose() {
    _spawnTimer?.cancel();
    _fallTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E293B),
      body: Stack(
        children: [
          Row(
            children: List.generate(4, (i) => Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.white.withValues(alpha: 0.02)],
                  ),
                ),
                child: GestureDetector(
                  onTapDown: (_) {
                    if (_activeKeys.contains(i)) {
                      setState(() {
                        score += 100;
                        _activeKeys.remove(i);
                      });
                    } else {
                      setState(() {
                        _lives--;
                        if (_lives <= 0) endMatch();
                      });
                    }
                  },
                ),
              )),
            ),
          ),
          // Fallling Tiles
          ..._buildTiles(),
          // UI Overlay
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("GOSPEL RHYTHM", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    Text(score.toString(), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                  ],
                ),
                Row(
                  children: List.generate(3, (i) => Icon(
                    LucideIcons.heart,
                    color: i < _lives ? Colors.red : Colors.white10,
                    size: 20,
                  )),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTiles() {
    // This is a simplified version of falling tiles. 
    // In a real pro version, we'd use a more complex animation system.
    return _activeKeys.map((idx) => Positioned(
      left: MediaQuery.of(context).size.width / 4 * idx,
      top: 200, // In a real version, this would animate from top to bottom
      width: MediaQuery.of(context).size.width / 4,
      height: 150,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blueAccent, Colors.purpleAccent],
          ),
          boxShadow: [BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.5), blurRadius: 10)],
        ),
        child: const Center(child: Icon(LucideIcons.music, color: Colors.white70)),
      ),
    )).toList();
  }
}

// 3. David's Sling (Professional Edition)
class DavidsSlingGame extends KingdomGameEngine {
  const DavidsSlingGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<DavidsSlingGame> createState() => _DavidsSlingState();
}

class _DavidsSlingState extends KingdomGameEngineState<DavidsSlingGame> {
  double _tx = 0.5, _ty = 0.3; 
  int _h = 0;
  bool _isHit = false;

  void _move() {
    setState(() {
      _tx = 0.1 + Random().nextDouble() * 0.8;
      _ty = 0.2 + Random().nextDouble() * 0.4;
      _isHit = false;
    });
  }

  void _onTargetTap() {
    if (_isHit) return;
    setState(() {
      score += 200;
      _h++;
      _isHit = true;
      if (_h >= 10) {
        endMatch();
      } else {
        Future.delayed(const Duration(milliseconds: 300), _move);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E1E1E), Color(0xFF000000)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.1,
                child: Image.network("https://images.unsplash.com/photo-1518709268805-4e9042af9f23?q=80&w=1000", fit: BoxFit.cover),
              ),
            ),
            _buildUI(),
            Positioned(
              left: MediaQuery.of(context).size.width * _tx - 40,
              top: MediaQuery.of(context).size.height * _ty,
              child: _buildTarget(),
            ),
            const Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Column(
                children: [
                   Icon(LucideIcons.shield, size: 100, color: Colors.brown),
                   SizedBox(height: 10),
                   Text("FAITH SHIELD ACTIVE", style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUI() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("GIANTS SLAIN", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                Text("$_h / 10", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              ],
            ),
            Text("SCORE: $score", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildTarget() {
    return GestureDetector(
      onTap: _onTargetTap,
      child: AnimatedScale(
        scale: _isHit ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red.withValues(alpha: 0.5), width: 2),
              ),
              child: const Icon(LucideIcons.flame, size: 60, color: Colors.orange),
            ),
            const SizedBox(height: 5),
            const Text("GOLIATH", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
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
  final List<String> _guessed = [];
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
        setState(() { _selTxt = t; if (_selRef != null) { score += 500; if (score >= 1500) {
          endMatch();
        } else { _selRef = null; _selTxt = null; } } });
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
  final List<String> _words = ["Faith", "Hope", "Love", "Grace", "Sin"];
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.blue.shade900, body: Stack(children: _words.map((w) => Positioned(
      left: Random().nextDouble() * 300, top: Random().nextDouble() * 600,
      child: ActionChip(label: Text(w), onPressed: () {
        setState(() { if (w != "Sin") {
          score += 300;
        } else {
          score -= 500;
        } _words.remove(w); if (_words.isEmpty) endMatch(); });
      }),
    )).toList()));
  }
}

// 8. Jericho Breaker (Professional Edition)
class JerichoBreakerGame extends KingdomGameEngine {
  const JerichoBreakerGame({super.key, required super.game, required super.level, required super.isSolo, super.opponentName});
  @override
  State<JerichoBreakerGame> createState() => _JerichoBreakerState();
}

class _JerichoBreakerState extends KingdomGameEngineState<JerichoBreakerGame> {
  int _hp = 20;
  final int _maxHp = 20;
  bool _isShaking = false;

  void _shout() {
    if (isGameOver) return;
    setState(() {
      _hp--;
      score += 50;
      _isShaking = true;
      if (_hp <= 0) endMatch();
    });
    Future.delayed(const Duration(milliseconds: 100), () => setState(() => _isShaking = false));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.orange.withValues(alpha: 0.1), Colors.black],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              const Spacer(),
              _buildCastle(),
              const Spacer(),
              _buildHPBar(),
              const SizedBox(height: 50),
              _buildShoutButton(),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: const Icon(LucideIcons.x, color: Colors.white70), onPressed: () => Navigator.pop(context)),
              Text("JERICHO BREAKER", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 10),
          Text("SCORE: $score", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCastle() {
    return Transform.translate(
      offset: _isShaking ? Offset(Random().nextDouble() * 10 - 5, Random().nextDouble() * 10 - 5) : Offset.zero,
      child: const Icon(LucideIcons.castle, size: 180, color: Colors.brown),
    );
  }

  Widget _buildHPBar() {
    return Column(
      children: [
        const Text("WALL STABILITY", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 15),
        Container(
          width: 250,
          height: 15,
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white24)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _hp / _maxHp,
              backgroundColor: Colors.transparent,
              color: _hp < 5 ? Colors.red : Colors.orange,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text("${((_hp / _maxHp) * 100).toInt()}%", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildShoutButton() {
    return GestureDetector(
      onTap: _shout,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.amber,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.amber.withValues(alpha: 0.5), blurRadius: 30, spreadRadius: 5),
          ],
        ),
        child: const Icon(LucideIcons.volume2, size: 60, color: Colors.black),
      ),
    );
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
  final List<int> _p = [0, 2, 1, 3], _u = [];
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
      const Text("'I was lost but now I'm found...'"),
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

