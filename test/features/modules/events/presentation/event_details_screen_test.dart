import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/modules/events/presentation/event_details_screen.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:google_fonts/google_fonts.dart';

// --- Direct Interface Mocking for HttpClient ---
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient();
  }
}

class _MockHttpClient implements HttpClient {
  @override
  bool autoUncompress = false;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 1);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials credentials) {}
  @override
  void addProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) {}
  @override
  set authenticate(Future<bool> Function(Uri url, String scheme, String realm)? f) {}
  @override
  set authenticateProxy(Future<bool> Function(String host, int port, String scheme, String realm)? f) {}
  @override
  void close({bool force = false}) {}
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) async => throw UnimplementedError();
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) async => throw UnimplementedError();
  @override
  set findProxy(String Function(Uri url)? f) {}
  @override
  Future<HttpClientRequest> get(String host, int port, String path) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> head(String host, int port, String path) async => throw UnimplementedError();
  @override
  Future<HttpClientRequest> headUrl(Uri url) async => throw UnimplementedError();
  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) async => throw UnimplementedError();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) async => throw UnimplementedError();
  @override
  Future<HttpClientRequest> patchUrl(Uri url) async => throw UnimplementedError();
  @override
  Future<HttpClientRequest> post(String host, int port, String path) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> put(String host, int port, String path) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> putUrl(Uri url) async => _MockHttpClientRequest();
  @override
  set badCertificateCallback(bool Function(X509Certificate cert, String host, int port)? callback) {}
  @override
  set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri url, String? proxyHost, int? proxyPort)? f) {}
  @override
  set keyLog(void Function(String line)? callback) {}
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  bool bufferOutput = true;
  @override
  int contentLength = 0;
  @override
  Encoding encoding = utf8;
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;

  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream<List<int>> stream) async {}
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
  @override
  Future<HttpClientResponse> get done async => _MockHttpClientResponse();
  @override
  void write(Object? object) {}
  @override
  void writeAll(Iterable objects, [String separator = ""]) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? object = ""]) {}
  @override
  HttpHeaders get headers => _MockHttpHeaders();
  @override
  List<Cookie> get cookies => [];
  @override
  String get method => "GET";
  @override
  Uri get uri => Uri.parse("https://dummy.co");
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  Future flush() async {}
}

class _MockHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _headers = {};
  @override
  List<String>? operator [](String name) => _headers[name];
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers.putIfAbsent(name, () => []).add(value.toString());
  }
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name] = [value.toString()];
  }
  @override
  void remove(String name, Object value) => _headers[name]?.remove(value.toString());
  @override
  void removeAll(String name) => _headers.remove(name);
  @override
  void forEach(void Function(String name, List<String> values) f) => _headers.forEach(f);
  @override
  String? value(String name) => _headers[name]?.first;

  @override
  DateTime? date;
  @override
  DateTime? expires;
  @override
  DateTime? ifModifiedSince;
  @override
  String? host;
  @override
  int? port;
  @override
  bool chunkedTransferEncoding = false;
  @override
  int contentLength = 0;
  @override
  ContentType? contentType;
  @override
  bool persistentConnection = true;

  @override
  void noSuchMethod(Invocation invocation) {}
}

class _MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
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
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_transparentImage]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => [];
  @override
  Future<HttpClientResponse> redirect([String? method, Uri? url, bool? followRedirects]) => throw UnimplementedError();
  @override
  HttpHeaders get headers => _MockHttpHeaders();
  @override
  List<Cookie> get cookies => [];
  @override
  String get reasonPhrase => "OK";
  @override
  bool get persistentConnection => true;
  @override
  Future<Socket> detachSocket() => throw UnimplementedError();
  @override
  X509Certificate? get certificate => null;
  @override
  HttpConnectionInfo? get connectionInfo => null;
}

class MockTenantNotifier extends CurrentTenantNotifier {
  @override
  Tenant? build() => null;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() async {
    HttpOverrides.global = MyHttpOverrides();
    dotenv.testLoad(fileInput: 'MAPS_ZAMBIA_URL=');
    
    // Mock SharedPreferences channel before Supabase initializes
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAll') {
          return <String, dynamic>{};
        }
        return null;
      },
    );

    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mockAnonKey',
      );
    } catch (_) {
      // Already initialized
    }
  });

  final testEvent = {
    'id': '1',
    'title': 'Sunday Service',
    'description': 'Weekly worship service',
    'date': '2026-07-12',
    'time': '09:00',
    'location': 'Main Sanctuary',
    'type': 'worship',
    'price': 0,
    'cover': '',
    'speakers': 'Pastor John',
    'created_by': 'user1',
  };

  testWidgets('EventDetailsScreen renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentTenantProvider.overrideWith(() => MockTenantNotifier()),
        ],
        child: MaterialApp(
          home: EventDetailsScreen(event: testEvent),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(EventDetailsScreen), findsOneWidget);
  });

  testWidgets('EventDetailsScreen displays event info', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentTenantProvider.overrideWith(() => MockTenantNotifier()),
        ],
        child: MaterialApp(
          home: EventDetailsScreen(event: testEvent),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Sunday Service'), findsOneWidget);
    expect(find.text('Weekly worship service'), findsOneWidget);
  });

  testWidgets('EventDetailsScreen has RSVP button for free event', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentTenantProvider.overrideWith(() => MockTenantNotifier()),
        ],
        child: MaterialApp(
          home: EventDetailsScreen(event: testEvent),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('RSVP NOW'), findsOneWidget);
  });

  testWidgets('EventDetailsScreen shows price for paid event', (WidgetTester tester) async {
    final paidEvent = Map<String, dynamic>.from(testEvent)..['price'] = 50;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentTenantProvider.overrideWith(() => MockTenantNotifier()),
        ],
        child: MaterialApp(
          home: EventDetailsScreen(event: paidEvent),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('SECURE TICKET'), findsOneWidget);
  });
}
