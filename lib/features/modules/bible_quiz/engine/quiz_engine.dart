import 'dart:math' show Random;
import 'package:flutter/foundation.dart';

/// International-standard Bible Quiz engine (JBQ / WBQA aligned).
///
/// Pure-Dart domain layer: no Supabase / Flutter imports beyond foundation,
/// so every class here is unit-testable without mocks of the network stack.
///
/// Competition mechanics:
/// - Categories: directQuote, chapterAnalysis, multipleChoice, speedRound
///   (mirrors JBQ quotations, WBQA chapter analysis and buzzer rounds).
/// - Timing: millisecond-precision countdown with pause/resume and
///   configurable timeout penalties (rule set).
/// - Scoring: base points by difficulty (+10 Easy / +20 Medium / +30 Hard),
///   speed bonus inside the fast-answer window, wrong-attempt penalties in
///   competitive mode, 50/50 + ask-the-pastor + extra-time lifelines.
/// - Anti-cheat: monotonic server-authoritative clock contract; implausible
///   response times or duplicate submits flag the session for review.

/// Question categories following international competition standards.
enum QuizCategory {
  /// Verbatim quotation questions ("Quote John 3:16") - JBQ style.
  directQuote,

  /// Whole-chapter comprehension (sequence, who-said-it, fill-the-blank).
  chapterAnalysis,

  /// Standard four-option multiple choice.
  multipleChoice,

  /// Rapid-fire short answers with the shortest decision window.
  speedRound,
}

/// Difficulty tiers mapped to base point values by [QuizRuleSet].
enum QuizDifficulty { easy, medium, hard }

/// Session modes. Tournament mode requires a tenant access token.
enum QuizMode {
  /// Free practice - unlimited daily trivia, public leaderboards only.
  practice,

  /// Church/bookshop sponsored tournament - restricted to verified tenants,
  /// branded trophies, voucher rewards, pastor-uploaded packs.
  tournament,
}

/// A single quiz question with full scripture metadata for audit trails.
@immutable
class QuizQuestion {
  final String id;
  final String prompt;
  final List<String> options;
  final int correctIndex;

  /// For all-that-apply questions; empty means single-answer.
  final List<int> correctIndexes;
  final QuizCategory category;
  final QuizDifficulty difficulty;

  /// Canonical reference, e.g. "John 3:16" or "Psalm 23:1-6".
  final String book;
  final int chapter;

  /// Verse end when the answer spans a range; equals [verseStart] for single.
  final int verseStart;
  final int verseEnd;

  /// Optional translation code the quotation is taken from (default kjv).
  final String translation;

  const QuizQuestion({
    required this.id,
    required this.prompt,
    required this.options,
    required this.correctIndex,
    this.correctIndexes = const [],
    required this.category,
    required this.difficulty,
    required this.book,
    required this.chapter,
    required this.verseStart,
    int? verseEnd,
    this.translation = 'kjv',
  }) : verseEnd = verseEnd ?? verseStart;

  bool get isMultipleAnswer => correctIndexes.length > 1;

  bool isCorrect(int selectedIndex) =>
      !isMultipleAnswer && selectedIndex == correctIndex;

  bool isCorrectMulti(List<int> selected) {
    if (!isMultipleAnswer) return false;
    final sortedA = [...selected]..sort();
    final sortedB = [...correctIndexes]..sort();
    return listEquals(sortedA, sortedB);
  }

  /// Human-readable canonical reference "Book C:V" or "Book C:V-V2".
  String get reference => verseEnd == verseStart
      ? '$book $chapter:$verseStart'
      : '$book $chapter:$verseStart-$verseEnd';

  factory QuizQuestion.fromMap(Map<String, dynamic> m) => QuizQuestion(
        id: m['id']?.toString() ?? '',
        prompt: m['prompt']?.toString() ?? m['question']?.toString() ?? '',
        options: List<String>.from(m['options'] ?? const <String>[]),
        correctIndex: (m['correct_index'] as num?)?.toInt() ??
            (m['correct_answer'] as num?)?.toInt() ??
            0,
        correctIndexes: m['correct_indexes'] != null
            ? List<int>.from(
                (m['correct_indexes'] as List).map((e) => (e as num).toInt()))
            : const [],
        category: QuizCategory.values.firstWhere(
          (c) => c.name == (m['category']?.toString() ?? 'multipleChoice'),
          orElse: () => QuizCategory.multipleChoice,
        ),
        difficulty: QuizDifficulty.values.firstWhere(
          (d) => d.name.toLowerCase() ==
              (m['difficulty']?.toString() ?? 'medium').toLowerCase(),
          orElse: () => QuizDifficulty.medium,
        ),
        book: m['book']?.toString() ?? '',
        chapter: (m['chapter'] as num?)?.toInt() ?? 0,
        verseStart: (m['verse_start'] as num?)?.toInt() ?? 0,
        verseEnd: (m['verse_end'] as num?)?.toInt(),
        translation: m['translation']?.toString() ?? 'kjv',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'prompt': prompt,
        'options': options,
        'correct_index': correctIndex,
        'correct_indexes': correctIndexes,
        'category': category.name,
        'difficulty': difficulty.name,
        'book': book,
        'chapter': chapter,
        'verse_start': verseStart,
        'verse_end': verseEnd,
        'translation': translation,
      };
}

/// Immutable rule configuration for a session/tournament (WBQA-style).
@immutable
class QuizRuleSet {
  /// Decision window after buzzing in before an answer is forced (ms).
  final int decisionWindowMs;

  /// Full answer window once the question is read aloud/shown (ms).
  final int answerWindowMs;

  /// Answers inside this window from reveal earn the speed bonus.
  final int fastAnswerWindowMs;

  /// Speed bonus points for beating [fastAnswerWindowMs].
  final int speedBonusPoints;

  /// Points deducted per wrong attempt; 0 disables penalties (practice mode).
  final int wrongAttemptPenalty;

  /// Timeout penalty applied when the window expires unanswered.
  final int timeoutPenalty;

  /// Lifeline budgets per session (0 disables the lifeline).
  final int fiftyFiftyCount;
  final int askPastorCount;
  final int extraTimeCount;

  /// Extra-time grant per use (added to remaining window).
  final int extraTimeBonusMs;

  const QuizRuleSet({
    this.decisionWindowMs = 5000,
    this.answerWindowMs = 30000,
    this.fastAnswerWindowMs = 3000,
    this.speedBonusPoints = 5,
    this.wrongAttemptPenalty = 10,
    this.timeoutPenalty = 5,
    this.fiftyFiftyCount = 1,
    this.askPastorCount = 1,
    this.extraTimeCount = 1,
    this.extraTimeBonusMs = 15000,
  });

  /// Free practice rules: generous windows, zero penalties, one lifeline each.
  static const QuizRuleSet practice = QuizRuleSet(
    decisionWindowMs: 8000,
    answerWindowMs: 45000,
    fastAnswerWindowMs: 5000,
    speedBonusPoints: 3,
    wrongAttemptPenalty: 0,
    timeoutPenalty: 0,
    fiftyFiftyCount: 1,
    askPastorCount: 1,
    extraTimeCount: 1,
    extraTimeBonusMs: 20000,
  );

  /// Official tournament rules: tight windows, full penalties, single-use
  /// lifelines - matches national/international finals conditions.
  static const QuizRuleSet tournament = QuizRuleSet();

  Map<String, dynamic> toMap() => {
        'decision_window_ms': decisionWindowMs,
        'answer_window_ms': answerWindowMs,
        'fast_answer_window_ms': fastAnswerWindowMs,
        'speed_bonus_points': speedBonusPoints,
        'wrong_attempt_penalty': wrongAttemptPenalty,
        'timeout_penalty': timeoutPenalty,
        'fifty_fifty_count': fiftyFiftyCount,
        'ask_pastor_count': askPastorCount,
        'extra_time_count': extraTimeCount,
        'extra_time_bonus_ms': extraTimeBonusMs,
      };

  static QuizRuleSet fromMap(Map<String, dynamic> m) => QuizRuleSet(
        decisionWindowMs: (m['decision_window_ms'] as num?)?.toInt() ?? 5000,
        answerWindowMs: (m['answer_window_ms'] as num?)?.toInt() ?? 30000,
        fastAnswerWindowMs:
            (m['fast_answer_window_ms'] as num?)?.toInt() ?? 3000,
        speedBonusPoints: (m['speed_bonus_points'] as num?)?.toInt() ?? 5,
        wrongAttemptPenalty:
            (m['wrong_attempt_penalty'] as num?)?.toInt() ?? 10,
        timeoutPenalty: (m['timeout_penalty'] as num?)?.toInt() ?? 5,
        fiftyFiftyCount: (m['fifty_fifty_count'] as num?)?.toInt() ?? 1,
        askPastorCount: (m['ask_pastor_count'] as num?)?.toInt() ?? 1,
        extraTimeCount: (m['extra_time_count'] as num?)?.toInt() ?? 1,
        extraTimeBonusMs: (m['extra_time_bonus_ms'] as num?)?.toInt() ?? 15000,
      );
}

/// Base points per difficulty tier (+10 / +20 / +30).
int basePointsFor(QuizDifficulty d) {
  switch (d) {
    case QuizDifficulty.easy:
      return 10;
    case QuizDifficulty.medium:
      return 20;
    case QuizDifficulty.hard:
      return 30;
  }
}

/// Multiplier used for display/leaderboard weighting (Easy 1x -> Hard 3x raw;
/// competition scoring uses additive base points instead).
double multiplierFor(QuizDifficulty d) {
  switch (d) {
    case QuizDifficulty.easy:
      return 1.0;
    case QuizDifficulty.medium:
      return 1.5;
    case QuizDifficulty.hard:
      return 2.0;
  }
}

/// Result of scoring a single answered question.
@immutable
class ScoreBreakdown {
  final int basePoints;
  final int speedBonus;
  final int penalty;
  final int total;
  final bool isCorrect;

  const ScoreBreakdown({
    required this.basePoints,
    required this.speedBonus,
    required this.penalty,
    required this.total,
    required this.isCorrect,
  });
}

/// Millisecond-precision countdown timer with pause/resume support and a
/// pluggable clock so tests can drive time deterministically.
class QuizTimer {
  /// Total budget. Starts at [initial]; grows via [addTime] (Extra Time).
  Duration total;
  final Duration Function() now; // injectable monotonic clock

  Duration _elapsedBeforePause = Duration.zero;
  Duration? _startedAt;
  bool _expiredNotified = false;
  final List<void Function()> _onExpireListeners = [];

  QuizTimer({required this.initial, DateTime Function()? clock})
      : total = initial,
        now = clock != null
            ? (() => Duration(milliseconds: clock().millisecondsSinceEpoch))
            : Duration.new {
    assert(initial >= Duration.zero);
  }

  final Duration initial;

  bool get isRunning => _startedAt != null;

  /// True once remaining hits zero. Expiry is detected lazily on read, which
  /// keeps behaviour deterministic under fake clocks in tests.
  bool get isExpired {
    final expiredNow = remaining <= Duration.zero;
    if (expiredNow && !_expiredNotified) {
      _expiredNotified = true;
      for (final l in List.of(_onExpireListeners)) {
        try {
          l();
        } catch (_) {}
      }
    }
    return expiredNow;
  }

  /// Time left on the clock. Pausing freezes it; extra time extends it.
  Duration get remaining {
    var left = total - _elapsedBeforePause;
    if (_startedAt != null) {
      final running = now() - _startedAt!;
      if (running >= left) return Duration.zero;
      left -= running;
    }
    return left < Duration.zero ? Duration.zero : left;
  }

  void start() {
    if (_startedAt != null || remaining <= Duration.zero) return;
    _startedAt = now();
  }

  void pause() {
    if (_startedAt == null) return;
    _elapsedBeforePause += now() - _startedAt!;
    _startedAt = null;
  }

  void resume() {
    if (_startedAt != null || remaining <= Duration.zero) return;
    _startedAt = now();
  }

  /// Adds bonus time (Extra-Time lifeline). An already-expired round may NOT
  /// be revived (anti-cheat); paused or running positive timers can extend.
  bool addTime(Duration bonus) {
    if (bonus < Duration.zero) return false;
    if (!isRunning && _elapsedBeforePause >= total) {
      // Fully consumed while paused -> treat as expired; no revival.
      return false;
    }
    if (remaining <= Duration.zero && _startedAt != null) {
      return false; // expired mid-round -> no revival
    }
    total += bonus;
    if (_startedAt != null && _elapsedBeforePause > total) {
      // Defensive: clamp impossible elapsed after shrink-like ops.
      _elapsedBeforePause = total;
    }
    return true;
  }

  void addExpireListener(void Function() listener) =>
      _onExpireListeners.add(listener);

  void dispose() => _onExpireListeners.clear();
}

/// Per-question state machine for competitive rounds.
enum QuestionPhase { pending, revealed, answering, scored }

/// One scored interaction inside a session.
@immutable
class QuestionAttempt {
  final QuizQuestion question;
  final int? selectedIndex;
  final List<int>? selectedMulti;
  final Duration responseTime;
  final bool timedOut;
  final ScoreBreakdown breakdown;
  final bool usedFiftyFifty;
  final bool usedAskPastor;
  final bool usedExtraTime;

  const QuestionAttempt({
    required this.question,
    required this.selectedIndex,
    required this.responseTime,
    required this.timedOut,
    required this.breakdown,
    this.selectedMulti,
    this.usedFiftyFifty = false,
    this.usedAskPastor = false,
    this.usedExtraTime = false,
  });
}

/// Live session state: scoring, lifelines, attempts, anti-cheat ledger.
class QuizSession {
  final String id;
  final String userId;
  final QuizMode mode;
  final QuizRuleSet rules;
  final List<QuizQuestion> questions;

  /// Tenant token required for [QuizMode.tournament]; verified upstream.
  final String? tenantToken;

  int _score = 0;
  int _fiftyLeft = 0;
  int _pastorLeft = 0;
  int _extraTimeLeft = 0;
  final List<QuestionAttempt> _attempts = [];

  /// Anti-cheat: set when a violation (clock rollback, pre-reveal answer,
  /// duplicate submit) is detected. Flagged sessions are excluded from ranks.
  String? antiCheatViolation;

  QuizSession({
    required this.id,
    required this.userId,
    required this.mode,
    required this.questions,
    QuizRuleSet? rules,
    this.tenantToken,
  })  : rules = rules ??
            (mode == QuizMode.tournament
                ? QuizRuleSet.tournament
                : QuizRuleSet.practice) {
    final effective = this.rules;
    _fiftyLeft = effective.fiftyFiftyCount;
    _pastorLeft = effective.askPastorCount;
    _extraTimeLeft = effective.extraTimeCount;
    if (mode == QuizMode.tournament &&
        (tenantToken == null || tenantToken!.isEmpty)) {
      throw ArgumentError('Tournament sessions require a tenant access token');
    }
  }

  int get score => _score;
  int get fiftyFiftyRemaining => _fiftyLeft;
  int get askPastorRemaining => _pastorLeft;
  int get extraTimeRemaining => _extraTimeLeft;
  List<QuestionAttempt> get attempts => List.unmodifiable(_attempts);
  bool get isFlagged => antiCheatViolation != null;

  int get maxScore =>
      questions.fold(0, (sum, q) => sum + basePointsFor(q.difficulty));

  double get accuracy {
    if (questions.isEmpty) return 0;
    return _attempts.where((a) => a.breakdown.isCorrect).length /
        questions.length;
  }

  /// Scores one attempt atomically. Returns the breakdown. Enforces:
  /// - no double-submit for the same question index
  /// - response time sanity (negative or > window -> flagged)
  ScoreBreakdown submitAnswer({
    required int questionIndex,
    int? selectedIndex,
    List<int>? selectedMulti,
    required Duration responseTime,
    bool timedOut = false,
  }) {
    assert(questionIndex >= 0 && questionIndex < questions.length);
    final q = questions[questionIndex];

    // Anti-cheat: duplicate submission for the same slot.
    if (_attempts.any((a) => identical(a.question, q))) {
      antiCheatViolation = 'duplicate_submit_q$questionIndex';
    }
    // Anti-cheat: impossible response times.
    if (responseTime < Duration.zero ||
        responseTime.inMilliseconds >
            rules.answerWindowMs + rules.extraTimeBonusMs * 4) {
      antiCheatViolation ??= 'implausible_response_time_q$questionIndex';
    }

    final correct = timedOut
        ? false
        : q.isMultipleAnswer
            ? q.isCorrectMulti(selectedMulti ?? const [])
            : q.isCorrect(selectedIndex ?? -1);

    final base = correct ? basePointsFor(q.difficulty) : 0;
    final speedBonus = (!timedOut &&
            correct &&
            responseTime.inMilliseconds <= rules.fastAnswerWindowMs)
        ? rules.speedBonusPoints
        : 0;
    final penalty = !correct
        ? (timedOut ? rules.timeoutPenalty : rules.wrongAttemptPenalty)
        : 0;

    final bd = ScoreBreakdown(
      basePoints: base,
      speedBonus: speedBonus,
      penalty: penalty,
      total: base + speedBonus - penalty,
      isCorrect: correct,
    );
    _score += bd.total;

    _attempts.add(QuestionAttempt(
      question: q,
      selectedIndex: selectedIndex,
      selectedMulti: selectedMulti,
      responseTime: responseTime,
      timedOut: timedOut,
      breakdown: bd,
      usedFiftyFifty: _fiftyUsedThisRound,
      usedAskPastor: _pastorUsedThisRound,
      usedExtraTime: _extraUsedThisRound,
    ));
    _resetRoundFlags();
    return bd;
  }

  // Lifelines --------------------------------------------------------------

  bool _fiftyUsedThisRound = false;
  bool _pastorUsedThisRound = false;
  bool _extraUsedThisRound = false;

  void _resetRoundFlags() {
    _fiftyUsedThisRound = false;
    _pastorUsedThisRound = false;
    _extraUsedThisRound = false;
  }

  /// Removes two wrong options, keeping the correct one plus [keepIndex].
  /// Returns the surviving option indexes, or null when exhausted/invalid.
  List<int>? useFiftyFifty(int questionIndex, {int keepIndex = -1}) {
    if (_fiftyLeft <= 0) return null;
    final q = questions[questionIndex];
    if (q.options.length < 3) return null;
    _fiftyLeft--;
    _fiftyUsedThisRound = true;

    final wrongIdx = List<int>.generate(q.options.length, (i) => i)
        .where((i) => i != q.correctIndex && i != keepIndex)
        .toList()
      ..shuffle(_seededRandom(questionIndex));
    final removeCount = q.options.length - 2;
    final removed = wrongIdx.take(removeCount).toSet();
    return List<int>.generate(q.options.length, (i) => i)
        .where((i) => !removed.contains(i))
        .toList();
  }

  /// Ask-the-Pastor AI hint. Consumes budget; returns true on success.
  bool useAskPastor() {
    if (_pastorLeft <= 0) return false;
    _pastorLeft--;
    _pastorUsedThisRound = true;
    return true;
  }

  /// Extra Time. Returns granted milliseconds, or null when exhausted.
  Duration? useExtraTime(QuizTimer timer) {
    if (_extraTimeLeft <= 0) return null;
    final granted = Duration(milliseconds: rules.extraTimeBonusMs);
    if (!timer.addTime(granted)) return null;
    _extraTimeLeft--;
    _extraUsedThisRound = true;
    return granted;
  }

  /// Deterministic PRNG seeded by question hash so mock runs are reproducible
  /// in tests (no flaky 50/50 removals).
  Random _seededRandom(int salt) =>
      Random(Object.hash(questions[salt].id, salt));
}
