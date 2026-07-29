import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import '../../../test_mocks.dart';

class MockFunctionsClient extends Mock implements FunctionsClient {}
class MockFunctionResponse extends Mock implements FunctionResponse {}

class FakeFilterBuilder extends Mock
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  final List<Map<String, dynamic>> mockResult;
  FakeFilterBuilder([this.mockResult = const []]);

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> neq(String column, Object? value) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(String column, Object? value) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> limit(int value, {String? referencedTable}) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> filter(String column, String operator, Object? value) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> inFilter(String column, List<dynamic> values) => this;

  @override
  Future<R> then<R>(FutureOr<R> Function(List<Map<String, dynamic>>) onValue,
      {Function? onError}) {
    return Future.value(mockResult).then(onValue, onError: onError);
  }
}

void main() {
  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;
  late MockQueryBuilder mockQuery;
  late MockMaybeSingleBuilder mockMaybeSingle;
  late FinanceService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    mockMaybeSingle = MockMaybeSingleBuilder();
    service = FinanceService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');

    // Default catch-all from() returning mockQuery
    when(() => mockClient.from(any())).thenAnswer((_) => mockQuery);

    // Default select/insert/upsert stub returning FakeFilterBuilder
    final defaultFilter = FakeFilterBuilder();
    when(() => mockQuery.select(any())).thenAnswer((_) => defaultFilter);
    when(() => mockQuery.insert(any())).thenAnswer((_) => defaultFilter);
    when(() => mockQuery.upsert(any(),
        onConflict: any(named: 'onConflict'),
        ignoreDuplicates: any(named: 'ignoreDuplicates'))).thenAnswer((_) => defaultFilter);

    when(() => defaultFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
    mockMaybeSingle.result = null;

    // Functions stub
    final mockFunctions = MockFunctionsClient();
    when(() => mockClient.functions).thenReturn(mockFunctions);
    when(() => mockFunctions.invoke(any(), body: any(named: 'body'))).thenAnswer((_) async => MockFunctionResponse());
  });

  group('logTransaction', () {
    test('logs transaction successfully and updates coins', () async {
      await service.logTransaction(50.0, 'offering', 'ref_123');
      verify(() => mockQuery.upsert(any(that: containsPair('amount', 50.0)),
          onConflict: 'reference',
          ignoreDuplicates: true)).called(1);
    });

    test('looks up church treasurer when recipientPhone is null and tenantId provided', () async {
      final defaultFilter = FakeFilterBuilder();
      final churchMaybeSingle = MockMaybeSingleBuilder()
        ..result = {
          'treasurer_phone': '0976847775',
          'name': 'Grace Church',
        };

      when(() => mockQuery.select('treasurer_phone, name')).thenAnswer((_) => defaultFilter);
      when(() => defaultFilter.maybeSingle()).thenAnswer((_) => churchMaybeSingle);

      await service.logTransaction(100.0, 'tithe', 'ref_456', tenantId: 'church_1');
      verify(() => mockQuery.upsert(any(that: containsPair('recipient_phone', '0976847775')),
          onConflict: 'reference',
          ignoreDuplicates: true)).called(1);
    });

    test('does nothing when user is null', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      await service.logTransaction(50.0, 'offering', 'ref');
    });
  });

  group('getTransactionsStream', () {
    test('returns empty stream when user is null', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      final stream = service.getTransactionsStream();
      final txns = await stream.first;
      expect(txns, isEmpty);
    });
  });

  group('Transaction model', () {
    test('fromMap parses all fields', () {
      final map = {
        'id': 't1',
        'user_id': 'u1',
        'amount': 150.0,
        'category': 'tithe',
        'reference': 'ref1',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
      };
      final t = Transaction.fromMap(map);
      expect(t.amount, 150.0);
      expect(t.status, 'completed');
    });
  });
}
