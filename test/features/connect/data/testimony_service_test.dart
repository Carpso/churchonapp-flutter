import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/connect/data/testimony_service.dart';
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
  late MockSingleBuilder mockSingle;
  late TestimonyService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    mockSingle = MockSingleBuilder();
    service = TestimonyService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');
    when(() => mockUser.userMetadata).thenReturn({'full_name': 'Test User'});

    // Catch-all from() returning mockQuery
    when(() => mockClient.from(any())).thenAnswer((_) => mockQuery);

    // Profile query defaults to prevent warning print statements
    final defaultFilter = FakeFilterBuilder();
    when(() => mockQuery.select(any())).thenAnswer((_) => defaultFilter);
    final emptyMaybeSingle = MockMaybeSingleBuilder()..result = null;
    when(() => defaultFilter.maybeSingle()).thenAnswer((_) => emptyMaybeSingle);

    // Functions stub
    final mockFunctions = MockFunctionsClient();
    when(() => mockClient.functions).thenReturn(mockFunctions);
    when(() => mockFunctions.invoke(any(), body: any(named: 'body'))).thenAnswer((_) async => MockFunctionResponse());
  });

  group('addTestimony - submitTestimony', () {
    test('submits testimony with new columns successfully', () async {
      final defaultFilter = FakeFilterBuilder();
      when(() => mockQuery.insert(any())).thenAnswer((_) => defaultFilter);

      await service.submitTestimony('God healed me', null);
      verify(() => mockQuery.insert(any(that: containsPair('content', 'God healed me')))).called(1);
    });

    test('falls back to baseline columns when new columns fail', () async {
      final defaultFilter = FakeFilterBuilder();
      when(() => mockQuery.insert(any(that: containsPair('praised_by', anything)))).thenThrow(Exception('new columns fail'));
      when(() => mockQuery.insert(any(that: isNot(containsPair('praised_by', anything))))).thenAnswer((_) => defaultFilter);

      await service.submitTestimony('God is good', 'https://img.url');
      verify(() => mockQuery.insert(any(that: containsPair('category', 'General')))).called(1);
    });

    test('does nothing when user is null', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      await service.submitTestimony('test', null);
    });
  });

  group('praiseTestimony', () {
    test('adds user to praised_by list with new columns', () async {
      final defaultFilter = FakeFilterBuilder();
      when(() => mockQuery.update(any())).thenAnswer((_) => defaultFilter);

      await service.praiseTestimony('t1', []);
      verify(() => mockQuery.update(any(that: containsPair('praised_by', ['user_1'])))).called(1);
    });

    test('does not add duplicate praise', () async {
      await service.praiseTestimony('t1', ['user_1']);
      verifyNever(() => mockQuery.update(any()));
    });

    test('falls back to likes column when new columns fail', () async {
      final defaultFilter = FakeFilterBuilder();
      when(() => mockQuery.update(any(that: containsPair('praised_by', anything)))).thenThrow(Exception('new cols fail'));
      when(() => mockQuery.update(any(that: containsPair('likes', anything)))).thenAnswer((_) => defaultFilter);

      when(() => mockQuery.select('likes')).thenAnswer((_) => defaultFilter);
      when(() => defaultFilter.single()).thenAnswer((_) => mockSingle);
      mockSingle.result = {'likes': 5};

      await service.praiseTestimony('t1', []);
      verify(() => mockQuery.update(any(that: containsPair('likes', 6)))).called(1);
    });
  });

  group('Testimony model', () {
    test('fromMap parses all fields correctly', () {
      final map = {
        'id': 't1',
        'user_id': 'u1',
        'user_name': 'John',
        'content': 'God is good!',
        'praise_count': 10,
        'praised_by': ['u1', 'u2'],
        'created_at': DateTime.now().toIso8601String(),
      };
      final t = Testimony.fromMap(map);
      expect(t.content, 'God is good!');
      expect(t.praiseCount, 10);
      expect(t.praisedBy.length, 2);
    });
  });
}
