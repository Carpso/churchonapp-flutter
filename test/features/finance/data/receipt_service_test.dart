import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/finance/data/receipt_service.dart';
import '../../../test_mocks.dart';

class FakeSupabaseClient extends Mock implements SupabaseClient {
  final SupabaseQueryBuilder queryBuilder;
  FakeSupabaseClient(this.queryBuilder);

  @override
  SupabaseQueryBuilder from(String table) => queryBuilder;
}

class FakeFilterBuilder extends Mock
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  final List<Map<String, dynamic>> mockResult;
  final Map<String, dynamic>? mockMaybeSingleResult;

  FakeFilterBuilder([this.mockResult = const [], this.mockMaybeSingleResult]);

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> neq(String column, Object? value) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(String column, Object? value) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> limit(int value, {String? referencedTable}) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> order(String column, {bool ascending = false, bool nullsFirst = false, String? referencedTable}) => this;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    return MockMaybeSingleBuilder()..result = mockMaybeSingleResult;
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(List<Map<String, dynamic>>) onValue,
      {Function? onError}) {
    return Future.value(mockResult).then(onValue, onError: onError);
  }
}

void main() {
  late FakeSupabaseClient mockClient;
  late MockQueryBuilder mockQuery;

  setUp(() {
    mockQuery = MockQueryBuilder();
    mockClient = FakeSupabaseClient(mockQuery);
  });

  group('getReceipt', () {
    test('returns full receipt when transaction and logs exist', () async {
      final service = ReceiptService(mockClient);

      // Unique filter builders with their concrete single results
      final txnFilter = FakeFilterBuilder([], {
        'id': 'txn_1',
        'amount': 100.0,
        'category': 'offering',
        'status': 'completed',
        'reference': 'ref_1',
        'created_at': DateTime.now().toIso8601String(),
      });
      
      final logFilter = FakeFilterBuilder([], {
        'id': 'log_1',
        'platform_fee': 5.0,
        'net_payout': 95.0,
      });

      // Return txnFilter first and logFilter second
      var selectCallCount = 0;
      when(() => mockQuery.select()).thenAnswer((_) {
        selectCallCount++;
        return selectCallCount == 1 ? txnFilter : logFilter;
      });

      final receipt = await service.getReceipt('ref_1');
      expect(receipt, isNotNull);
      expect(receipt!.amount, 100.0);
      expect(receipt.platformFee, 5.0);
      expect(receipt.netPayout, 95.0);
    });

    test('returns null when transaction not found', () async {
      final service = ReceiptService(mockClient);
      final emptyFilter = FakeFilterBuilder([], null);

      when(() => mockQuery.select()).thenAnswer((_) => emptyFilter);

      final receipt = await service.getReceipt('nonexistent');
      expect(receipt, isNull);
    });

    test('fetches church info when tenantId present', () async {
      final service = ReceiptService(mockClient);

      final txnFilter = FakeFilterBuilder([], {
        'id': 'txn_2',
        'amount': 50.0,
        'category': 'tithe',
        'status': 'completed',
        'reference': 'ref_2',
        'tenant_id': 'church_1',
        'created_at': DateTime.now().toIso8601String(),
      });

      final logFilter = FakeFilterBuilder([], null);
      final churchFilter = FakeFilterBuilder([], {'name': 'Grace Church'});

      var selectCallCount = 0;
      when(() => mockQuery.select()).thenAnswer((_) {
        selectCallCount++;
        return selectCallCount == 1 ? txnFilter : logFilter;
      });
      when(() => mockQuery.select('name')).thenAnswer((_) => churchFilter);

      final receipt = await service.getReceipt('ref_2');
      expect(receipt, isNotNull);
      expect(receipt!.tenantName, 'Grace Church');
    });
  });

  group('getReceiptsForUser', () {
    test('returns list of receipts for user', () async {
      final service = ReceiptService(mockClient);

      final transactionData = {
        'id': 'txn_3',
        'amount': 200.0,
        'category': 'pledge',
        'status': 'completed',
        'reference': 'ref_3',
        'created_at': DateTime.now().toIso8601String(),
      };

      final customFilter = FakeFilterBuilder([transactionData], null);
      when(() => mockQuery.select()).thenAnswer((_) => customFilter);

      final receipts = await service.getReceiptsForUser('user_1');
      expect(receipts, isNotEmpty);
      expect(receipts.first.amount, 200.0);
    });

    test('returns empty list when no transactions', () async {
      final service = ReceiptService(mockClient);
      final customFilter = FakeFilterBuilder([], null);
      when(() => mockQuery.select()).thenAnswer((_) => customFilter);

      final receipts = await service.getReceiptsForUser('user_1');
      expect(receipts, isEmpty);
    });
  });
}
