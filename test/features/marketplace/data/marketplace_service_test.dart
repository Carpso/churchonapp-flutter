import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/marketplace/data/marketplace_service.dart';
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
  FakeFilterBuilder([this.mockResult = const []]);

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> neq(String column, Object? value) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(String column, Object? value) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> limit(int value, {String? referencedTable}) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> order(String column, {bool ascending = false, bool nullsFirst = false, String? referencedTable}) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> range(int from, int to, {String? referencedTable}) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> inFilter(String column, List values, {String? referencedTable}) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> or(String filters, {String? referencedTable}) => this;

  @override
  Future<R> then<R>(FutureOr<R> Function(List<Map<String, dynamic>>) onValue,
      {Function? onError}) {
    return Future.value(mockResult).then(onValue, onError: onError);
  }
}

void main() {
  late FakeSupabaseClient mockClient;
  late MockQueryBuilder mockQuery;
  late FakeFilterBuilder defaultFilter;
  late MarketplaceService service;

  setUp(() {
    mockQuery = MockQueryBuilder();
    mockClient = FakeSupabaseClient(mockQuery);
    defaultFilter = FakeFilterBuilder();
    service = MarketplaceService(mockClient);

    when(() => mockQuery.select(any())).thenAnswer((_) => defaultFilter);
    when(() => mockQuery.insert(any())).thenAnswer((_) => defaultFilter);
  });

  group('fetchProducts', () {
    test('returns products from supabase', () async {
      final customFilter = FakeFilterBuilder([
        {
          'id': 'p1',
          'name': 'Piano',
          'price': 500.0,
          'category': 'Music',
        },
      ]);
      when(() => mockQuery.select(any())).thenAnswer((_) => customFilter);

      final products = await service.fetchProducts(category: 'Music', marketType: 'general');
      expect(products.length, 1);
      expect(products.first.name, 'Piano');
    });

    test('returns all products when category is all', () async {
      final customFilter = FakeFilterBuilder([]);
      when(() => mockQuery.select(any())).thenAnswer((_) => customFilter);

      final products = await service.fetchProducts(category: 'all');
      expect(products, isEmpty);
    });

    test('returns empty list on error', () async {
      final customFilter = FakeFilterBuilder([]);
      when(() => mockQuery.select(any())).thenAnswer((_) => customFilter);

      final products = await service.fetchProducts();
      expect(products, isEmpty);
    });
  });

  group('postProduct', () {
    test('inserts a product', () async {
      await service.postProduct({'name': 'Guitar', 'price': 300.0});
      verify(() => mockQuery.insert(any())).called(1);
    });
  });

  group('MarketProduct model', () {
    test('fromMap parses all fields', () {
      final map = {
        'id': 'p1',
        'name': 'Bible',
        'price': 25.0,
        'category': 'Books',
        'image': 'bible.jpg',
        'description': 'Holy Bible',
        'vendorName': 'Shop',
        'vendorId': 'v1',
        'condition': 'New',
        'marketType': 'general',
        'isCurated': false,
      };
      final product = MarketProduct.fromMap(map);
      expect(product.name, 'Bible');
      expect(product.price, 25.0);
    });
  });
}
