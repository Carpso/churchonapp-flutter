import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/modules/bible_quiz/data/quiz_hosting_service.dart';

import '../../../../test_mocks.dart';

/// rpc<T>() result carrier that resolves to a plain bool.
class _BoolRpc extends Mock implements PostgrestFilterBuilder<bool> {
  _BoolRpc(this.value);
  final bool value;

  @override
  Future<R> then<R>(FutureOr<R> Function(bool) onValue, {Function? onError}) {
    return Future.value(value).then(onValue, onError: onError);
  }
}

/// rpc<T>() result carrier that resolves to a JSON map.
class _MapRpc extends Mock
    implements PostgrestFilterBuilder<Map<String, dynamic>> {
  _MapRpc(this.value);
  final Map<String, dynamic> value;

  @override
  Future<R> then<R>(
      FutureOr<R> Function(Map<String, dynamic>) onValue,
      {Function? onError}) {
    return Future.value(value).then(onValue, onError: onError);
  }
}

class _FakeTenantNotifier extends CurrentTenantNotifier {
  _FakeTenantNotifier(this._tenant);
  final Tenant? _tenant;

  @override
  Tenant? build() => _tenant;
}

class _FakeProfileNotifier extends ProfileNotifier {
  @override
  AsyncValue<UserProfile?> build() => const AsyncData(null);
}

final _mockClientProvider =
    Provider<SupabaseClient>((_) => throw UnimplementedError());

final _serviceProvider = Provider<QuizHostingService>(
    (ref) => QuizHostingService(ref.read(_mockClientProvider), ref));

Tenant _tenant(String id) => Tenant(
      id: id,
      slug: id,
      name: 'Test Church',
      primaryColor: const Color(0xFFFFDA03),
      accentColor: const Color(0xFFFFDA03),
      surfaceColor: const Color(0xFFFFFFFF),
      fontFamily: 'Roboto',
      darkMode: 'light',
    );

void main() {
  late MockSupabaseClient mockClient;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late ProviderContainer container;
  late QuizHostingService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    container = ProviderContainer(overrides: [
      _mockClientProvider.overrideWithValue(mockClient),
      currentTenantProvider.overrideWith(() => _FakeTenantNotifier(_tenant('t1'))),
      profileProvider.overrideWith(_FakeProfileNotifier.new),
    ]);
    service = container.read(_serviceProvider);
  });

  tearDown(() => container.dispose());

  group('models', () {
    test('QuizQuestionSet parses extraction state', () {
      final s = QuizQuestionSet.fromMap({
        'id': 'set1',
        'title': 'Season Paper',
        'extract_status': 'ready',
        'extracted_count': 42,
        'study_pack_open': false,
        'created_at': '2026-09-10T08:00:00.000Z',
      });
      expect(s.id, 'set1');
      expect(s.extractStatus, 'ready');
      expect(s.extractedCount, 42);
      expect(s.studyPackOpen, isFalse);
    });

    test('QuizTournament defaults + parsing', () {
      final t = QuizTournament.fromMap({
        'id': 'trn1',
        'host_tenant_id': 't1',
        'title': 'Interchurch Cup',
        'visibility': 'invited',
        'status': 'live',
        'question_count': 15,
        'time_per_question': 20,
        'created_at': '2026-09-10T08:00:00.000Z',
      });
      expect(t.id, 'trn1');
      expect(t.hostTenantId, 't1');
      expect(t.visibility, 'invited');
      expect(t.status, 'live');
      expect(t.questionCount, 15);
      expect(t.timePerQuestion, 20);
    });

    test('QuizTournamentMatch parses bracket fields', () {
      final m = QuizTournamentMatch.fromMap({
        'id': 'm1',
        'round': 2,
        'slot': 1,
        'home_user_id': 'u1',
        'away_user_id': 'u2',
        'home_score': 30,
        'away_score': 20,
        'winner_user_id': 'u1',
        'status': 'completed',
      });
      expect(m.round, 2);
      expect(m.homeScore, 30);
      expect(m.winnerUserId, 'u1');
      expect(m.status, 'completed');
    });

    test('QuizEngineLease reports active only when unexpired', () {
      final active = QuizEngineLease.fromMap({
        'id': 'l1',
        'tenant_id': 't1',
        'status': 'active',
        'starts_at': '2026-01-01T00:00:00.000Z',
        'ends_at': '2099-01-01T00:00:00.000Z',
      });
      final expired = QuizEngineLease.fromMap({
        'id': 'l2',
        'tenant_id': 't1',
        'status': 'active',
        'starts_at': '2020-01-01T00:00:00.000Z',
        'ends_at': '2021-01-01T00:00:00.000Z',
      });
      expect(active.isActive, isTrue);
      expect(expired.isActive, isFalse);
    });
  });

  group('tenant-scoped reads', () {
    test('fetchSets filters by the current tenant', () async {
      when(() => mockClient.from('quiz_question_sets'))
          .thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('tenant_id', 't1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false))
          .thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [
        {'id': 'set1', 'title': 'Paper', 'extracted_count': 5},
      ];

      final sets = await service.fetchSets();

      expect(sets, hasLength(1));
      expect(sets.first.title, 'Paper');
      verify(() => mockFilter.eq('tenant_id', 't1')).called(1);
    });

    test('fetchLease returns null when there is no lease', () async {
      when(() => mockClient.from('quiz_engine_leases'))
          .thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('tenant_id', 't1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('ends_at', ascending: false))
          .thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(1)).thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [];

      expect(await service.fetchLease(), isNull);
    });

    test('canHost reflects the tenant_can_host_quiz RPC', () async {
      when(() => mockClient.rpc('tenant_can_host_quiz',
          params: any(named: 'params'))).thenAnswer((_) => _BoolRpc(true));

      expect(await service.canHost(), isTrue);
      verify(() => mockClient.rpc('tenant_can_host_quiz',
          params: {'p_tenant_id': 't1'})).called(1);
    });

    test('canHost is false when the RPC says no', () async {
      when(() => mockClient.rpc('tenant_can_host_quiz',
          params: any(named: 'params'))).thenAnswer((_) => _BoolRpc(false));

      expect(await service.canHost(), isFalse);
    });
  });

  group('createTournament', () {
    test('passes host options through to the RPC', () async {
      when(() => mockClient.rpc('create_quiz_tournament',
              params: any(named: 'params')))
          .thenAnswer((_) => _MapRpc({
                'tournament_id': 'trn9',
                'visibility': 'invited',
              }));

      final res = await service.createTournament(
        title: 'Cup',
        questionSetId: 'set1',
        visibility: 'invited',
      );

      expect(res['tournament_id'], 'trn9');
      verify(() => mockClient.rpc('create_quiz_tournament', params: any(
              named: 'params',
              that: containsPair('p_title', 'Cup'))))
          .called(1);
    });
  });
}
