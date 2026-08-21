import 'package:flutter_test/flutter_test.dart';

import 'package:church_on_app/features/modules/bible_quiz/engine/quiz_engine.dart';
import 'package:church_on_app/features/modules/bible_quiz/engine/quiz_models.dart';
import 'package:church_on_app/features/modules/bible_quiz/engine/mock_quiz_repository.dart';

List<QuizQuestion> _bank() => MockQuizRepository.seedBank();

void main() {
  group('QuizRuleSet', () {
    test('tournament rules match international finals conditions', () {
      const r = QuizRuleSet.tournament;
      expect(r.decisionWindowMs, 5000, reason: '5s decision window (WBQA)');
      expect(r.answerWindowMs, 30000, reason: '30s answer window');
      expect(r.wrongAttemptPenalty, greaterThan(0));
      expect(r.fiftyFiftyCount, 1);
    });

    test('practice rules are penalty-free and generous', () {
      const r = QuizRuleSet.practice;
      expect(r.wrongAttemptPenalty, 0);
      expect(r.timeoutPenalty, 0);
      expect(r.answerWindowMs, greaterThan(QuizRuleSet.tournament.answerWindowMs));
    });

    test('roundtrips through map without data loss', () {
      const r = QuizRuleSet(
        decisionWindowMs: 4000,
        answerWindowMs: 25000,
        fastAnswerWindowMs: 2000,
        speedBonusPoints: 7,
        wrongAttemptPenalty: 15,
        timeoutPenalty: 8,
        fiftyFiftyCount: 2,
        askPastorCount: 3,
        extraTimeCount: 4,
        extraTimeBonusMs: 12000,
      );
      final restored = QuizRuleSet.fromMap(r.toMap());
      expect(restored.decisionWindowMs, 4000);
      expect(restored.speedBonusPoints, 7);
      expect(restored.wrongAttemptPenalty, 15);
      expect(restored.extraTimeBonusMs, 12000);
    });
  });

  group('scoring model (+10/+20/+30, speed bonus, penalties)', () {
    test('base points follow difficulty tiers exactly', () {
      expect(basePointsFor(QuizDifficulty.easy), 10);
      expect(basePointsFor(QuizDifficulty.medium), 20);
      expect(basePointsFor(QuizDifficulty.hard), 30);
    });

    test('multipliers are 1x / 1.5x / 2x for display weighting', () {
      expect(multiplierFor(QuizDifficulty.easy), 1.0);
      expect(multiplierFor(QuizDifficulty.medium), 1.5);
      expect(multiplierFor(QuizDifficulty.hard), 2.0);
    });

    test('correct easy answer scores base only when slow', () {
      final q = _bank().firstWhere((x) => x.difficulty == QuizDifficulty.easy);
      final s = QuizSession(id: 's1', userId: 'u1', mode: QuizMode.practice, questions: [q]);
      final bd = s.submitAnswer(questionIndex: 0, selectedIndex: q.correctIndex, responseTime: const Duration(milliseconds: 9000));
      expect(bd.isCorrect, isTrue);
      expect(bd.basePoints, 10);
      expect(bd.speedBonus, greaterThanOrEqualTo(0));
      expect(bd.penalty, 0, reason: 'practice mode has no penalties');
      expect(s.score, bd.total);
    });

    test('fast correct answer earns the speed bonus in tournament mode', () {
      final q = _bank().first;
      final s = QuizSession(
        id: 's2', userId: 'u1', mode: QuizMode.tournament,
        questions: [q], tenantToken: 'tok-123',
        rules: const QuizRuleSet(fastAnswerWindowMs: 3000, speedBonusPoints: 5),
      );
      final bd = s.submitAnswer(questionIndex: 0, selectedIndex: q.correctIndex, responseTime: const Duration(milliseconds: 1200));
      expect(bd.basePoints, 10);
      expect(bd.speedBonus, 5);
      expect(bd.total, 15);
      expect(s.score, 15);
    });

    test('wrong attempt deducts tournament penalty but not in practice', () {
      final q = _bank().first;
      final wrong = (q.correctIndex + 1) % q.options.length;

      final t = QuizSession(id: 't', userId: 'u', mode: QuizMode.tournament, questions: [q], tenantToken: 'tok');
      final tb = t.submitAnswer(questionIndex: 0, selectedIndex: wrong, responseTime: const Duration(seconds: 2));
      expect(tb.total, -QuizRuleSet.tournament.wrongAttemptPenalty);

      final p = QuizSession(id: 'p', userId: 'u', mode: QuizMode.practice, questions: [q]);
      final pb = p.submitAnswer(questionIndex: 0, selectedIndex: wrong, responseTime: const Duration(seconds: 2));
      expect(pb.total, 0, reason: 'free tier must never go negative');
      expect(p.score, 0);
    });

    test('timeout applies timeoutPenalty and marks timedOut', () {
      final q = _bank().first;
      final s = QuizSession(
        id: 's3', userId: 'u1', mode: QuizMode.tournament,
        questions: [q], tenantToken: 'tok',
        rules: const QuizRuleSet(timeoutPenalty: 5),
      );
      final bd = s.submitAnswer(questionIndex: 0, selectedIndex: null, responseTime: const Duration(seconds: 30), timedOut: true);
      expect(bd.isCorrect, isFalse);
      expect(bd.penalty, 5);
      expect(bd.basePoints, 0);
    });

    test('session score can go negative in competitive mode (penalties)', () {
      final qs = _bank().take(3).toList();
      final s = QuizSession(id: 's4', userId: 'u1', mode: QuizMode.tournament, questions: qs, tenantToken: 'tok');
      for (var i = 0; i < 3; i++) {
        final wrong = (qs[i].correctIndex + 1) % qs[i].options.length;
        s.submitAnswer(questionIndex: i, selectedIndex: wrong, responseTime: const Duration(seconds: 1));
      }
      expect(s.score, -3 * QuizRuleSet.tournament.wrongAttemptPenalty);
      expect(s.accuracy, 0.0);
    });

    test('maxScore equals sum of difficulty base points', () {
      final qs = _bank().take(5).toList();
      final s = QuizSession(id: 's5', userId: 'u1', mode: QuizMode.practice, questions: qs);
      expect(s.maxScore, qs.fold<int>(0, (acc, q) => acc + basePointsFor(q.difficulty)));
    });
  });

  group('multi-answer questions', () {
    test('isCorrectMulti requires exact set equality', () {
      final q = QuizQuestion(
        id: 'ma1', prompt: 'Pick the two gospel books',
        options: ['Matthew', 'Mark', 'Romans', 'Jude'],
        correctIndex: 0, correctIndexes: const [0, 1],
        category: QuizCategory.multipleChoice, difficulty: QuizDifficulty.medium,
        book: 'Matthew', chapter: 1, verseStart: 1,
      );
      expect(q.isMultipleAnswer, isTrue);
      expect(q.isCorrectMulti([1, 0]), isTrue, reason: 'order-insensitive');
      expect(q.isCorrectMulti([0]), isFalse, reason: 'partial selection fails');
      expect(q.isCorrectMulti([0, 1, 2]), isFalse);
      expect(q.isCorrectMulti(const []), isFalse);
    });
  });

  group('anti-cheat', () {
    test('duplicate submission for same question flags the session', () {
      final q = _bank().first;
      final s = QuizSession(id: 'ac1', userId: 'u', mode: QuizMode.practice, questions: [q]);
      s.submitAnswer(questionIndex: 0, selectedIndex: q.correctIndex, responseTime: const Duration(seconds: 1));
      s.submitAnswer(questionIndex: 0, selectedIndex: q.correctIndex, responseTime: const Duration(seconds: 1));
      expect(s.isFlagged, isTrue);
      expect(s.antiCheatViolation, contains('duplicate_submit'));
    });

    test('implausible (negative) response time flags the session', () {
      final q = _bank().first;
      final s = QuizSession(id: 'ac2', userId: 'u', mode: QuizMode.practice, questions: [q]);
      s.submitAnswer(questionIndex: 0, selectedIndex: q.correctIndex, responseTime: const Duration(milliseconds: -50));
      expect(s.isFlagged, isTrue);
      expect(s.antiCheatViolation, contains('implausible_response_time'));
    });

    test('flagged sessions are rejected by the repository on submit', () async {
      final repo = MockQuizRepository();
      final q = _bank().first;
      final s = QuizSession(id: 'ac3', userId: 'u', mode: QuizMode.practice, questions: [q]);
      s.submitAnswer(questionIndex: 0, selectedIndex: q.correctIndex, responseTime: const Duration(milliseconds: -1));
      expect(() => repo.submitSession(s, scoreHashPreview(s)), throwsStateError);
    });

    test('clean session passes submit and returns stable hash', () async {
      final repo = MockQuizRepository();
      final q = _bank().first;
      final s = QuizSession(id: 'ok1', userId: 'u', mode: QuizMode.practice, questions: [q]);
      s.submitAnswer(questionIndex: 0, selectedIndex: q.correctIndex, responseTime: const Duration(milliseconds: 800));
      final hash = await repo.submitSession(s, scoreHashPreview(s));
      expect(hash, isNotEmpty);
      // Deterministic: same session facts → same preview hash.
      expect(scoreHashPreview(s), hash);
    });
  });

  group('lifelines', () {
    test('50/50 keeps exactly two options including the correct one', () {
      final q = _bank().first;
      final s = QuizSession(id: 'lf1', userId: 'u', mode: QuizMode.practice, questions: [q]);
      final survivors = s.useFiftyFifty(0);
      expect(survivors, isNotNull);
      expect(survivors!.length, 2);
      expect(survivors, contains(q.correctIndex));
      expect(s.fiftyFiftyRemaining, 0);
    });

    test('50/50 respects keepIndex preference', () {
      final q = _bank().first;
      final s = QuizSession(id: 'lf2', userId: 'u', mode: QuizMode.practice, questions: [q]);
      final keep = (q.correctIndex + 1) % q.options.length;
      final survivors = s.useFiftyFifty(0, keepIndex: keep)!;
      expect(survivors, containsAll(<int>[q.correctIndex, keep]));
    });

    test('50/50 returns null once exhausted or options < 3', () {
      final q = _bank().first;
      final tiny = QuizQuestion(
        id: 'tiny', prompt: 'T/F', options: ['True', 'False'], correctIndex: 0,
        category: QuizCategory.speedRound, difficulty: QuizDifficulty.easy,
        book: 'John', chapter: 11, verseStart: 35,
      );
      final s = QuizSession(id: 'lf3', userId: 'u', mode: QuizMode.practice, questions: [q, tiny]);
      expect(s.useFiftyFifty(0), isNotNull);
      expect(s.useFiftyFifty(0), isNull, reason: 'budget spent');
      expect(s.useFiftyFifty(1), isNull, reason: 'two-option question ineligible');
    });

    test('Ask-the-Pastor consumes budget once then refuses', () {
      final s = QuizSession(id: 'lf4', userId: 'u', mode: QuizMode.practice, questions: _bank());
      expect(s.useAskPastor(), isTrue);
      expect(s.askPastorRemaining, 0);
      expect(s.useAskPastor(), isFalse);
    });

    test('Extra Time extends a running timer by the configured bonus', () {
      var fakeNow = DateTime(2026, 8, 22, 12, 0, 0);
      final timer = QuizTimer(initial: const Duration(seconds: 30), clock: () => fakeNow)..start();
      final s = QuizSession(
        id: 'lf5', userId: 'u', mode: QuizMode.practice, questions: _bank(),
        rules: const QuizRuleSet(extraTimeBonusMs: 15000),
      );

      fakeNow = fakeNow.add(const Duration(seconds: 20)); // 10s left
      final before = timer.remaining;
      expect(before, const Duration(seconds: 10));

      final granted = s.useExtraTime(timer);
      expect(granted, const Duration(seconds: 15));
      expect(timer.remaining, const Duration(seconds: 25));
      expect(s.extraTimeRemaining, 0);
      expect(s.useExtraTime(timer), isNull, reason: 'budget exhausted');
    });

    test('Extra Time cannot revive an already-expired round (anti-cheat)', () {
      var fakeNow = DateTime(2026, 8, 22, 12, 0, 0);
      final timer = QuizTimer(initial: const Duration(seconds: 5), clock: () => fakeNow)..start();
      final s = QuizSession(id: 'lf6', userId: 'u', mode: QuizMode.practice, questions: _bank());

      fakeNow = fakeNow.add(const Duration(seconds: 6)); // expired
      expect(timer.isExpired, isTrue);
      expect(timer.remaining, Duration.zero);
      expect(s.useExtraTime(timer), isNull, reason: 'no revival after expiry');
    });

    test('tournament mode throws without a tenant token', () {
      expect(
        () => QuizSession(id: 'lf7', userId: 'u', mode: QuizMode.tournament, questions: _bank()),
        throwsArgumentError,
      );
      expect(
        () => QuizSession(id: 'lf8', userId: 'u', mode: QuizMode.tournament, questions: _bank(), tenantToken: ''),
        throwsArgumentError,
      );
      expect(
        QuizSession(id: 'lf9', userId: 'u', mode: QuizMode.tournament, questions: _bank(), tenantToken: 'tok'),
        isA<QuizSession>(),
      );
    });
  });

  group('QuizTimer precision & interruption handling', () {
    test('tracks millisecond precision under a fake clock', () {
      var now = DateTime(2026, 8, 22, 9, 0, 0, 0);
      final t = QuizTimer(initial: const Duration(seconds: 30), clock: () => now)..start();
      now = now.add(const Duration(milliseconds: 1234));
      expect(t.remaining.inMilliseconds, 30000 - 1234);
      now = now.add(const Duration(milliseconds: 766));
      expect(t.remaining.inMilliseconds, 28000);
    });

    test('pause freezes remaining; resume continues from freeze point', () {
      var now = DateTime(2026, 8, 22, 9, 0, 0);
      final t = QuizTimer(initial: const Duration(seconds: 30), clock: () => now)..start();
      now = now.add(const Duration(seconds: 10));
      t.pause();
      // Time passes while paused — must NOT count down.
      now = now.add(const Duration(minutes: 5));
      expect(t.remaining, const Duration(seconds: 20));
      t.resume();
      now = now.add(const Duration(seconds: 5));
      expect(t.remaining, const Duration(seconds: 15));
    });

    test('expiry fires listener exactly once even if polled repeatedly', () {
      var now = DateTime(2026, 8, 22, 9, 0, 0);
      final t = QuizTimer(initial: const Duration(seconds: 1), clock: () => now);
      var fired = 0;
      t.addExpireListener(() => fired++);
      t.start();
      now = now.add(const Duration(seconds: 2));
      expect(t.isExpired, isTrue);
      expect(t.isExpired, isTrue); // poll again
      expect(t.isExpired, isTrue);
      expect(fired, 1);
    });

    test('zero-duration timer is born expired and cannot start', () {
      var now = DateTime(2026, 8, 22);
      final t = QuizTimer(initial: Duration.zero, clock: () => now);
      expect(t.isExpired, isTrue);
      t.start();
      now = now.add(const Duration(seconds: 1));
      expect(t.remaining, Duration.zero);
    });

    test('addTime rejects negative bonuses', () {
      var now = DateTime(2026, 8, 22);
      final t = QuizTimer(initial: const Duration(seconds: 10), clock: () => now)..start();
      expect(t.addTime(const Duration(seconds: -5)), isFalse);
      expect(t.remaining, const Duration(seconds: 10));
    });
  });

  group('question metadata integrity (international standard)', () {
    final bank = MockQuizRepository.seedBank();

    test('every seeded question carries valid book/chapter/verse metadata', () {
      for (final q in bank) {
        expect(q.id, isNotEmpty);
        expect(q.book, isNotEmpty, reason: '${q.id} missing book');
        expect(q.chapter, greaterThan(0), reason: '${q.id} bad chapter');
        expect(q.verseStart, greaterThan(0), reason: '${q.id} bad verseStart');
        expect(q.verseEnd, greaterThanOrEqualTo(q.verseStart), reason: '${q.id} verse range inverted');
        expect(q.reference, matches(RegExp(r'^.+ \d+:\d+(-\d+)?$')), reason: '${q.id} reference malformed');
      }
    });

    test('options are non-empty and correct index is in range', () {
      for (final q in bank) {
        expect(q.options.length, greaterThanOrEqualTo(2));
        expect(q.options.any((o) => o.trim().isEmpty), isFalse);
        expect(q.correctIndex, inInclusiveRange(0, q.options.length - 1));
      }
    });

    test('all four competition categories are represented', () {
      final cats = bank.map((q) => q.category).toSet();
      expect(cats, containsAll([
        QuizCategory.directQuote,
        QuizCategory.chapterAnalysis,
        QuizCategory.multipleChoice,
        QuizCategory.speedRound,
      ]));
    });

    test('all three difficulty tiers are represented', () {
      final diffs = bank.map((q) => q.difficulty).toSet();
      expect(diffs, containsAll([QuizDifficulty.easy, QuizDifficulty.medium, QuizDifficulty.hard]));
    });

    test('fromMap/toMap roundtrip preserves scripture metadata', () {
      final original = bank.first;
      final restored = QuizQuestion.fromMap(original.toMap());
      expect(restored.book, original.book);
      expect(restored.chapter, original.chapter);
      expect(restored.verseStart, original.verseStart);
      expect(restored.verseEnd, original.verseEnd);
      expect(restored.category, original.category);
      expect(restored.difficulty, original.difficulty);
      expect(restored.correctIndex, original.correctIndex);
    });
  });
}
