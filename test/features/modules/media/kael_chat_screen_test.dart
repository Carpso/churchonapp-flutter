import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/modules/media/presentation/kael_chat_screen.dart';
import 'package:church_on_app/features/modules/media/data/ai_chat_service.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import '../../../test_mocks.dart';

class MockAiChatService extends Mock implements AiChatService {}

class FakeSupabaseService extends Mock implements SupabaseService {
  final SupabaseClient mockClient;
  FakeSupabaseService(this.mockClient);

  @override
  SupabaseClient get client => mockClient;
}

void main() {
  late MockAiChatService mockChatService;
  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;

  setUp(() {
    mockChatService = MockAiChatService();
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.email).thenReturn('user@example.com');

    when(() => mockChatService.createSession(any())).thenAnswer((_) async => 'session_1');
    when(() => mockChatService.getMessagesStream(any())).thenAnswer((_) => Stream.value(<AiChatMessage>[]));
  });

  testWidgets('Kael Chat screen renders without error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiChatServiceProvider.overrideWithValue(mockChatService),
          supabaseServiceProvider.overrideWithValue(FakeSupabaseService(mockClient)),
        ],
        child: const MaterialApp(home: KaelChatScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(KaelChatScreen), findsOneWidget);
  });

  testWidgets('Kael Chat screen has AppBar', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiChatServiceProvider.overrideWithValue(mockChatService),
          supabaseServiceProvider.overrideWithValue(FakeSupabaseService(mockClient)),
        ],
        child: const MaterialApp(home: KaelChatScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);
  });
}
