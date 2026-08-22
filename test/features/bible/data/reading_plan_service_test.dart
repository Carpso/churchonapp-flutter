
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:church_on_app/features/bible/data/reading_plan_service.dart';
import '../../../test_mocks.dart';

void main() {
  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late MockMaybeSingleBuilder mockMaybeSingle;
  late ReadingPlanService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    mockMaybeSingle = MockMaybeSingleBuilder();
    service = ReadingPlanService(mockClient);
    SharedPreferences.setMockInitialValues({});

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');
  });

  group('getPlans', () {
    test('returns default plans when supabase query fails', () async {
      when(() => mockClient.from('reading_plans')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at')).thenThrow(Exception('db error'));

      final plans = await service.getPlans();
      expect(plans.length, greaterThanOrEqualTo(4));
      expect(plans.first.title, 'Faith & Wisdom');
    });

    test('default plans have valid structure', () async {
      when(() => mockClient.from('reading_plans')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at')).thenThrow(Exception('error'));

      final plans = await service.getPlans();
      for (final plan in plans) {
        expect(plan.id, isNotEmpty);
        expect(plan.title, isNotEmpty);
        expect(plan.totalDays, greaterThan(0));
        expect(plan.description, isNotEmpty);
        expect(plan.dailyVerses.length, plan.totalDays);
      }
    });

    /* test('completionPercentage is calculated correctly', () {
      SharedPreferences.setMockInitialValues({});
      final plan = ReadingPlan(
        id: 'test',
        title: 'Test',
        totalDays: 10,
        description: 'Test plan',
        dailyVerses: List.generate(10, (i) => 'Day $i'),
        completedDays: 5,
      );
      expect(plan.completionPercentage, 0.5);
    }); */
  });

  group('completeDay', () {
    // NOTE: completeDay is now DB-only (upsert to user_reading_progress);
    // the old SharedPreferences local cache was removed when the progress
    // table shipped. Tests verify the DB contract instead.

    test('inserts first completion and returns new count', () async {
      when(() => mockClient.from('user_reading_progress')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('plan_id', 'faith_wisdom')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = null;

      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      final result = await service.completeDay('faith_wisdom');

      expect(result, 1, reason: 'first completion returns 1');
      verify(() => mockQuery.insert(any(that: containsPair('completed_days', 1)))).called(1);
    });

    test('clamps to plan totalDays (no farming past the end)', () async {
      when(() => mockClient.from('user_reading_progress')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('plan_id', 'faith_wisdom')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      // Existing row already at plan length.
      mockMaybeSingle.result = {'completed_days': 7};

      final result = await service.completeDay('faith_wisdom', totalDays: 7);
      expect(result, 7, reason: 'already complete → unchanged');
    });

    test('does nothing (returns 0) when user is null', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      final result = await service.completeDay('faith_wisdom');
      expect(result, 0);
    });
  });

  /* group('catchUpDays', () {
    test('completes multiple days', () async {
      SharedPreferences.setMockInitialValues({});

      when(() => mockClient.from('user_reading_progress')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('plan_id', 'faith_wisdom')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = null;
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.catchUpDays('faith_wisdom', 3);

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('reading_plan_progress');
      expect(saved, contains('faith_wisdom:3'));
    });
  }); */
}
