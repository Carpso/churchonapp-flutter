import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../data/bible_quiz_service.dart';
import '../data/quiz_event_service.dart';
import 'bible_quiz_results_screen.dart';

enum GamePhase { matchmaking, countdown, playing, answering, feedback, review, finished }

class BibleQuizArenaScreen extends ConsumerStatefulWidget {
  final String mode;
  final int questionCount;
  final String? eventId;
  final int timePerQuestionSec;
  final String? categoryFilter;
  final String? difficultyFilter;

  const BibleQuizArenaScreen({
    super.key,
    this.mode = 'Solo',
    this.questionCount = 10,
    this.eventId,
    this.timePerQuestionSec = 15,
    this.categoryFilter,
    this.difficultyFilter,
  });

  @override
  ConsumerState<BibleQuizArenaScreen> createState() => _BibleQuizArenaScreenState();
}

class _BibleQuizArenaScreenState extends ConsumerState<BibleQuizArenaScreen>
    with SingleTickerProviderStateMixin {
  late final BibleQuizService _service;

  GamePhase _phase = GamePhase.matchmaking;
  List<QuizQuestion> _questions = [];
  int _currentIndex = 0;
  int? _selectedAnswer;
  int? _fiftyFiftyIndex; // tracks which 50:50 was used (question index)
  final Set<int> _eliminatedOptions = {};
  int _score = 0;
  int _streak = 0;
  int _bestStreak = 0;
  int _powerUpsUsed = 0;
  bool _fiftyFiftyUsed = false;
  bool _skipUsed = false;
  bool _doubleUsed = false;
  bool _timeFreezeUsed = false;

  final List<int?> _answers = [];
  final List<int> _responseTimesMs = [];

  late int _timerMs;
  final int _timerIntervalMs = 50;
  int? _startTime;
  Timer? _timer;
  Timer? _countdownTimer;
  int _countdownValue = 3;

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  // Opponent score simulation (P2P)
  int _opponentScore = 0;

  // Matchmaking avatar cycling
  Timer? _avatarCycleTimer;
  final List<String> _matchmakingAvatars = List.generate(
    20,
    (i) => 'https://i.pravatar.cc/150?img=${i + 1}',
  );
  int _currentAvatarIndex = 0;

  @override
  void initState() {
    super.initState();
    _timerMs = widget.timePerQuestionSec * 1000;
    _service = BibleQuizService();
    _startAvatarCycling();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _loadQuestions();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    _avatarCycleTimer?.cancel();
    _slideController.dispose();
    super.dispose();
  }

  void _startAvatarCycling() {
    _avatarCycleTimer = Timer.periodic(const Duration(milliseconds: 400), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _currentAvatarIndex = (_currentAvatarIndex + 1) % _matchmakingAvatars.length;
      });
    });
  }

  void _stopAvatarCycling() {
    _avatarCycleTimer?.cancel();
    _avatarCycleTimer = null;
  }

  Future<void> _loadQuestions() async {
    final questions = await _service.getRandomQuestions(
      widget.questionCount,
      category: widget.categoryFilter,
      difficulty: widget.difficultyFilter,
    );
    if (!mounted) return;

    _stopAvatarCycling();
    setState(() {
      _questions = questions;
      _answers.clear();
      _responseTimesMs.clear();
      for (int i = 0; i < questions.length; i++) {
        _answers.add(null);
        _responseTimesMs.add(0);
      }
      _phase = GamePhase.countdown;
    });
    _startCountdown();
  }

  void _startCountdown() {
    _countdownValue = 3;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_countdownValue <= 1) {
        t.cancel();
        setState(() => _phase = GamePhase.playing);
        _startTimer();
      } else {
        setState(() => _countdownValue--);
      }
    });
  }

  void _startTimer() {
    _timerMs = widget.timePerQuestionSec * 1000;
    _startTime = DateTime.now().millisecondsSinceEpoch;
    _timer = Timer.periodic(Duration(milliseconds: _timerIntervalMs), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_timerMs <= 0) {
        t.cancel();
        _timeUp();
      } else {
        if (mounted) setState(() => _timerMs -= _timerIntervalMs);
      }
    });
  }

  void _timeUp() {
    if (_phase != GamePhase.playing) return;
    _submitAnswer(-1); // -1 means skipped
  }

  void _selectAnswer(int idx) {
    if (_phase != GamePhase.playing) return;
    if (_eliminatedOptions.contains(idx)) return;

    _submitAnswer(idx);
  }

  void _submitAnswer(int idx) {
    _timer?.cancel();
    final elapsed = _startTime != null
        ? DateTime.now().millisecondsSinceEpoch - _startTime!
        : 0;

    setState(() {
      _selectedAnswer = idx;
      _phase = GamePhase.answering;
    });

    final isCorrect = idx >= 0 && _questions[_currentIndex].correctAnswer == idx;

    // Wait a moment to show feedback, then advance
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _answers[_currentIndex] = idx;
        _responseTimesMs[_currentIndex] = elapsed;

        if (isCorrect) {
          int pts = _questions[_currentIndex].points;
          if (_doubleUsed) pts *= 2;
          _score += pts;
          _streak++;
          if (_streak > _bestStreak) _bestStreak = _streak;
          // streak bonus: every 3+ streak gives +5 extra
          if (_streak >= 3) _score += 5;
        } else {
          _streak = 0;
        }

        // Reset per-question power-ups
        _eliminatedOptions.clear();
        _doubleUsed = false;
        if (_fiftyFiftyIndex == _currentIndex) _fiftyFiftyIndex = null;

        // P2P: simulate opponent scoring
        if (widget.mode != 'Solo') {
          if (Random().nextInt(100) < 55) _opponentScore += 10;
        }

        _phase = GamePhase.feedback;
      });

      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _nextQuestion();
      });
    });
  }

  void _nextQuestion() {
    if (_currentIndex + 1 >= _questions.length) {
      setState(() => _phase = GamePhase.finished);
      return;
    }

    _slideController.reset();
    setState(() {
      _currentIndex++;
      _selectedAnswer = null;
      _phase = GamePhase.playing;
      _timerMs = 15000;
    });

    _slideController.forward();
    _startTimer();
  }

  void _useFiftyFifty() {
    if (_fiftyFiftyUsed) return;
    final q = _questions[_currentIndex];
    final correct = q.correctAnswer;
    final others = <int>[];
    for (int i = 0; i < q.options.length; i++) {
      if (i != correct) others.add(i);
    }
    others.shuffle();
    // Eliminate 2 wrong options (or at least 1 if only 2 options)
    final removeCount = others.length >= 2 ? 2 : others.length;
    for (int i = 0; i < removeCount; i++) {
      _eliminatedOptions.add(others[i]);
    }
    _fiftyFiftyUsed = true;
    _fiftyFiftyIndex = _currentIndex;
    _powerUpsUsed++;
    setState(() {});
  }

  void _useSkip() {
    if (_skipUsed) return;
    _skipUsed = true;
    _powerUpsUsed++;
    _timer?.cancel();
    _answers[_currentIndex] = -1;
    _responseTimesMs[_currentIndex] =
        _startTime != null ? DateTime.now().millisecondsSinceEpoch - _startTime! : 0;
    _streak = 0;

    setState(() => _phase = GamePhase.feedback);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _nextQuestion();
    });
  }

  void _useDoublePoints() {
    if (_doubleUsed) return;
    _doubleUsed = true;
    _powerUpsUsed++;
    setState(() {});
  }

  void _useTimeFreeze() {
    if (_timeFreezeUsed) return;
    _timeFreezeUsed = true;
    _powerUpsUsed++;
    _timerMs = 15000;
    setState(() {});
  }

  Color _timerColor() {
    final ratio = _timerMs / 15000;
    if (ratio > 0.5) return Colors.greenAccent;
    if (ratio > 0.25) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  Future<void> _goToResults() async {
    final results = QuizSessionResult(
      questions: _questions,
      answers: _answers,
      responseTimesMs: _responseTimesMs,
      streak: _bestStreak,
      powerUpsUsed: _powerUpsUsed,
    );

    // Submit score to event if in event mode
    if (widget.eventId != null) {
      int correctCount = 0;
      for (int i = 0; i < _answers.length; i++) {
        if (_answers[i] == _questions[i].correctAnswer) correctCount++;
      }
      try {
        await ref.read(quizEventServiceProvider).submitEventScore(
          eventId: widget.eventId!,
          score: _score,
          correctCount: correctCount,
          totalQuestions: _questions.length,
        );
      } catch (e) {
        debugPrint('Failed to submit quiz event score: $e');
      }
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BibleQuizResultsScreen(result: results),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: _phase == GamePhase.matchmaking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase != GamePhase.matchmaking) {
          _showQuitConfirm(theme);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        body: SafeArea(
          child: _buildBody(theme),
        ),
      ),
    );
  }

  void _showQuitConfirm(ThemeData theme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Quit Quiz?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your progress will be lost.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Keep Playing'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _timer?.cancel();
              if (mounted) Navigator.of(context).pop();
            },
            child: const Text('Quit', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_phase) {
      case GamePhase.matchmaking:
        return _buildMatchmaking(theme);
      case GamePhase.countdown:
        return _buildCountdown(theme);
      case GamePhase.playing:
      case GamePhase.answering:
      case GamePhase.feedback:
        return _buildGameplay(theme);
      case GamePhase.finished:
        return _buildFinished(theme);
      case GamePhase.review:
        return _buildReview(theme);
    }
  }

  Widget _buildMatchmaking(ThemeData theme) {
    final quizType = widget.categoryFilter ?? 'General';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 100, height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 100, height: 100,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: theme.primaryColor,
                    backgroundColor: theme.primaryColor.withAlpha(40),
                  ),
                ),
                Text(_categoryEmoji(quizType), style: const TextStyle(fontSize: 40)),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            widget.mode == 'Solo' ? 'Preparing Questions…' : 'Finding Opponent…',
            style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.mode == 'Solo'
                ? 'Curating $quizType questions for you'
                : 'Searching for a worthy challenger',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          if (widget.mode != 'Solo') ...[
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: NetworkImage(_matchmakingAvatars[_currentAvatarIndex]),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text('VS', style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.w900)),
                ),
                CircleAvatar(
                  radius: 28,
                  backgroundImage: NetworkImage(_matchmakingAvatars[(_currentAvatarIndex + 5) % _matchmakingAvatars.length]),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _categoryEmoji(String category) {
    const emojis = {
      'People': '🧑‍🤝‍🧑',
      'History': '📜',
      'Miracles': '🌟',
      'Prophecy': '🔮',
      'Scripture': '📖',
      'Law': '⚖️',
      'NT': '✝️',
      'OT': '📜',
      'Angels': '👼',
      'Language': '📝',
    };
    return emojis[category] ?? '📖';
  }

  Widget _buildCountdown(ThemeData theme) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(seconds: 1),
        builder: (context, value, child) {
          return Transform.scale(
            scale: 1 + value * 0.3,
            child: Opacity(
              opacity: value > 0.5 ? 1 : 0,
              child: Text(
                '$_countdownValue',
                style: TextStyle(
                  fontSize: 100 - value * 40,
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                  shadows: [
                    Shadow(
                      color: theme.primaryColor.withAlpha(100),
                      blurRadius: 30,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGameplay(ThemeData theme) {
    final q = _questions[_currentIndex];
    final progress = _currentIndex / _questions.length;

    return Column(
      children: [
        // Top bar: progress + score + streak + timer
        _buildTopBar(theme, progress),
        const SizedBox(height: 8),
        // Question card
        Expanded(
          child: SlideTransition(
            position: _slideAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Category + difficulty badges
                  _buildBadges(theme, q),
                  const SizedBox(height: 16),
                  // Scripture reference
                  if (q.scriptureReference != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        q.scriptureReference!,
                        style: TextStyle(
                          color: theme.primaryColor.withAlpha(180),
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  // Question text
                  Text(
                    q.question,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  // Options grid
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return GridView.count(
                          crossAxisCount: 2,
                          childAspectRatio: constraints.maxWidth > 400 ? 2.2 : 1.6,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          physics: const NeverScrollableScrollPhysics(),
                          children: List.generate(q.options.length, (i) {
                            if (_eliminatedOptions.contains(i)) {
                              return _buildEliminatedOption(theme, q.options[i], i);
                            }
                            return _buildOption(theme, q, i);
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Power-ups bar
        _buildPowerUps(theme),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTopBar(ThemeData theme, double progress) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          // Exit + question counter + opponent (P2P)
          Row(
            children: [
              // Exit button
              GestureDetector(
                onTap: () => _showQuitConfirm(theme),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(LucideIcons.x, color: Colors.white54, size: 20),
                ),
              ),
              const Spacer(),
              // Question counter
              Text(
                '${_currentIndex + 1} / ${_questions.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              if (widget.mode != 'Solo') ...[
                const SizedBox(width: 16),
                // Opponent score
                Row(
                  children: [
                    Icon(LucideIcons.user, size: 14, color: Colors.orangeAccent),
                    const SizedBox(width: 4),
                    Text(
                      '$_opponentScore',
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
              const Spacer(),
              // Score
              Row(
                children: [
                  Icon(LucideIcons.star, size: 16, color: theme.primaryColor),
                  const SizedBox(width: 4),
                  Text(
                    '$_score',
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withAlpha(20),
              valueColor: AlwaysStoppedAnimation(theme.primaryColor),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 8),
          // Timer + Streak
          Row(
            children: [
              // Timer ring
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        value: _timerMs / 15000,
                        strokeWidth: 3,
                        color: _timerColor(),
                        backgroundColor: Colors.white.withAlpha(15),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${(_timerMs / 1000).toStringAsFixed(1)}s',
                      style: TextStyle(
                        color: _timerColor(),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Streak indicator
              if (_streak >= 2)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _streak >= 5 ? LucideIcons.zap : LucideIcons.trendingUp,
                      size: 16,
                      color: _streak >= 5 ? Colors.orangeAccent : Colors.greenAccent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_streak}x',
                      style: TextStyle(
                        color: _streak >= 5 ? Colors.orangeAccent : Colors.greenAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadges(ThemeData theme, QuizQuestion q) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _badge(q.category, theme.primaryColor, theme),
        const SizedBox(width: 8),
        _badge(q.difficulty, _difficultyColor(q.difficulty), theme),
      ],
    );
  }

  Widget _badge(String text, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Color _difficultyColor(String diff) {
    switch (diff) {
      case 'Easy':
        return Colors.greenAccent;
      case 'Medium':
        return Colors.amberAccent;
      case 'Hard':
        return Colors.redAccent;
      default:
        return Colors.blueAccent;
    }
  }

  Widget _buildOption(ThemeData theme, QuizQuestion q, int i) {
    final bool isRevealingAnswer = _phase == GamePhase.answering || _phase == GamePhase.feedback;
    final bool isCorrect = isRevealingAnswer && q.correctAnswer == i;
    final bool isWrong = isRevealingAnswer && _selectedAnswer == i && !isCorrect;
    final bool isSelected = _selectedAnswer == i;
    final bool isDisabled = _phase != GamePhase.playing;

    Color bgColor = Colors.white.withAlpha(10);
    Color borderColor = Colors.white.withAlpha(25);
    Color textColor = Colors.white;

    if (isCorrect) {
      bgColor = Colors.greenAccent.withAlpha(30);
      borderColor = Colors.greenAccent;
      textColor = Colors.greenAccent;
    } else if (isWrong) {
      bgColor = Colors.redAccent.withAlpha(30);
      borderColor = Colors.redAccent;
      textColor = Colors.redAccent;
    } else if (isSelected && isRevealingAnswer) {
      bgColor = Colors.orangeAccent.withAlpha(30);
      borderColor = Colors.orangeAccent;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: isDisabled ? null : () => _selectAnswer(i),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isCorrect)
                    const Icon(LucideIcons.checkCircle, size: 16, color: Colors.greenAccent)
                  else if (isWrong)
                    const Icon(LucideIcons.xCircle, size: 16, color: Colors.redAccent),
                  if (isCorrect || isWrong) const SizedBox(width: 6),
                  Text(
                    q.options[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEliminatedOption(ThemeData theme, String text, int i) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      alignment: Alignment.center,
      child: const Text('???', style: TextStyle(color: Colors.white24, fontSize: 16)),
    );
  }

  Widget _buildPowerUps(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _powerUpButton(
            icon: LucideIcons.gitBranch,
            label: '50:50',
            used: _fiftyFiftyUsed,
            onTap: _useFiftyFifty,
            color: Colors.blueAccent,
          ),
          _powerUpButton(
            icon: LucideIcons.skipForward,
            label: 'Skip',
            used: _skipUsed,
            onTap: _useSkip,
            color: Colors.purpleAccent,
          ),
          _powerUpButton(
            icon: LucideIcons.dice2,
            label: '2x',
            used: _doubleUsed,
            onTap: _useDoublePoints,
            color: Colors.orangeAccent,
          ),
          _powerUpButton(
            icon: LucideIcons.clock,
            label: 'Freeze',
            used: _timeFreezeUsed,
            onTap: _useTimeFreeze,
            color: Colors.tealAccent,
          ),
        ],
      ),
    );
  }

  Widget _powerUpButton({
    required IconData icon,
    required String label,
    required bool used,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: used ? null : onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: used ? 0.3 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: used ? Colors.white.withAlpha(8) : color.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: used ? Colors.white.withAlpha(15) : color.withAlpha(80),
                ),
              ),
              child: Icon(icon, size: 18, color: used ? Colors.white38 : color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: used ? Colors.white38 : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinished(ThemeData theme) {
    int correctCount = 0;
    for (int i = 0; i < _answers.length; i++) {
      if (_answers[i] == _questions[i].correctAnswer) correctCount++;
    }
    final accuracy = _questions.isEmpty
        ? 0.0
        : correctCount / _questions.length;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Trophy icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accuracy >= 0.8
                    ? Colors.amber.withAlpha(40)
                    : accuracy >= 0.5
                        ? Colors.blueGrey.withAlpha(40)
                        : Colors.white.withAlpha(15),
              ),
              child: Icon(
                accuracy >= 0.8
                    ? LucideIcons.trophy
                    : accuracy >= 0.5
                        ? LucideIcons.award
                        : LucideIcons.target,
                size: 40,
                color: accuracy >= 0.8
                    ? Colors.amberAccent
                    : accuracy >= 0.5
                        ? Colors.blueGrey
                        : Colors.white54,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              accuracy >= 0.8
                  ? 'Excellent!'
                  : accuracy >= 0.5
                      ? 'Good Job!'
                      : 'Keep Learning!',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            // Score
            Text(
              '$_score pts',
              style: TextStyle(
                color: theme.primaryColor,
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            // Stats grid
            _buildStatsGrid(theme, correctCount, accuracy),
            const SizedBox(height: 24),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.home, size: 18),
                    label: const Text('Home'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _goToResults,
                    icon: const Icon(LucideIcons.barChart3, size: 18),
                    label: const Text('Details'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(ThemeData theme, int correctCount, double accuracy) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem(LucideIcons.checkCheck, '$correctCount', 'Correct', Colors.greenAccent),
              _statItem(
                LucideIcons.x,
                '${_questions.length - correctCount}',
                'Wrong',
                Colors.redAccent,
              ),
              _statItem(
                LucideIcons.target,
                '${(accuracy * 100).toInt()}%',
                'Accuracy',
                theme.primaryColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem(
                LucideIcons.trendingUp,
                '$_bestStreak',
                'Best Streak',
                Colors.orangeAccent,
              ),
              _statItem(
                LucideIcons.zap,
                '$_powerUpsUsed',
                'Power-ups',
                Colors.purpleAccent,
              ),
              _statItem(
                LucideIcons.clock,
                _avgTimeText(),
                'Avg Time',
                Colors.tealAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _avgTimeText() {
    if (_responseTimesMs.isEmpty) return '0s';
    final avg = _responseTimesMs.reduce((a, b) => a + b) ~/ _responseTimesMs.length;
    return '${(avg / 1000).toStringAsFixed(1)}s';
  }

  Widget _statItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildReview(ThemeData theme) {
    return Column(
      children: [
        // Top bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _phase = GamePhase.finished),
                child: const Icon(LucideIcons.chevronLeft, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Review Questions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _questions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final q = _questions[i];
              final answer = _answers[i];
              final isCorrect = answer == q.correctAnswer;
              Color borderColor;
              if (answer == null || answer < 0) {
                borderColor = Colors.orangeAccent;
              } else if (isCorrect) {
                borderColor = Colors.greenAccent;
              } else {
                borderColor = Colors.redAccent;
              }

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor.withAlpha(80)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: Q number + category + result
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: borderColor.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Q${i + 1}',
                            style: TextStyle(
                              color: borderColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          q.category,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const Spacer(),
                        Icon(
                          answer == null || answer < 0
                              ? LucideIcons.alertCircle
                              : isCorrect
                                  ? LucideIcons.checkCircle
                                  : LucideIcons.xCircle,
                          size: 16,
                          color: borderColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      q.question,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Options
                    ...List.generate(q.options.length, (optIdx) {
                      final isCorrectOpt = q.correctAnswer == optIdx;
                      final isUserAnswer = answer == optIdx;
                      Color optColor = Colors.white54;
                      IconData? leading;
                      if (isCorrectOpt) {
                        optColor = Colors.greenAccent;
                        leading = LucideIcons.check;
                      } else if (isUserAnswer && !isCorrectOpt) {
                        optColor = Colors.redAccent;
                        leading = LucideIcons.x;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            if (leading != null)
                              Icon(leading, size: 14, color: optColor),
                            if (leading != null)
                              const SizedBox(width: 6),
                            Text(
                              q.options[optIdx],
                              style: TextStyle(color: optColor, fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (q.scriptureReference != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        q.scriptureReference!,
                        style: TextStyle(
                          color: theme.primaryColor.withAlpha(150),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
