import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:church_on_app/features/bible/data/streak_service.dart';
import '../../../test_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late MockMaybeSingleBuilder mockMaybeSingle;
  late StreakService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    mockMaybeSingle = MockMaybeSingleBuilder();
    service = StreakService(mockClient);
    SharedPreferences.setMockInitialValues({});

    when(() => mockClient.auth).thenReturn(mockAuth);
  });

  group('logStudyActivity', () {
    test('saves streak to local storage', () async {
      when(() => mockClient.from('user_study_streaks')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = null;
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.logStudyActivity('user_1');

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('study_streak_info-user_1');
      expect(saved, isNotNull);
      final decoded = jsonDecode(saved!);
      expect(decoded['currentStreak'], 1);
      expect(decoded['longestStreak'], 1);
    });

    test('increments streak on consecutive days', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      SharedPreferences.setMockInitialValues({
        'study_streak_info-user_1': jsonEncode({
          'userId': 'user_1',
          'currentStreak': 1,
          'longestStreak': 1,
          'lastActivityDate': yesterday.toIso8601String(),
          'activityLog': [yesterday.toIso8601String()],
        }),
      });

      when(() => mockClient.from('user_study_streaks')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = {
        'current_streak': 1,
        'longest_streak': 1,
        'last_activity_date': yesterday.toIso8601String(),
        'activity_log': jsonEncode([yesterday.toIso8601String()]),
      };
      when(() => mockQuery.update(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);

      await service.logStudyActivity('user_1');

      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('study_streak_info-user_1')!);
      expect(saved['currentStreak'], 2);
      expect(saved['longestStreak'], 2);
    });

    test('resets streak when day is skipped', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final twoDaysAgo = today.subtract(const Duration(days: 2));
      SharedPreferences.setMockInitialValues({
        'study_streak_info-user_1': jsonEncode({
          'userId': 'user_1',
          'currentStreak': 5,
          'longestStreak': 5,
          'lastActivityDate': twoDaysAgo.toIso8601String(),
          'activityLog': [twoDaysAgo.toIso8601String()],
        }),
      });

      when(() => mockClient.from('user_study_streaks')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = {
        'current_streak': 5,
        'longest_streak': 5,
        'last_activity_date': twoDaysAgo.toIso8601String(),
        'activity_log': jsonEncode([twoDaysAgo.toIso8601String()]),
      };
      when(() => mockQuery.update(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);

      await service.logStudyActivity('user_1');

      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('study_streak_info-user_1')!);
      expect(saved['currentStreak'], 1);
      expect(saved['longestStreak'], 5);
    });
  });

  group('getStreakInfo', () {
    test('returns streak info from supabase on success', () async {
      when(() => mockClient.from('user_study_streaks')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = {
        'current_streak': 7,
        'longest_streak': 14,
        'last_activity_date': DateTime.now().toIso8601String(),
        'activity_log': jsonEncode([DateTime.now().subtract(const Duration(days: 1)).toIso8601String(), DateTime.now().toIso8601String()]),
      };

      final info = await service.getStreakInfo('user_1');
      expect(info.currentStreak, 7);
      expect(info.longestStreak, 14);
    });

    test('returns empty streak info when no data exists', () async {
      when(() => mockClient.from('user_study_streaks')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = null;

      final info = await service.getStreakInfo('user_1');
      expect(info.currentStreak, 0);
      expect(info.longestStreak, 0);
    });

    test('falls back to local when supabase fails', () async {
      SharedPreferences.setMockInitialValues({
        'study_streak_info-user_1': jsonEncode({
          'userId': 'user_1',
          'currentStreak': 3,
          'longestStreak': 5,
          'lastActivityDate': DateTime.now().toIso8601String(),
          'activityLog': [DateTime.now().toIso8601String()],
        }),
      });

      when(() => mockClient.from('user_study_streaks')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenThrow(Exception('network error'));

      final info = await service.getStreakInfo('user_1');
      expect(info.currentStreak, 3);
      expect(info.longestStreak, 5);
    });

    test('resets current streak to 0 if last activity was more than 1 day ago', () async {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      when(() => mockClient.from('user_study_streaks')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = {
        'current_streak': 10,
        'longest_streak': 14,
        'last_activity_date': twoDaysAgo.toIso8601String(),
        'activity_log': jsonEncode([twoDaysAgo.toIso8601String()]),
      };

      final info = await service.getStreakInfo('user_1');
      expect(info.currentStreak, 0);
      expect(info.longestStreak, 14);
    });
  });

  group('streak milestones', () {
    test('tier returns correct values', () {
      expect(const StreakInfo(currentStreak: 0).tier, '🌱 STARTER');
      expect(const StreakInfo(currentStreak: 3).tier, '🔥 BEGINNER');
      expect(const StreakInfo(currentStreak: 7).tier, '⭐ BRONZE');
      expect(const StreakInfo(currentStreak: 30).tier, '🏆 SILVER');
      expect(const StreakInfo(currentStreak: 100).tier, '👑 GOLD');
      expect(const StreakInfo(currentStreak: 365).tier, '💎 DIAMOND');
    });

    test('motivationalMessage returns appropriate message', () {
      expect(const StreakInfo(currentStreak: 0).motivationalMessage, contains('Start your study journey'));
      expect(const StreakInfo(currentStreak: 7).motivationalMessage, contains('One week streak'));
      expect(const StreakInfo(currentStreak: 365).motivationalMessage, contains('A full year'));
    });
  });

  group('getLast30DaysStatus', () {
    test('returns list of 30 booleans', () {
      final info = const StreakInfo(activityLog: []);
      final status = service.getLast30DaysStatus(info);
      expect(status.length, 30);
    });

    test('marks days with activity as true', () {
      final today = DateTime.now();
      final info = StreakInfo(activityLog: [today]);
      final status = service.getLast30DaysStatus(info);
      expect(status.last, true);
    });
  });
}
