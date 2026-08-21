import 'package:flutter_test/flutter_test.dart';

import 'package:church_on_app/features/modules/bible_quiz/engine/quiz_engine.dart';
import 'package:church_on_app/features/modules/bible_quiz/engine/quiz_models.dart';
import 'package:church_on_app/features/modules/bible_quiz/engine/mock_quiz_repository.dart';

void main() {
  group('QuizRepository (mock, deterministic)', () {
    final repo = MockQuizRepository();

    test('loadQuestions returns deterministic order — no flaky tests', () async {
      final a = await repo.loadQuestions(mode: QuizMode.practice, count: 5);
      final b = await repo.loadQuestions(mode: QuizMode.practice, count: 5);
      expect(a.map((x) => x.id).toList(), b.map((x) => x.id).toList());
    });

    test('respects count limit', () async {
      final qs = await repo.loadQuestions(mode: QuizMode.practice, count: 3);
      expect(qs.length, 3);
    });

    test('filters by category', () async {
      final qs = await repo.loadQuestions(mode: QuizMode.practice, category: QuizCategory.directQuote);
      expect(qs, isNotEmpty);
      expect(qs.every((q) => q.category == QuizCategory.directQuote), isTrue);
    });

    test('filters by difficulty', () async {
      final qs = await repo.loadQuestions(mode: QuizMode.practice, difficulty: QuizDifficulty.hard);
      expect(qs, isNotEmpty);
      expect(qs.every((q) => q.difficulty == QuizDifficulty.hard), isTrue);
    });

    test('tournament mode without token throws ArgumentError', () async {
      expect(
        () => repo.loadQuestions(mode: QuizMode.tournament),
        throwsArgumentError,
      );
      // With token → succeeds
      final qs = await repo.loadQuestions(mode: QuizMode.tournament, tenantToken: 'tok-abc');
      expect(qs, isNotEmpty);
    });

    test('activeTournamentsForTenant returns an active tournament for that tenant', () async {
      final ts = await repo.activeTournamentsForTenant('tenant-a');
      expect(ts, isNotEmpty);
      expect(ts.first.tenantId, 'tenant-a');
      expect(ts.first.isActive, isTrue);
    });
  });

  group('QuizLeaderboard tie-breakers (WBQA order)', () {
    test('rank order: score desc → wrong asc → avg response asc → completedAt asc', () {
      final lb = MockLeaderboards.forRegion('ZM-LUSAKA');
      final ids = lb.entries.map((e) => e.userId).toList();
      // u-4 excluded by region filter; u-1/u-2/u-3 all 120 pts:
      //   u-3 beats u-2 on completion time despite identical everything else.
      // u-6 (90pts) ranks below the 120s.
      expect(ids.indexOf('u-3'), lessThan(ids.indexOf('u-2')));
      expect(ids.indexOf('u-2'), lessThan(ids.indexOf('u-1'))); // fewer wrong? same wrong(1), faster avg 1900 vs 2100
      expect(ids.indexOf('u-1'), lessThan(ids.indexOf('u-6')));
    });

    test('region filter returns only scoped entries', () {
      final lb = MockLeaderboards.forRegion('GLOBAL');
      expect(lb.entries, hasLength(1));
      expect(lb.entries.single.userId, 'u-4');
    });

    test('unknown region yields empty board with valid rankOf -1', () {
      final lb = MockLeaderboards.forRegion('KE-NAIROBI');
      expect(lb.entries, isEmpty);
      expect(lb.rankOf('u-1'), -1);
    });

    test('rankOf resolves correct 1-based positions', () {
      final lb = MockLeaderboards.forRegion('ZM-LUSAKA');
      final first = lb.entries.first;
      expect(lb.rankOf(first.userId), 1);
      final last = lb.entries.last;
      expect(lb.rankOf(last.userId), lb.entries.length);
    });
  });

  group('TenantTournament access & lifecycle', () {
    test('isActive only within start/end window', () {
      final now = DateTime.now();
      final active = TenantTournament(
        id: 't', name: 'n', tenantId: 'x',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 1)),
      );
      final upcoming = TenantTournament(
        id: 't2', name: 'n2', tenantId: 'x',
        startsAt: now.add(const Duration(days: 1)),
        endsAt: now.add(const Duration(days: 2)),
      );
      expect(active.isActive, isTrue);
      expect(active.isUpcoming, isFalse);
      expect(upcoming.isUpcoming, isTrue);
      expect(upcoming.isActive, isFalse);
    });

    test('defaults carry branded trophy + voucher + prize coins', () {
      final t = TenantTournament(id: 't', name: 'n', tenantId: 'x', startsAt: DateTime.now(), endsAt: DateTime.now());
      expect(t.trophyLabel, isNotEmpty);
      expect(t.voucherDiscountPercent, greaterThan(0));
      expect(t.prizeCoinsFirst, greaterThan(0));
    });
  });
}
