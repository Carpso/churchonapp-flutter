import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:audio_service/audio_service.dart';
import 'package:rxdart/rxdart.dart';
import 'package:church_on_app/features/modules/media/presentation/radio_screen.dart';
import 'package:church_on_app/features/modules/media/data/radio_service.dart';
import 'package:church_on_app/core/providers/audio_provider.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class MockRadioService extends Mock implements RadioService {}
class MockAudioHandler extends Mock implements AudioHandler {}

class MockProfileNotifier extends ProfileNotifier {
  @override
  AsyncValue<UserProfile?> build() => const AsyncValue.data(null);
  @override
  Future<void> updateReadingStreak() async {}
}

class MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return MockHttpClient();
  }
}

class MockHttpClient extends Mock implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) => _mockRequest();

  static Future<HttpClientRequest> _mockRequest() async {
    final req = MockHttpClientRequest();
    final resp = MockHttpClientResponse();
    final headers = MockHttpHeaders();
    when(() => req.headers).thenReturn(headers);
    when(() => req.close()).thenAnswer((_) async => resp);
    when(() => resp.statusCode).thenReturn(200);
    when(() => resp.compressionState).thenReturn(HttpClientResponseCompressionState.notCompressed);
    when(() => resp.contentLength).thenReturn(_transparentImage.length);
    when(() => resp.listen(any(),
        cancelOnError: any(named: 'cancelOnError'),
        onDone: any(named: 'onDone'),
        onError: any(named: 'onError'))).thenAnswer((invocation) {
      final onData = invocation.positionalArguments[0] as void Function(List<int>);
      final onDone = invocation.namedArguments[#onDone] as void Function()?;
      onData(_transparentImage);
      if (onDone != null) onDone();
      return MockStreamSubscription();
    });
    return req;
  }
}

class MockHttpClientRequest extends Mock implements HttpClientRequest {}
class MockHttpClientResponse extends Mock implements HttpClientResponse {}
class MockHttpHeaders extends Mock implements HttpHeaders {}
class MockStreamSubscription extends Mock implements StreamSubscription<List<int>> {}

final List<int> _transparentImage = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82
];

void main() {
  late MockRadioService mockRadioService;
  late MockAudioHandler mockAudioHandler;
  late BehaviorSubject<PlaybackState> mockPlaybackSubject;

  setUpAll(() {
    HttpOverrides.global = MockHttpOverrides();
  });

  setUp(() {
    mockRadioService = MockRadioService();
    mockAudioHandler = MockAudioHandler();

    final mockPlaybackState = PlaybackState(playing: false);
    mockPlaybackSubject = BehaviorSubject<PlaybackState>.seeded(mockPlaybackState);
    when(() => mockAudioHandler.playbackState).thenAnswer((_) => mockPlaybackSubject);
  });

  tearDown(() {
    mockPlaybackSubject.close();
  });

  testWidgets('Kingdom Radio screen renders without error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          radioServiceProvider.overrideWithValue(mockRadioService),
          radioStationsFutureProvider.overrideWithValue(AsyncValue.data(<RadioStation>[
            RadioStation(
              id: 'rs1',
              name: 'Radio Christian Voice',
              streamUrl: 'http://test.stream',
              location: 'Lusaka',
              isPrivate: false,
            ),
          ])),
          radioMetadataProvider('Radio Christian Voice').overrideWith((ref) => Stream.value("LIVE: Streaming...")),
          audioHandlerProvider.overrideWithValue(mockAudioHandler),
          profileProvider.overrideWith(() => MockProfileNotifier()),
        ],
        child: const MaterialApp(home: RadioScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(RadioScreen), findsOneWidget);
  });

  testWidgets('Kingdom Radio screen has a Scaffold', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          radioServiceProvider.overrideWithValue(mockRadioService),
          radioStationsFutureProvider.overrideWithValue(AsyncValue.data(<RadioStation>[
            RadioStation(
              id: 'rs1',
              name: 'Radio Christian Voice',
              streamUrl: 'http://test.stream',
              location: 'Lusaka',
              isPrivate: false,
            ),
          ])),
          radioMetadataProvider('Radio Christian Voice').overrideWith((ref) => Stream.value("LIVE: Streaming...")),
          audioHandlerProvider.overrideWithValue(mockAudioHandler),
          profileProvider.overrideWith(() => MockProfileNotifier()),
        ],
        child: const MaterialApp(home: RadioScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
