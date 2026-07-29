import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/home/presentation/home_screen.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/notification_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/home/data/sermon_service.dart';
import 'package:church_on_app/features/home/data/news_service.dart';
import 'package:church_on_app/features/home/data/live_streaming_service.dart';
import 'package:church_on_app/features/bible/data/bible_verse_service.dart';

// --- Lightweight Http Mock for Network Images ---
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient();
  }
}

class _MockHttpClient extends Mock implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> get(String host, int port, String path) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _MockHttpClientRequest();
}

class _MockHttpClientRequest extends Mock implements HttpClientRequest {
  @override
  HttpHeaders get headers => _MockHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Mock implements HttpHeaders {}

class _MockHttpClientResponse extends Mock implements HttpClientResponse {
  static const List<int> _transparentImage = [
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 
    0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 204, 137, 
    0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 96, 0, 0, 0, 
    2, 0, 1, 73, 175, 168, 14, 0, 0, 0, 0, 73, 69, 78, 68, 
    174, 66, 96, 130
  ];

  @override
  int get statusCode => 200;
  @override
  int get contentLength => _transparentImage.length;
  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.fromIterable([_transparentImage]).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

// --- Riverpod Mocks ---
class MockProfileNotifier extends ProfileNotifier {
  @override
  AsyncValue<UserProfile?> build() => const AsyncValue.data(null);
  @override
  Future<void> updateReadingStreak() async {}
}

class MockCurrentTenantNotifier extends CurrentTenantNotifier {
  @override
  Tenant? build() => null;
  @override
  Future<void> loadTenant() async {}
  @override
  Future<void> setTenant(Tenant? tenant) async {}
}

class MockNotificationService extends Mock implements NotificationService {}

class MockSermonService extends Mock implements SermonService {}

class MockNewsService extends Mock implements NewsService {}

class MockLiveStreamingService extends Mock implements LiveStreamingService {}

void main() {
  late MockNotificationService mockNotificationService;
  late MockSermonService mockSermonService;
  late MockNewsService mockNewsService;
  late MockLiveStreamingService mockLiveStreamingService;

  final mockVerse = DailyBibleVerse(
    id: '1',
    reference: 'John 3:16',
    text: 'For God so loved the world',
    createdAt: DateTime.now(),
  );

  setUp(() {
    HttpOverrides.global = MyHttpOverrides();
    mockNotificationService = MockNotificationService();
    mockSermonService = MockSermonService();
    mockNewsService = MockNewsService();
    mockLiveStreamingService = MockLiveStreamingService();

    when(() => mockNotificationService.init()).thenAnswer((_) async {});
    when(() => mockNotificationService.listenForAnnouncements(any())).thenReturn(null);
    when(() => mockSermonService.fetchLatestSermons()).thenAnswer((_) async => []);
    when(() => mockNewsService.getPublicNews()).thenAnswer((_) async => []);
  });

  testWidgets('Home screen renders without error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith(() => MockProfileNotifier()),
          currentTenantProvider.overrideWith(() => MockCurrentTenantNotifier()),
          unreadCountProvider.overrideWith((ref) => Stream.value(0)),
          notificationServiceProvider.overrideWithValue(mockNotificationService),
          sermonServiceProvider.overrideWithValue(mockSermonService),
          newsServiceProvider.overrideWithValue(mockNewsService),
          liveStreamingServiceProvider.overrideWithValue(mockLiveStreamingService),
          liveStatusProvider.overrideWith((ref, id) => Stream.value(LiveStreamStatus(isLive: false))),
          dailyBibleVerseProvider.overrideWith((ref) => Future.value(mockVerse)),
          // trendingSermonVerseProvider.overrideWith((ref) => Future.value(mockVerse)),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Home screen contains Scaffold', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith(() => MockProfileNotifier()),
          currentTenantProvider.overrideWith(() => MockCurrentTenantNotifier()),
          unreadCountProvider.overrideWith((ref) => Stream.value(0)),
          notificationServiceProvider.overrideWithValue(mockNotificationService),
          sermonServiceProvider.overrideWithValue(mockSermonService),
          newsServiceProvider.overrideWithValue(mockNewsService),
          liveStreamingServiceProvider.overrideWithValue(mockLiveStreamingService),
          liveStatusProvider.overrideWith((ref, id) => Stream.value(LiveStreamStatus(isLive: false))),
          dailyBibleVerseProvider.overrideWith((ref) => Future.value(mockVerse)),
          // trendingSermonVerseProvider.overrideWith((ref) => Future.value(mockVerse)),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
