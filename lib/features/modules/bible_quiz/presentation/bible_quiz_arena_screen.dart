import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/bible_quiz_service.dart';
import '../data/daily_challenge_service.dart';
import '../data/pvp_service.dart';
import '../data/quiz_event_service.dart';
import '../../../../core/providers/profile_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../bible/presentation/scripture_audio_button.dart';
import '../../../bible/presentation/live_scripture_text.dart';
import 'bible_quiz_results_screen.dart';

enum GamePhase { matchmaking, vsReveal, countdown, playing, answering, feedback, review, finished }

/// Competitive play styles (Solo). Each tweaks timer, question count, scoring.
enum QuizStyle { classic, rapidFire, marathon, suddenDeath, blitz }

extension QuizStyleX on QuizStyle {
  String get label {
    switch (this) {
      case QuizStyle.rapidFire:
        return 'Rapid Fire';
      case QuizStyle.marathon:
        return 'Marathon';
      case QuizStyle.suddenDeath:
        return 'Last Stand';
      case QuizStyle.blitz:
        return 'Blitz';
      case QuizStyle.classic:
        return 'Classic';
    }
  }

  String get description {
    switch (this) {
      case QuizStyle.rapidFire:
        return '8s per question · 15 Qs · 2× points';
      case QuizStyle.marathon:
        return '12s per question · 40 Qs · big streaks';
      case QuizStyle.suddenDeath:
        return '10s per question · 1 mistake ends the run';
      case QuizStyle.blitz:
        return '10s per question · 90s total clock';
      case QuizStyle.classic:
        return 'Standard timed rounds';
    }
  }

  int get defaultSeconds {
    switch (this) {
      case QuizStyle.rapidFire:
        return 8;
      case QuizStyle.marathon:
        return 12;
      case QuizStyle.suddenDeath:
        return 10;
      case QuizStyle.blitz:
        return 10;
      case QuizStyle.classic:
        return 15;
    }
  }

  int get defaultCount {
    switch (this) {
      case QuizStyle.rapidFire:
        return 15;
      case QuizStyle.marathon:
        return 40;
      case QuizStyle.suddenDeath:
        return 25;
      case QuizStyle.blitz:
        return 30;
      case QuizStyle.classic:
        return 10;
    }
  }

  int get pointsMultiplier {
    switch (this) {
      case QuizStyle.rapidFire:
        return 2;
      default:
        return 1;
    }
  }

  int get streakBonus {
    switch (this) {
      case QuizStyle.marathon:
        return 10;
      default:
        return 5;
    }
  }
}

class BibleQuizArenaScreen extends ConsumerStatefulWidget {
  final String mode;
  final int questionCount;
  final String? eventId;
  final int timePerQuestionSec;
  final String? categoryFilter;
  final String? difficultyFilter;
  final PvPMatch? initialPvPMatch;
  final WagerTier wagerTier;
  final QuizStyle style;

  const BibleQuizArenaScreen({
    super.key,
    this.mode = 'Solo',
    this.questionCount = 10,
    this.eventId,
    this.timePerQuestionSec = 15,
    this.categoryFilter,
    this.difficultyFilter,
    this.initialPvPMatch,
    this.wagerTier = WagerTier.free,
    this.style = QuizStyle.classic,
  });

  @override
  ConsumerState<BibleQuizArenaScreen> createState() => _BibleQuizArenaScreenState();
}

class _BibleQuizArenaScreenState extends ConsumerState<BibleQuizArenaScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final BibleQuizService _service;
  PvPService? _pvpService;

  GamePhase _phase = GamePhase.matchmaking;
  List<QuizQuestion> _questions = [];
  int _currentIndex = 0;
  int? _selectedAnswer;
  final Set<int> _selectedAnswers = {};
  int? _fiftyFiftyIndex;
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
  final int _timerIntervalMs = 120;
  int? _startTime;
  Timer? _timer;
  Timer? _countdownTimer;
  int _countdownValue = 3;

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  // VS Reveal Animations
  late AnimationController _vsController;
  late Animation<double> _vsScaleAnimation;
  late Animation<Offset> _player1SlideAnimation;
  late Animation<Offset> _player2SlideAnimation;

  int _opponentScore = 0;
  PvPMatch? _pvpMatch;
  Map<String, dynamic>? _p1Profile;
  Map<String, dynamic>? _p2Profile;

  /// When no human opponent joins, Kael AI steps in as the challenger.
  bool _kaelOpponent = false;
  final Random _random = Random();

  // Anti-cheat: track if app was backgrounded during a question
  bool _wasBackgroundedDuringQuestion = false;

  bool _loadingTimedOut = false;
  bool _loadingError = false;
  bool _isQuitting = false;

  // Rematch state
  bool _rematchRequested = false;

  // Style helpers
  int get _effectiveTimePerQuestionSec =>
      widget.style != QuizStyle.classic ? widget.style.defaultSeconds : widget.timePerQuestionSec;

  int? _blitzStartedAt;
  bool _suddenDeathOut = false;
  static const int _blitzTotalMs = 90 * 1000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timerMs = _effectiveTimePerQuestionSec * 1000;
    _service = BibleQuizService();
    if (widget.mode != 'Solo') {
      _pvpService = PvPService();
    }
    
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _vsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _vsScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _vsController, curve: const Interval(0.4, 1.0, curve: Curves.elasticOut)),
    );
    _player1SlideAnimation = Tween<Offset>(begin: const Offset(-1.5, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _vsController, curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic)),
    );
    _player2SlideAnimation = Tween<Offset>(begin: const Offset(1.5, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _vsController, curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic)),
    );

    _loadQuestions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _countdownTimer?.cancel();
    _slideController.dispose();
    _vsController.dispose();
    try {
      _pvpService?.disconnect();
    } catch (e) {
      debugPrint('Error disconnecting PvP service: $e');
    }
    super.dispose();
  }

  // ── Anti-cheat: detect app backgrounding during active question ──
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.mode == 'Solo') return;
    if (_phase != GamePhase.playing) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _wasBackgroundedDuringQuestion = true;
      debugPrint('[PvP Anti-Cheat] App backgrounded during question $_currentIndex — flagging as zero points');
    }
  }

  QuizQuestion _shuffleQuestionOptions(QuizQuestion q) {
    final correctValue = q.options[q.correctAnswer];
    final shuffled = List<String>.from(q.options)..shuffle();
    final newIndex = shuffled.indexOf(correctValue);
    return QuizQuestion(
      id: q.id,
      question: q.question,
      options: shuffled,
      correctAnswer: newIndex,
      difficulty: q.difficulty,
      category: q.category,
      scriptureReference: q.scriptureReference,
      style: q.style,
      points: q.points,
      isSuperadminOnly: q.isSuperadminOnly,
    );
  }

  Future<Map<String, dynamic>?> _fetchPlayerDetail(String userId) async {
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('full_name, avatar_url, tenant_id')
          .eq('id', userId)
          .maybeSingle();
      if (res == null) return null;
      String churchName = 'Independent';
      final tenantId = res['tenant_id']?.toString();
      if (tenantId != null && tenantId.isNotEmpty) {
        try {
          final tenant = await Supabase.instance.client
              .from('tenants')
              .select('name')
              .filter('id::text', 'eq', tenantId)
              .maybeSingle();
          churchName = tenant?['name']?.toString() ?? 'Independent';
        } catch (e) {
          debugPrint('Error fetching player church: $e');
        }
      }
      return {
        'name': res['full_name'] ?? 'Believer',
        'avatar': res['avatar_url'] ?? '',
        'church': churchName,
      };
    } catch (e) {
      debugPrint('Error fetching player detail: $e');
      return null;
    }
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _loadingTimedOut = false;
      _loadingError = false;
    });

    // For PvP mode, find or create a match first
    if (widget.mode != 'Solo' && _pvpService != null) {
      try {
        // Invited match passed in (deep link or in-app invite accept):
        // never re-run matchmaking — use (and accept) the invited match.
        final provided = widget.initialPvPMatch;
        var match = provided;
        if (provided != null && provided.status == 'invited' && provided.player2Id == _pvpService!.currentUserId) {
          final accepted = await _pvpService!.acceptInvite(provided.id);
          if (accepted != null) match = accepted;
        }
        match ??= await _pvpService!.findOrCreateMatch(
          questionCount: widget.questionCount,
          timePerQuestion: widget.timePerQuestionSec,
          wagerTier: widget.wagerTier,
          mode: widget.mode,
        );
        if (!mounted) return;
        if (match == null) {
          // Match creation failed (RPC hiccup) — Kael AI steps in so the
          // player is never stranded on the matchmaking screen.
          _kaelOpponent = true;
        } else {
          _pvpMatch = match;

          // If match is still pending (we created it), wait for opponent.
          // Nobody joined within 25s → Kael AI takes the challenge.
          if (match.status == 'pending') {
            final accepted = await _pvpService!.waitForMatch(match.id,
                timeout: const Duration(seconds: 25));
            if (!mounted) return;
            if (accepted == null) {
              _kaelOpponent = true;
            } else {
              _pvpMatch = accepted;
            }
          }
        }

        if (_kaelOpponent) {
          _p2Profile = {
            'name': 'Kael AI',
            'avatar': '',
            'church': 'Church On App · AI Opponent',
          };
        } else if (!mounted) {
          return;
        } else {
          // Connect to Realtime broadcast channel
          _pvpService!.connectToChannel(_pvpMatch!);

          // Listen for opponent answers → update opponent score via callback
          _pvpService!.onOpponentAnswered = (payload) {
            if (!mounted) return;
            final score = payload['score'] as int? ?? 0;
            setState(() => _opponentScore = score);
          };

          // Fetch profiles for VS reveal
          _p1Profile = await _fetchPlayerDetail(_pvpMatch!.player1Id);
          if (_pvpMatch!.player2Id != null) {
            _p2Profile = await _fetchPlayerDetail(_pvpMatch!.player2Id!);
          }
        }
        if (_pvpMatch != null && _p1Profile == null) {
          _p1Profile = await _fetchPlayerDetail(_pvpMatch!.player1Id);
        }
      } catch (e) {
        debugPrint('[PvP] Match setup failed: $e');
        if (mounted) {
          setState(() => _loadingError = true);
        }
        return;
      }
    }

    final result = await _service.getUnseenQuestions(
      widget.questionCount,
      category: widget.categoryFilter,
      difficulty: widget.difficultyFilter,
    ).timeout(const Duration(seconds: 15), onTimeout: () {
      if (mounted) setState(() => _loadingTimedOut = true);
      return <QuizQuestion>[];
    });

    if (!mounted) return;

    // Fallback: if result is empty, try seed bank directly
    final questionsToUse = result.isNotEmpty
        ? result
        : _service.getFallbackQuestions(
            widget.questionCount,
            category: widget.categoryFilter,
            difficulty: widget.difficultyFilter,
          );

    if (questionsToUse.isEmpty) {
      setState(() => _loadingError = true);
      return;
    }

    setState(() {
      final seenIds = <String>{};
      _questions = questionsToUse.where((q) => seenIds.add(q.id)).map(_shuffleQuestionOptions).toList();
      if (_questions.isEmpty) {
        _loadingError = true;
        return;
      }
      _answers.clear();
      _responseTimesMs.clear();
      for (int i = 0; i < _questions.length; i++) {
        _answers.add(null);
        _responseTimesMs.add(0);
      }
      
      if (widget.mode != 'Solo') {
        _phase = GamePhase.vsReveal;
      } else {
        _phase = GamePhase.countdown;
      }
    });

    if (!_loadingError) {
      if (_phase == GamePhase.vsReveal) {
        _startVsReveal();
      } else {
        _startCountdown();
      }
    }
  }

  void _startVsReveal() async {
    _vsController.forward();
    await Future.delayed(const Duration(seconds: 4)); // 3s delay + animation time
    if (!mounted) return;
    setState(() => _phase = GamePhase.countdown);
    _startCountdown();
  }

  void _retryLoadQuestions() {
    _loadQuestions();
  }

  void _startCountdown() {
    _countdownValue = 3;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_countdownValue <= 1) {
        t.cancel();
        setState(() => _phase = GamePhase.playing);
        // First question: start fully visible (no slide animation needed)
        _slideController.value = 1.0;
        _startTimer();
      } else {
        setState(() => _countdownValue--);
      }
    });
  }

  void _startTimer() {
    _timerMs = _effectiveTimePerQuestionSec * 1000;
    // Blitz: cap the per-question timer at the remaining total clock.
    if (widget.style == QuizStyle.blitz) {
      _blitzStartedAt ??= DateTime.now().millisecondsSinceEpoch;
      final remaining = _blitzTotalMs -
          (DateTime.now().millisecondsSinceEpoch - _blitzStartedAt!);
      if (remaining <= 0) {
        _timerMs = 0;
      } else {
        _timerMs = _timerMs > remaining ? remaining : _timerMs;
      }
    }
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

    final q = _questions[_currentIndex];
    if (q.isMultipleAnswer) {
      // Multi-select: toggle selection, auto-submit when 2+ selected
      setState(() {
        if (_selectedAnswers.contains(idx)) {
          _selectedAnswers.remove(idx);
        } else {
          _selectedAnswers.add(idx);
        }
      });
      // Auto-submit if user has selected at least 2 options and paused
      // (They can also tap outside to submit)
      return;
    }

    _submitAnswer(idx);
  }

  void _submitMultiSelect() {
    final q = _questions[_currentIndex];
    _timer?.cancel();
    final elapsed = _startTime != null
        ? DateTime.now().millisecondsSinceEpoch - _startTime!
        : 0;

    final selected = Set<int>.from(_selectedAnswers);
    // For multi-select, correct = selected set matches correct_answers set
    final isCorrect = q.correctAnswers.isNotEmpty &&
        selected.length == q.correctAnswers.length &&
        selected.every((s) => q.correctAnswers.contains(s));

    setState(() {
      // Store first selected answer for PvP broadcast compatibility
      _selectedAnswer = selected.isNotEmpty ? selected.first : -1;
      _answers[_currentIndex] = _selectedAnswer;
      _responseTimesMs[_currentIndex] = elapsed;
      _phase = GamePhase.answering;

      if (isCorrect) {
        int pts = _questions[_currentIndex].points;
        pts *= widget.style.pointsMultiplier;
        if (_doubleUsed) pts *= 2;
        _score += pts;
        _streak++;
        if (_streak > _bestStreak) _bestStreak = _streak;
        if (_streak >= 3) _score += widget.style.streakBonus;
      } else {
        _streak = 0;
        if (widget.style == QuizStyle.suddenDeath) {
          _suddenDeathOut = true;
        }
      }

      _eliminatedOptions.clear();
      _doubleUsed = false;
      if (_fiftyFiftyIndex == _currentIndex) _fiftyFiftyIndex = null;
      if (_kaelOpponent) {
        final q2 = _questions[_currentIndex];
        if (_random.nextDouble() < 0.65) {
          _opponentScore += q2.points;
          if (_random.nextDouble() < 0.4) _opponentScore += 5;
        }
      }

      _phase = GamePhase.feedback;
    });

    if (widget.mode != 'Solo' && _pvpMatch != null && _pvpService != null) {
      int correctCount = 0;
      for (int i = 0; i <= _currentIndex; i++) {
        final qi = _questions[i];
        if (qi.isMultipleAnswer) {
          final stored = _answers[i];
          if (stored != null && qi.correctAnswers.contains(stored)) correctCount++;
        } else {
          if (_answers[i] == qi.correctAnswer) correctCount++;
        }
      }
      _pvpService!.sendAnswer(
        match: _pvpMatch!,
        questionIndex: _currentIndex,
        questionId: _questions[_currentIndex].id,
        selectedAnswer: _selectedAnswer ?? -1,
        responseTimeMs: elapsed,
        isCorrect: isCorrect,
        score: _score,
        correctCount: correctCount,
      );
    }

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _nextQuestion();
    });
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

    // Anti-cheat: if app was backgrounded, force zero points
    int effectiveIdx = idx;
    if (_wasBackgroundedDuringQuestion && widget.mode != 'Solo') {
      effectiveIdx = -1; // Force skip/zero
      debugPrint('[PvP Anti-Cheat] Question $_currentIndex flagged as zero points');
    }
    _wasBackgroundedDuringQuestion = false;

    final isCorrect = effectiveIdx >= 0 && _questions[_currentIndex].correctAnswer == effectiveIdx;

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _answers[_currentIndex] = effectiveIdx;
        _responseTimesMs[_currentIndex] = elapsed;

        if (isCorrect) {
          int pts = _questions[_currentIndex].points;
          pts *= widget.style.pointsMultiplier;
          if (_doubleUsed) pts *= 2;
          _score += pts;
          _streak++;
          if (_streak > _bestStreak) _bestStreak = _streak;
          if (_streak >= 3) _score += widget.style.streakBonus;
        } else {
          _streak = 0;
          if (widget.style == QuizStyle.suddenDeath) {
            _suddenDeathOut = true;
          }
        }

        _eliminatedOptions.clear();
        _doubleUsed = false;
        if (_fiftyFiftyIndex == _currentIndex) _fiftyFiftyIndex = null;

        // Kael AI opponent answers with ~65% accuracy, mimicking streaks.
        if (_kaelOpponent) {
          final q = _questions[_currentIndex];
          if (_random.nextDouble() < 0.65) {
            _opponentScore += q.points;
            if (_random.nextDouble() < 0.4) _opponentScore += 5;
          }
        }

        _phase = GamePhase.feedback;
      });

      // Send answer via PvP broadcast
      if (widget.mode != 'Solo' && _pvpMatch != null && _pvpService != null) {
        int correctCount = 0;
        for (int i = 0; i <= _currentIndex; i++) {
          if (_answers[i] == _questions[i].correctAnswer) correctCount++;
        }
        _pvpService!.sendAnswer(
          match: _pvpMatch!,
          questionIndex: _currentIndex,
          questionId: _questions[_currentIndex].id,
          selectedAnswer: effectiveIdx,
          responseTimeMs: elapsed,
          isCorrect: isCorrect,
          score: _score,
          correctCount: correctCount,
        );
      }

      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _nextQuestion();
      });
    });
  }

  void _nextQuestion() {
    // Sudden death: first mistake ends the run.
    if (widget.style == QuizStyle.suddenDeath && _suddenDeathOut) {
      setState(() => _phase = GamePhase.finished);
      return;
    }
    // Blitz: total 90s clock.
    if (widget.style == QuizStyle.blitz && _blitzStartedAt != null) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - _blitzStartedAt!;
      if (elapsed >= _blitzTotalMs) {
        setState(() => _phase = GamePhase.finished);
        return;
      }
    }
    if (_currentIndex + 1 >= _questions.length) {
      setState(() => _phase = GamePhase.finished);
      return;
    }

    _slideController.reset();
    setState(() {
      _currentIndex++;
       _selectedAnswer = null;
      _selectedAnswers.clear();
      _phase = GamePhase.playing;
      _timerMs = _effectiveTimePerQuestionSec * 1000;
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
    if (widget.style == QuizStyle.suddenDeath) {
      _suddenDeathOut = true;
    }

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
    _timerMs = _effectiveTimePerQuestionSec * 1000;
    setState(() {});
  }

  Color _timerColor() {
    final ratio = _timerMs / (_effectiveTimePerQuestionSec * 1000);
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

    // Submit verified score to event if in event mode (server-verified RPC)
    if (widget.eventId != null) {
      try {
        await ref.read(quizEventServiceProvider).submitTournamentAnswersBatch(
          eventId: widget.eventId!,
          questionIds: _questions.map((q) => q.id).toList(),
          answers: _answers.map((e) => e ?? -1).toList(),
          responseTimesMs: _responseTimesMs,
        );
      } catch (e) {
        debugPrint('Failed to submit quiz event score: $e');
      }
    }

try {
      await _service.recordAnsweredQuestions(
        questionIds: _questions.map((q) => q.id).toList(),
        matchId: _kaelOpponent ? null : _pvpMatch?.id,
        isCorrect: List.generate(_questions.length, (i) => _answers[i] == _questions[i].correctAnswer),
        answers: _answers.map((e) => e ?? -1).toList(),
        responseTimesMs: _responseTimesMs,
      );
    } catch (e) {
      debugPrint('Failed to record answered questions: $e');
    }

    // Complete PvP match (server-side settlement: verified scores + ELO + wager)
    if (widget.mode != 'Solo' &&
        !_kaelOpponent &&
        _pvpMatch != null &&
        _pvpService != null) {
      try {
        await _pvpService!.completeMatch(_pvpMatch!);
      } catch (e) {
        debugPrint('Failed to complete PvP match: $e');
      }
    }
    // Fetch the opponent's final score (settled server-side) for the results.
    int? oppScore;
    String? oppName;
    String? oppAvatar;
    String? oppChurch;
    if (widget.mode != 'Solo') {
      if (_kaelOpponent) {
        oppScore = _opponentScore;
        oppName = 'Kael AI';
        oppChurch = 'Church On App · AI Opponent';
      } else if (_pvpMatch != null) {
        try {
          final settled = await Supabase.instance.client
              .from('pvp_matches')
              .select('player1_score, player2_score, player1_id, player2_id')
              .eq('id', _pvpMatch!.id)
              .maybeSingle();
          if (settled != null) {
            final me = _pvpService!.currentUserId;
            oppScore = me == settled['player1_id']
                ? (settled['player2_score'] as num?)?.toInt()
                : (settled['player1_score'] as num?)?.toInt();
          }
          final oppId = _pvpService!.currentUserId == _pvpMatch!.player1Id
              ? _pvpMatch!.player2Id
              : _pvpMatch!.player1Id;
          final oppProfile = oppId != null
              ? await _fetchPlayerDetail(oppId)
              : null;
          oppName = oppProfile?['name'] as String?;
          oppAvatar = oppProfile?['avatar'] as String?;
          oppChurch = oppProfile?['church'] as String?;
        } catch (e) {
          debugPrint('Failed to fetch settled match scores: $e');
          oppScore = _opponentScore;
        }
      }
    }

    if (widget.categoryFilter == 'Daily') {
      var dailyRecorded = false;
      try {
        final res = await ref.read(dailyChallengeServiceProvider).submitVerifiedResult(
          questionIds: _questions.map((q) => q.id).toList(),
          answers: _answers.map((e) => e ?? -1).toList(),
          responseTimesMs: _responseTimesMs,
        );
        dailyRecorded = res?['success'] == true;
      } catch (e) {
        debugPrint('Failed to save daily challenge result: $e');
      }
      // +10 CC only when today's challenge was actually recorded (no replays).
      if (dailyRecorded) {
        try {
          await ref.read(profileProvider.notifier).addCoins(10);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("+10 CC earned for Daily Challenge!"), backgroundColor: Colors.green),
            );
          }
        } catch (e) {
          debugPrint('Failed to award daily challenge coins: $e');
        }
      }
    }

    // Leaderboard reflects the just-finished game.
    ref.invalidate(quizLeaderboardProvider);
    ref.invalidate(myQuizRankProvider);

    if (!mounted) return;
    Future.microtask(() {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BibleQuizResultsScreen(
            result: QuizSessionResult(
              questions: results.questions,
              answers: results.answers,
              responseTimesMs: results.responseTimesMs,
              streak: results.streak,
              powerUpsUsed: results.powerUpsUsed,
              opponentScore: oppScore,
              opponentName: oppName,
              opponentAvatar: oppAvatar,
              opponentChurch: oppChurch,
            ),
          ),
        ),
      );
    });
  }

  void _sendRematch() {
    if (_pvpMatch == null || _pvpService == null) return;
    setState(() => _rematchRequested = true);
    _pvpService!.sendRematchInvite(_pvpMatch!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: _phase == GamePhase.matchmaking || _isQuitting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase != GamePhase.matchmaking) {
          _showQuitConfirm(theme);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1117),
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
        backgroundColor: const Color(0xFF1A1D23),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Quit Quiz?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Your progress will be lost.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Keep Playing', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _isQuitting = true;
              _timer?.cancel();
              _countdownTimer?.cancel();
              _pvpService?.disconnect();
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
      case GamePhase.vsReveal:
        return _buildVsReveal(theme);
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

  Widget _buildVsReveal(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "MATCH FOUND!",
            style: TextStyle(color: AppTheme.platformPrimary, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  children: [
                    SlideTransition(
                      position: _player1SlideAnimation,
                      child: _vsPlayerCard(theme, _p1Profile, true),
                    ),
                    const SizedBox(height: 60),
                    SlideTransition(
                      position: _player2SlideAnimation,
                      child: _vsPlayerCard(theme, _p2Profile, false),
                    ),
                  ],
                ),
                ScaleTransition(
                  scale: _vsScaleAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: AppTheme.platformPrimary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: AppTheme.platformPrimary.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 5),
                      ],
                    ),
                    child: const Text("VS", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 22)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vsPlayerCard(ThemeData theme, Map<String, dynamic>? profile, bool isTop) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          if (!isTop) const Spacer(),
          if (isTop) ...[
            _avatarCircle(profile?['avatar']),
            const SizedBox(width: 15),
          ],
          Column(
            crossAxisAlignment: isTop ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              Text(profile?['name'] ?? 'Loading...', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              Text(profile?['church'] ?? 'Independent', style: TextStyle(color: AppTheme.platformPrimary.withValues(alpha: 0.7), fontSize: 12)),
            ],
          ),
          if (!isTop) ...[
            const SizedBox(width: 15),
            _avatarCircle(profile?['avatar']),
          ],
          if (isTop) const Spacer(),
        ],
      ),
    );
  }

  Widget _avatarCircle(String? url) {
    return Container(
      width: 60, height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).primaryColor, width: 2),
        image: url != null && url.isNotEmpty
            ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
            : null,
      ),
      child: url == null || url.isEmpty
          ? const Icon(LucideIcons.user, color: Colors.white24, size: 30)
          : null,
    );
  }

  Widget _buildMatchmaking(ThemeData theme) {
    final quizType = widget.categoryFilter ?? 'General';

    if (_loadingError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.alertTriangle, color: Colors.orangeAccent, size: 60),
              const SizedBox(height: 20),
              const Text('Failed to load questions', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                _loadingTimedOut ? 'Connection timed out. Check your network.' : 'No questions available. Try again.',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _retryLoadQuestions,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('RETRY'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.platformPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Shimmer.fromColors(
                baseColor: AppTheme.platformPrimary.withAlpha(40),
                highlightColor: AppTheme.platformPrimary.withAlpha(120),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.platformPrimary, width: 3),
                        ),
                      ),
                      Text(_categoryEmoji(quizType), style: const TextStyle(fontSize: 40)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                widget.mode == 'Solo' ? 'Preparing Questions…' : 'Finding Opponent…',
                style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.mode == 'Solo'
                    ? 'Curating $quizType questions for you'
                    : 'Searching for a worthy challenger',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              if (widget.mode != 'Solo') ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: AppTheme.platformPrimary.withAlpha(80),
                      child: Icon(LucideIcons.user, color: AppTheme.platformPrimary),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text('VS', style: TextStyle(color: AppTheme.platformPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
                    ),
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Theme.of(context).colorScheme.surface.withAlpha(20),
                      child: const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'If no challenger joins, Kael AI will step in.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 30),
              TextButton(
                onPressed: () {
                  _timer?.cancel();
                  _countdownTimer?.cancel();
                  Navigator.pop(context);
                },
                child: const Text('CANCEL', style: TextStyle(color: Colors.white38)),
              ),
            ],
          ),
        ),
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
        key: ValueKey(_countdownValue),
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: 900),
        builder: (context, value, child) {
          return Transform.scale(
            scale: 1 + value * 0.25,
            child: Text(
              '$_countdownValue',
              style: TextStyle(
                fontSize: 90,
                fontWeight: FontWeight.bold,
                color: AppTheme.platformPrimary,
                shadows: [
                  Shadow(
                    color: AppTheme.platformPrimary.withAlpha(100),
                    blurRadius: 30,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGameplay(ThemeData theme) {
    if (_questions.isEmpty || _currentIndex >= _questions.length) {
      return const Center(
        child: Text(
          'No questions available. Please try another category.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    final q = _questions[_currentIndex];
    final progress = _currentIndex / _questions.length;

    return Column(
      children: [
        // Top bar: progress + score + streak + timer
        _buildTopBar(theme, progress),
        const SizedBox(height: 8),
        // Question area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                children: [
                  // Category + difficulty badges
                  _buildBadges(theme, q),
                  const SizedBox(height: 16),
                  // Question card container
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      children: [
                        // Scripture reference — only reveal after answer submitted
                        if (q.scriptureReference != null &&
                            (_phase == GamePhase.answering || _phase == GamePhase.feedback || _phase == GamePhase.review))
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  q.scriptureReference!,
                                  style: TextStyle(
                                    color: AppTheme.platformPrimary.withValues(alpha: 0.8),
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ScriptureAudioButton(
                                reference: q.scriptureReference!,
                                iconColor: AppTheme.platformPrimary,
                                iconSize: 16,
                              ),
                            ],
                          ),
                        // Verse text — only reveal after answer submitted
                        if (q.scriptureReference != null &&
                            (_phase == GamePhase.answering || _phase == GamePhase.feedback || _phase == GamePhase.review))
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: LiveScriptureText(
                              reference: q.scriptureReference!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 13,
                                height: 1.5,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        // Question text
                        Text(
                          q.question,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Options grid/list
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: q.options.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      if (_eliminatedOptions.contains(i)) {
                        return _buildEliminatedOption(theme, q.options[i], i);
                      }
                      return _buildOption(theme, q, i);
                    },
                  ),
                  if (q.isMultipleAnswer && _phase == GamePhase.playing && _selectedAnswers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            _submitMultiSelect();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Submit Answers', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                  const SizedBox(height: 100), // Spacing for powerups at bottom
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Exit button
              GestureDetector(
                onTap: () => _showQuitConfirm(theme),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(LucideIcons.x, color: Colors.white70, size: 18),
                ),
              ),
              const Spacer(),
              _topStat(LucideIcons.helpCircle, '${_currentIndex + 1}/${_questions.length}', Colors.white54),
              if (widget.mode != 'Solo') ...[
                const SizedBox(width: 20),
                _topStat(LucideIcons.user, '$_opponentScore', Colors.orangeAccent),
              ],
              const Spacer(),
              // Score
              _topStat(LucideIcons.star, '$_score', AppTheme.platformPrimary),
            ],
          ),
          const SizedBox(height: 15),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation(AppTheme.platformPrimary),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
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
                        value: (_timerMs / (_effectiveTimePerQuestionSec * 1000)).clamp(0.0, 1.0),
                        strokeWidth: 3,
                        color: _timerColor(),
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(_timerMs / 1000).toStringAsFixed(1)}s',
                      style: TextStyle(
                        color: _timerColor(),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              // Streak indicator
              if (_streak >= 2)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_streak >= 5 ? Colors.orangeAccent : Colors.greenAccent).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: (_streak >= 5 ? Colors.orangeAccent : Colors.greenAccent).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _streak >= 5 ? LucideIcons.zap : LucideIcons.trendingUp,
                        size: 14,
                        color: _streak >= 5 ? Colors.orangeAccent : Colors.greenAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_streak}x STREAK',
                        style: TextStyle(
                          color: _streak >= 5 ? Colors.orangeAccent : Colors.greenAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
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
        _badge(q.category.toUpperCase(), AppTheme.platformPrimary, theme),
        const SizedBox(width: 10),
        _badge(q.difficulty.toUpperCase(), _difficultyColor(q.difficulty, theme), theme),
      ],
    );
  }

  Widget _topStat(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
      ),
    );
  }

  Color _difficultyColor(String diff, ThemeData theme) {
    switch (diff) {
      case 'Easy':
        return Colors.greenAccent;
      case 'Medium':
        return Colors.amberAccent;
      case 'Hard':
        return Colors.redAccent;
      default:
        return AppTheme.platformPrimary;
    }
  }

  Widget _buildOption(ThemeData theme, QuizQuestion q, int i) {
    final bool isRevealingAnswer = _phase == GamePhase.answering || _phase == GamePhase.feedback || _phase == GamePhase.review;
    final bool isCorrect = isRevealingAnswer && (q.isMultipleAnswer ? q.correctAnswers.contains(i) : q.correctAnswer == i);
    final bool isWrong = isRevealingAnswer && (q.isMultipleAnswer
        ? (_selectedAnswers.contains(i) && !q.correctAnswers.contains(i))
        : (_selectedAnswer == i && !isCorrect));
    final bool isSelected = q.isMultipleAnswer ? _selectedAnswers.contains(i) : _selectedAnswer == i;
    final bool isDisabled = _phase != GamePhase.playing;

    Color bgColor = Colors.white.withValues(alpha: 0.05);
    Color borderColor = Colors.white.withValues(alpha: 0.1);
    Color textColor = Colors.white;

    if (isCorrect) {
      bgColor = Colors.greenAccent.withValues(alpha: 0.2);
      borderColor = Colors.greenAccent;
      textColor = Colors.greenAccent;
    } else if (isWrong) {
      bgColor = Colors.redAccent.withValues(alpha: 0.2);
      borderColor = Colors.redAccent;
      textColor = Colors.redAccent;
    } else if (isSelected && isRevealingAnswer) {
      bgColor = Colors.orangeAccent.withValues(alpha: 0.2);
      borderColor = Colors.orangeAccent;
    } else if (isSelected && q.isMultipleAnswer) {
      bgColor = Colors.orangeAccent.withValues(alpha: 0.1);
      borderColor = Colors.orangeAccent;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isDisabled ? null : () => _selectAnswer(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    q.options[i],
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                    ),
                  ),
                ),
                if (isCorrect) const Icon(LucideIcons.checkCircle, size: 20, color: Colors.greenAccent),
                if (isWrong) const Icon(LucideIcons.xCircle, size: 20, color: Colors.redAccent),
              ],
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
            color: AppTheme.platformPrimary,
          ),
          _powerUpButton(
            icon: LucideIcons.skipForward,
            label: 'Skip',
            used: _skipUsed,
            onTap: _useSkip,
            color: AppTheme.platformPrimary,
          ),
          _powerUpButton(
            icon: LucideIcons.dice2,
            label: '2x',
            used: _doubleUsed,
            onTap: _useDoublePoints,
            color: AppTheme.platformPrimary,
          ),
          _powerUpButton(
            icon: LucideIcons.clock,
            label: 'Freeze',
            used: _timeFreezeUsed,
            onTap: _useTimeFreeze,
            color: AppTheme.platformPrimary,
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
                fontSize: 11,
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
                    ? AppTheme.platformPrimary.withAlpha(40)
                    : accuracy >= 0.5
                        ? AppTheme.platformPrimary.withAlpha(20)
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
                    ? AppTheme.platformPrimary
                    : accuracy >= 0.5
                        ? AppTheme.platformPrimary.withValues(alpha: 0.6)
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
                color: AppTheme.platformPrimary,
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            if (widget.mode != 'Solo') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _opponentScore > _score
                        ? Colors.redAccent.withAlpha(60)
                        : _opponentScore == _score
                            ? Colors.white.withAlpha(30)
                            : Colors.greenAccent.withAlpha(60),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _opponentScore > _score
                          ? LucideIcons.swords
                          : _opponentScore == _score
                              ? LucideIcons.scale
                              : LucideIcons.trophy,
                      color: _opponentScore > _score
                          ? Colors.redAccent
                          : _opponentScore == _score
                              ? Colors.white70
                              : Colors.greenAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Opponent: $_opponentScore pts',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      _opponentScore > _score
                          ? 'OPPONENT WINS'
                          : _opponentScore == _score
                              ? 'DRAW'
                              : 'YOU WIN',
                      style: TextStyle(
                        color: _opponentScore > _score
                            ? Colors.redAccent
                            : _opponentScore == _score
                                ? Colors.white70
                                : Colors.greenAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
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
                if (widget.mode != 'Solo')
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _rematchRequested ? null : _sendRematch,
                      icon: Icon(
                        _rematchRequested ? LucideIcons.check : LucideIcons.swords,
                        size: 18,
                      ),
                      label: Text(_rematchRequested ? 'Invite Sent!' : 'Rematch'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _rematchRequested ? Colors.greenAccent : AppTheme.platformPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                if (widget.mode != 'Solo') const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _goToResults,
                    icon: const Icon(LucideIcons.barChart3, size: 18),
                    label: const Text('Details'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.platformPrimary,
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
                AppTheme.platformPrimary,
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
                AppTheme.platformPrimary,
              ),
              _statItem(
                LucideIcons.zap,
                '$_powerUpsUsed',
                'Power-ups',
                AppTheme.platformPrimary,
              ),
              _statItem(
                LucideIcons.clock,
                _avgTimeText(),
                'Avg Time',
                AppTheme.platformPrimary.withValues(alpha: 0.7),
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
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                      final isCorrectOpt = q.isMultipleAnswer
                          ? q.correctAnswers.contains(optIdx)
                          : q.correctAnswer == optIdx;
                      final isUserAnswer = q.isMultipleAnswer
                          ? (answer != null && answer >= 0 && q.correctAnswers.contains(answer) && answer == optIdx) || answer == optIdx
                          : answer == optIdx;
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
                          color: AppTheme.platformPrimary.withAlpha(150),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LiveScriptureText(
                        reference: q.scriptureReference!,
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.4,
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
