import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/modules/media/data/ai_chat_service.dart';
import '../../../../test_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late MockSingleBuilder mockSingle;
  late MockSupabaseStreamBuilder mockStream;

  late AiChatService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    mockSingle = MockSingleBuilder();
    mockStream = MockSupabaseStreamBuilder();

    service = AiChatService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');
  });

  group('getMessagesStream', () {
    test('returns stream from supabase', () {
      when(() => mockClient.from('ai_chat_messages')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.stream(primaryKey: ['id'])).thenAnswer((_) => mockStream);
      when(() => mockStream.eq('session_id', 'session_1')).thenAnswer((_) => mockStream);
      when(() => mockStream.order('created_at', ascending: true)).thenAnswer((_) => mockStream);
      mockStream.streamResult = Stream.value([
        {'id': 'm1', 'content': 'Hello', 'role': 'user', 'created_at': DateTime.now().toIso8601String()},
      ]);

      final stream = service.getMessagesStream('session_1');
      expect(stream, isA<Stream<List<AiChatMessage>>>());
    });
  });

  group('createSession', () {
    test('creates session and returns id', () async {
      when(() => mockClient.from('ai_chat_sessions')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(
        {
          'user_id': 'user_1',
          'title': 'Prayer Chat',
        },
        defaultToNull: true,
      )).thenAnswer((_) => mockFilter);
      when(() => mockFilter.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.single()).thenAnswer((_) => mockSingle);
      mockSingle.result = {'id': 'session_1'};

      final sessionId = await service.createSession('Prayer Chat');
      expect(sessionId, 'session_1');
    });

    test('throws when not authenticated', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      expect(
        () => service.createSession('Chat'),
        throwsA(isA<Exception>()),
      );
    });
  });

  /* group('sendMessage', () {
    test('sends message and inserts assistant response', () async {
      when(() => mockClient.from('ai_chat_messages')).thenAnswer((_) => mockQuery);
      
      // Stub the two inserts
      when(() => mockQuery.insert(
        {
          'session_id': 'session_1',
          'role': 'user',
          'content': 'Pray for me',
        },
        defaultToNull: true,
      )).thenAnswer((_) => mockFilter);

      when(() => mockQuery.insert(
        {
          'session_id': 'session_1',
          'role': 'assistant',
          'content': 'God bless you!',
        },
        defaultToNull: true,
      )).thenAnswer((_) => mockFilter);

      // Stub the fetch history query
      when(() => mockQuery.select('role, content')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('session_id', 'session_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(20)).thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [];

      when(() => mockGemini.chat('Pray for me', history: [])).thenAnswer((_) async => 'God bless you!');

      await service.sendMessage('session_1', 'Pray for me');

      verify(() => mockQuery.insert(
        {
          'session_id': 'session_1',
          'role': 'user',
          'content': 'Pray for me',
        },
        defaultToNull: true,
      )).called(1);

      verify(() => mockQuery.insert(
        {
          'session_id': 'session_1',
          'role': 'assistant',
          'content': 'God bless you!',
        },
        defaultToNull: true,
      )).called(1);
    });

    test('uses fallback when gemini returns empty', () async {
      when(() => mockClient.from('ai_chat_messages')).thenAnswer((_) => mockQuery);

      when(() => mockQuery.insert(
        {
          'session_id': 'session_1',
          'role': 'user',
          'content': 'prayer',
        },
        defaultToNull: true,
      )).thenAnswer((_) => mockFilter);

      when(() => mockQuery.insert(
        {
          'session_id': 'session_1',
          'role': 'assistant',
          'content': "May the Lord hear your prayers and grant you peace. 'Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God.' — Philippians 4:6. How can I pray with you today?",
        },
        defaultToNull: true,
      )).thenAnswer((_) => mockFilter);

      // Stub the fetch history query
      when(() => mockQuery.select('role, content')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('session_id', 'session_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(20)).thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [];

      when(() => mockGemini.chat('prayer', history: [])).thenAnswer((_) async => '');

      await service.sendMessage('session_1', 'prayer');

      verify(() => mockQuery.insert(
        {
          'session_id': 'session_1',
          'role': 'user',
          'content': 'prayer',
        },
        defaultToNull: true,
      )).called(1);

      verify(() => mockQuery.insert(
        {
          'session_id': 'session_1',
          'role': 'assistant',
          'content': "May the Lord hear your prayers and grant you peace. 'Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God.' — Philippians 4:6. How can I pray with you today?",
        },
        defaultToNull: true,
      )).called(1);
    });
  }); */
}
