import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/finance/data/offering_basket_service.dart';
import '../../../test_mocks.dart';

/// rpc<T>() carrier that resolves to a JSON map (what the real RPCs return).
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

void main() {
  late MockSupabaseClient mockClient;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late OfferingBasketService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    service = OfferingBasketService(mockClient);
  });

  group('OfferingBasket model', () {
    test('parses a tenant basket', () {
      final b = OfferingBasket.fromMap({
        'id': 'b1',
        'tenant_id': 'tenant_1',
        'name': 'Tithe',
        'code': 'TITHE',
        'icon': 'coins',
        'color': '#FFDA03',
        'is_active': true,
        'sort_order': 1,
      });
      expect(b.id, 'b1');
      expect(b.name, 'Tithe');
      expect(b.code, 'TITHE');
      expect(b.isOrgWide, isFalse);
      expect(b.isActive, isTrue);
    });

    test('detects organisation-wide baskets (tenant_id null)', () {
      final b = OfferingBasket.fromMap({
        'id': 'b2',
        'tenant_id': null,
        'name': 'Missions',
      });
      expect(b.isOrgWide, isTrue);
      expect(b.color, '#FFDA03');
      expect(b.icon, 'hand-heart');
    });
  });

  group('BasketSummaryRow model', () {
    test('parses summary totals', () {
      final r = BasketSummaryRow.fromMap({
        'basket_type_id': 'b1',
        'basket_name': 'Sunday Offering',
        'basket_code': 'SUN',
        'scope': 'organisation',
        'sessions': 3,
        'total_amount': 1250.5,
        'last_taken_at': '2026-09-01T10:00:00.000Z',
      });
      expect(r.basketName, 'Sunday Offering');
      expect(r.scope, 'organisation');
      expect(r.sessions, 3);
      expect(r.totalAmount, 1250.5);
      expect(r.lastTakenAt, isNotNull);
    });
  });

  group('fetchBaskets', () {
    test('scopes to the given tenant (guards the staff RLS bypass)', () async {
      when(() => mockClient.from('offering_basket_types'))
          .thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('is_active', true)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('tenant_id', 't1'))
          .thenAnswer((_) => mockFilter);
      when(() => mockFilter.order(any(), ascending: any(named: 'ascending')))
          .thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [
        {'id': 'b1', 'tenant_id': 't1', 'name': 'Tithe', 'sort_order': 1},
      ];

      final baskets = await service.fetchBaskets(tenantId: 't1');

      expect(baskets, hasLength(1));
      expect(baskets.first.name, 'Tithe');
      // The whole point: never return another church's baskets.
      verify(() => mockFilter.eq('tenant_id', 't1')).called(1);
      verify(() => mockFilter.order('sort_order', ascending: true)).called(1);
      verify(() => mockFilter.order('name', ascending: true)).called(1);
    });

    test('with no tenant context only organisation-wide baskets are read',
        () async {
      when(() => mockClient.from('offering_basket_types'))
          .thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('is_active', true)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.isFilter('tenant_id', null))
          .thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('organization_id', 'o1'))
          .thenAnswer((_) => mockFilter);
      when(() => mockFilter.order(any(), ascending: any(named: 'ascending')))
          .thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [];

      await service.fetchBaskets(organizationId: 'o1');

      verify(() => mockFilter.isFilter('tenant_id', null)).called(1);
      verify(() => mockFilter.eq('organization_id', 'o1')).called(1);
    });

    test('skips the is_active filter when activeOnly is false', () async {
      when(() => mockClient.from('offering_basket_types'))
          .thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.isFilter('tenant_id', null))
          .thenAnswer((_) => mockFilter);
      when(() => mockFilter.order(any(), ascending: any(named: 'ascending')))
          .thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [];

      await service.fetchBaskets(activeOnly: false);

      verifyNever(() => mockFilter.eq('is_active', any()));
    });
  });

  group('openSession', () {
    test('calls open_offering_session and returns the session id', () async {
      when(() => mockClient.rpc('open_offering_session',
              params: any(named: 'params')))
          .thenAnswer((_) => _MapRpc({'session_id': 's1', 'basket': 'Tithe'}));

      final session = await service.openSession(
        basketTypeId: 'b1',
        title: 'Sunday Morning',
      );

      expect(session.id, 's1');
      expect(session.basketName, 'Tithe');
      expect(session.isOpen, isTrue);
      verify(() => mockClient.rpc('open_offering_session', params: {
            'p_basket_type_id': 'b1',
            'p_title': 'Sunday Morning',
          })).called(1);
    });

    test('throws when the RPC returns no session_id', () async {
      when(() => mockClient.rpc('open_offering_session',
              params: any(named: 'params')))
          .thenAnswer((_) => _MapRpc({'basket': 'Tithe'}));

      expect(
        () => service.openSession(basketTypeId: 'b1'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('recordContribution', () {
    test('returns true when the server records the gift', () async {
      when(() => mockClient.rpc('record_offering_contribution',
              params: any(named: 'params')))
          .thenAnswer(
              (_) => _MapRpc({'recorded': true, 'total': 100, 'count': 1}));

      final ok = await service.recordContribution(
        sessionId: 's1',
        amount: 100,
        paymentRef: 'REF-1',
      );

      expect(ok, isTrue);
      verify(() => mockClient.rpc('record_offering_contribution', params: {
            'p_session_id': 's1',
            'p_amount': 100.0,
            'p_payment_ref': 'REF-1',
            'p_method': 'momo',
          })).called(1);
    });

    test('returns false (never throws) on RPC failure', () async {
      when(() => mockClient.rpc('record_offering_contribution',
          params: any(named: 'params'))).thenThrow(Exception('db down'));

      final ok = await service.recordContribution(sessionId: 's1', amount: 50);

      expect(ok, isFalse);
    });
  });

  group('fetchSummary', () {
    test('maps get_basket_summary rows', () async {
      when(() => mockClient.rpc('get_basket_summary',
          params: any(named: 'params'))).thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [
        {
          'basket_name': 'Tithe',
          'scope': 'tenant',
          'sessions': 2,
          'total_amount': 800,
        },
      ];

      final rows = await service.fetchSummary(tenantId: 't1', days: 30);

      expect(rows, hasLength(1));
      expect(rows.first.basketName, 'Tithe');
      expect(rows.first.totalAmount, 800);
      verify(() => mockClient.rpc('get_basket_summary', params: {
            'p_tenant_id': 't1',
            'p_org_id': null,
            'p_days': 30,
          })).called(1);
    });
  });

  group('fetchActiveSession', () {
    test('returns null when there is no open session', () async {
      when(() => mockClient.from('offering_sessions'))
          .thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('status', 'open')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order(any(), ascending: any(named: 'ascending')))
          .thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(any())).thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [];

      final active = await service.fetchActiveSession();

      expect(active, isNull);
      verify(() => mockFilter.limit(1)).called(1);
    });
  });
}
