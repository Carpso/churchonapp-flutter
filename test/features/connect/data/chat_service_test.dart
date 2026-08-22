import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/connect/data/chat_service.dart';
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
  late ChatService service;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    service = ChatService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');

    // Default catch-all stub for client tables returning mock query builder
    when(() => mockClient.from(any())).thenAnswer((_) => mockQuery);

    // Default select/insert stub returning a FakeFilterBuilder (using thenAnswer because it implements Future)
    final defaultFilter = FakeFilterBuilder();
    when(() => mockQuery.select(any())).thenAnswer((_) => defaultFilter);
    when(() => mockQuery.insert(any())).thenAnswer((_) => defaultFilter);

    final emptyMaybeSingle = MockMaybeSingleBuilder()..result = null;
    when(() => defaultFilter.maybeSingle()).thenAnswer((_) => emptyMaybeSingle);

    // Stub functions client for FCM notifications
    final mockFunctions = MockFunctionsClient();
    when(() => mockClient.functions).thenReturn(mockFunctions);
    when(() => mockFunctions.invoke(any(), body: any(named: 'body'))).thenAnswer((_) async => MockFunctionResponse());
  });

  group('sendMessage', () {
    test('sends a 1-to-1 message successfully', () async {
      await service.sendMessage('receiver_1', 'Hello!');
      verify(() => mockQuery.insert(any(that: allOf(
        containsPair('sender_id', 'user_1'),
        containsPair('receiver_id', 'receiver_1'),
        containsPair('content', 'Hello!'),
      )))).called(1);
    });

    test('throws when user is null (auth contract)', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      expect(
        () => service.sendMessage('receiver_1', 'test'),
        throwsA(isA<Exception>()),
      );
    });

    test('sends message with optional media parameters', () async {
      await service.sendMessage(
        'receiver_1',
        'Check this',
        mediaUrl: 'https://example.com/img.jpg',
        mediaType: 'image',
        fileName: 'photo.jpg',
      );

      verify(() => mockQuery.insert(any(that: allOf(
        containsPair('media_url', 'https://example.com/img.jpg'),
        containsPair('media_type', 'image'),
        containsPair('file_name', 'photo.jpg'),
      )))).called(1);
    });
  });

  group('sendGroupMessage', () {
    test('sends group message successfully', () async {
      await service.sendGroupMessage('group_1', 'Hello everyone!');
      verify(() => mockQuery.insert(any(that: allOf(
        containsPair('community_group_id', 'group_1'),
        containsPair('content', 'Hello everyone!'),
      )))).called(1);
    });

    test('throws when user is null (auth contract)', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      expect(
        () => service.sendGroupMessage('group_1', 'test'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('fetchChurchMembers', () {
    test('returns list of members excluding current user', () async {
      const memberColumns = 'id, full_name, avatar_url, role, tenant_id';
      final myProfileSingle = MockMaybeSingleBuilder()..result = {'tenant_id': 'tenant_1'};
      final tenantFilter = FakeFilterBuilder();

      // Profile lookup for current user's tenant.
      when(() => mockQuery.select('tenant_id')).thenAnswer((_) => tenantFilter);
      when(() => tenantFilter.maybeSingle()).thenAnswer((_) => myProfileSingle);

      // Members listing scoped by tenant.
      final membersFilter = FakeFilterBuilder([
        {'id': 'u2', 'full_name': 'Member 2', 'role': 'member'},
      ]);
      when(() => mockQuery.select(memberColumns)).thenAnswer((_) => membersFilter);
      // eq/neq are overridden on FakeFilterBuilder (return this) — no stub needed.

      final members = await service.fetchChurchMembers(tenantId: 'tenant_1');
      expect(members.length, 1);
      expect(members.first['full_name'], 'Member 2');
    });

    test('returns empty list when user is null', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      final members = await service.fetchChurchMembers();
      expect(members, isEmpty);
    });
  });

  group('ChatMessage model', () {
    Map<String, dynamic> msgMap(String senderId) => {
          'id': 'msg1',
          'content': 'Hello',
          'sender_id': senderId,
          'profiles': {'full_name': 'John', 'avatar_url': null},
          'created_at': DateTime.now().toIso8601String(),
        };

    test('fromMap parses message correctly', () {
      final msg = ChatMessage.fromMap(msgMap('u1'), 'u2');
      expect(msg.text, 'Hello');
      expect(msg.isMe, false);
      expect(msg.senderName, 'John');
    });

    test('marks message as isMe when sender matches current user', () {
      final msg = ChatMessage.fromMap(msgMap('u1'), 'u1');
      expect(msg.isMe, true);
    });
  });
}
