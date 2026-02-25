import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/bible_quiz_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class BibleQuizArenaScreen extends ConsumerStatefulWidget {
  final String mode;
  const BibleQuizArenaScreen({super.key, required this.mode});

  @override
  ConsumerState<BibleQuizArenaScreen> createState() => _BibleQuizArenaScreenState();
}

class _BibleQuizArenaScreenState extends ConsumerState<BibleQuizArenaScreen> {
  bool _isSearching = true;
  String? _opponentName;
  String? _opponentAvatar;
  int _countdown = 3;
  bool _matchStarted = false;
  int _currentQuestionIndex = 0;
  int _myScore = 0;
  int _oppScore = 0;
  List<QuizQuestion> _questions = [];

  @override
  void initState() {
    super.initState();
    _findMatch();
  }

  Future<void> _findMatch() async {
    final service = ref.read(bibleQuizServiceProvider);
    _questions = await service.getRandomQuestions(5);
    
    final opponent = await service.findOpponent();
    
    if (mounted) {
      setState(() {
        _isSearching = false;
        _opponentName = opponent['name'];
        _opponentAvatar = opponent['avatar'];
      });
      _startCountdown();
    }
  }

  void _startCountdown() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown == 1) {
        timer.cancel();
        setState(() => _matchStarted = true);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _submitAnswer(String option) {
    bool isCorrect = option == _questions[_currentQuestionIndex].options[_questions[_currentQuestionIndex].correctAnswer];
    
    if (isCorrect) {
      setState(() => _myScore += 100);
      
      // Auto-Progression Logic: Level up after every 500 points
      if (_myScore % 500 == 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("LEVEL UP! Difficulty increased.", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.amber,
          duration: Duration(seconds: 1),
        ));
      }
    }
    
    // Simulate opponent scoring
    if (DateTime.now().millisecond % 4 == 0) {
      setState(() => _oppScore += 100);
    }

    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() => _currentQuestionIndex++);
    } else {
      // Fetch more questions for 'Infinite Play' or show results
      if (_myScore > 1000) {
        _showResults();
      } else {
        _fetchMoreQuestions();
      }
    }
  }

  Future<void> _fetchMoreQuestions() async {
    final service = ref.read(bibleQuizServiceProvider);
    final more = await service.getRandomQuestions(5);
    setState(() {
      _questions.addAll(more);
      _currentQuestionIndex++;
    });
  }

  void _showResults() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: Center(child: Text(_myScore >= _oppScore ? "VICTORY!" : "DEFEAT", style: TextStyle(color: _myScore >= _oppScore ? Colors.greenAccent : Colors.redAccent, fontSize: 24, fontWeight: FontWeight.w900))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.trophy, color: _myScore >= _oppScore ? Colors.amber : Colors.grey, size: 60),
            const SizedBox(height: 20),
            Text("Your Score: $_myScore", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text("Opponent Score: $_oppScore", style: const TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 10),
            Text(_myScore >= _oppScore ? "+50 Church Coins Earned" : "Try again to earn rewards!", style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            if (_myScore >= _oppScore)
              const Text("(Activity-only tokens)", style: TextStyle(color: Colors.white24, fontSize: 8)),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                if (_myScore >= _oppScore) {
                  ref.read(profileProvider.notifier).addCoins(50);
                }
                Navigator.pop(context);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("EXIT ARENA", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6A11CB), Color(0xFF1E1E2C)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: _matchStarted ? _buildQuizGame() : _buildMatchmaking(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(LucideIcons.chevronLeft, color: Colors.white), onPressed: () => Navigator.pop(context)),
          const Text("BIBLE QUIZ ARENA", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 4)),
          const Icon(LucideIcons.radio, color: Colors.redAccent, size: 20),
        ],
      ),
    );
  }

  Widget _buildMatchmaking() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPlayerCircle("You", "https://i.pravatar.cc/150?u=me", isMe: true),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text("VS", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
            ),
            _isSearching ? _buildSearchingLoader() : _buildPlayerCircle(_opponentName!, _opponentAvatar!),
          ],
        ),
        const SizedBox(height: 80),
        if (_isSearching) ...[
          const Text("SEARCHING FOR MATCH...", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
          Text("Mode: ${widget.mode}", style: const TextStyle(color: Colors.white30, fontSize: 10)),
          const SizedBox(height: 20),
          const CircularProgressIndicator(color: Colors.white),
        ] else ...[
          const Text("MATCH FOUND!", style: TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Text("Starting in $_countdown...", style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900)),
        ],
      ],
    );
  }

  Widget _buildQuizGame() {
    final q = _questions[_currentQuestionIndex];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildScoreTile("YOU", _myScore, Colors.blueAccent),
              _buildScoreTile(_opponentName!.toUpperCase(), _oppScore, Colors.pinkAccent),
            ],
          ),
        ),
        const SizedBox(height: 40),
        Container(
          height: 180,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 25),
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(color: Colors.white.withAlpha(13), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white12)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(q.category.toUpperCase(), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 2)),
              const SizedBox(height: 15),
              Text(q.question, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, height: 1.4)),
            ],
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            children: q.options.map((opt) => _buildOptionButton(opt)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildScoreTile(String name, int score, Color color) {
    return Column(
      children: [
        Text(name, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        Text(score.toString(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildOptionButton(String option) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _submitAnswer(option),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
          child: Text(option, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildPlayerCircle(String name, String avatar, {bool isMe = false}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: isMe ? Colors.blueAccent : Colors.pinkAccent, width: 3)),
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
        Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)), child: const Center(child: Icon(LucideIcons.user, color: Colors.white24, size: 40))),
        const SizedBox(height: 15),
        const Text("???", style: TextStyle(color: Colors.white24, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

