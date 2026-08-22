
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/admin/data/admin_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockAuth extends Mock implements GoTrueClient {}
class MockUser extends Mock implements User {}
class MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}

// ignore: must_be_immutable
class MockFilterBuilder extends Mock
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  List<Map<String, dynamic>> returnData = [];

  @override
  Future<T> then<T>(
    FutureOr<T> Function(List<Map<String, dynamic>>) onValue, {
    Function? onError,
  }) {
    return Future.value(returnData).then(onValue, onError: onError);
  }
}

// ignore: must_be_immutable
class MockMaybeSingleBuilder extends Mock
    implements PostgrestTransformBuilder<Map<String, dynamic>?> {
  Map<String, dynamic>? result;

  @override
  Future<R> then<R>(FutureOr<R> Function(Map<String, dynamic>?) onValue,
      {Function? onError}) {
    return Future.value(result).then(onValue, onError: onError);
  }
}

void main() {
  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late AdminService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    service = AdminService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('admin_1');
  });

  group('getTotalRidesCount', () {
    test('returns count of ride requests', () async {
      mockFilter.returnData = [
        {'id': '1'}, {'id': '2'}, {'id': '3'},
      ];
      when(() => mockClient.from('ride_requests')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select('id')).thenAnswer((_) => mockFilter);

      final count = await service.getTotalRidesCount();
      expect(count, 3);
    });
  });

  group('getPendingDeliveriesCount', () {
    test('returns count of pending deliveries', () async {
      mockFilter.returnData = [
        {'id': '1'},
      ];
      when(() => mockClient.from('delivery_requests')).thenAnswer((_) => mockQuery);
      // Service selects 'id' then filters status=pending.
      when(() => mockQuery.select('id')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('status', 'pending')).thenAnswer((_) => mockFilter);

      final count = await service.getPendingDeliveriesCount();
      expect(count, 1);
    });
  });

  group('getActiveCouriersCount', () {
    test('returns count of active couriers', () async {
      mockFilter.returnData = [
        {'id': '1'}, {'id': '2'},
      ];
      when(() => mockClient.from('profiles')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select('id')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('is_work_mode', true)).thenAnswer((_) => mockFilter);

      final count = await service.getActiveCouriersCount();
      expect(count, 2);
    });
  });

  group('getTotalTransactionVolume', () {
    test('returns sum of absolute amounts', () async {
      mockFilter.returnData = [
        {'amount': 100.0},
        {'amount': -50.0},
        {'amount': 25.0},
      ];
      when(() => mockClient.from('wallet_transactions')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select('amount')).thenAnswer((_) => mockFilter);

      final total = await service.getTotalTransactionVolume();
      expect(total, 175.0);
    });
  });

  group('getMonthlyFinancialStats', () {
    test('returns categorized financial stats', () async {
      mockFilter.returnData = [
        {'amount': 100.0, 'type': 'ride_payment'},
        {'amount': -50.0, 'type': 'delivery_earning'},
        {'amount': 200.0, 'type': 'tithe'},
      ];
      when(() => mockClient.from('wallet_transactions')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select('amount, type')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.gte('created_at', any())).thenAnswer((_) => mockFilter);

      final stats = await service.getMonthlyFinancialStats();
      expect(stats['rides'], 100.0);
      expect(stats['deliveries'], 50.0);
      expect(stats['tithes'], 200.0);
    });
  });

  group('requestPayout', () {
    test('inserts payout request', () async {
      when(() => mockClient.from('payout_requests')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.requestPayout(amount: 500.0, mobileNumber: '0976847775', network: 'MTN');
      verify(() => mockQuery.insert(any(that: containsPair('amount', 500.0)))).called(1);
    });
  });

  group('updateUserRole', () {
    test('updates role in profiles after caller authorization', () async {
      // Service flow: caller lookup (role+tenant) -> target lookup (tenant)
      // -> security check -> update. Caller is superadmin so any tenant OK.
      final callerSingle = MockMaybeSingleBuilder()
        ..result = {'role': 'superadmin', 'tenant_id': 't1'};
      final targetSingle = MockMaybeSingleBuilder()
        ..result = {'tenant_id': 'caller-tenant'};

      when(() => mockClient.from('profiles')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select('role, tenant_id')).thenAnswer((_) => mockFilter);
      // Target lookup selects tenant only.
      when(() => mockQuery.select('tenant_id')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('id', 'admin_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('id', 'user_1')).thenAnswer((_) => mockFilter);

      // Distinguish caller vs target by which id filter was last applied.
      var lastFilteredId = '';
      when(() => mockFilter.eq('id', any())).thenAnswer((inv) {
        lastFilteredId = inv.positionalArguments[1] as String;
        return mockFilter;
      });
      when(() => mockFilter.maybeSingle()).thenAnswer((_) {
        return lastFilteredId == 'admin_1' ? callerSingle : targetSingle;
      });

      when(() => mockQuery.update(any())).thenAnswer((_) => mockFilter);

      await service.updateUserRole('user_1', 'pastor');
      verify(() => mockQuery.update(any(that: containsPair('role', 'pastor')))).called(1);
    });
  });
}
