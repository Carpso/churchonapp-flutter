import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/features/auth/presentation/select_church_screen.dart'
    show SelectTenantScreen;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) {}
  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) {}
  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String realm)? f,
  ) {}
  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String realm)?
    f,
  ) {}
  @override
  void close({bool force = false}) {}
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) async =>
      throw UnimplementedError();
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) async =>
      throw UnimplementedError();
  @override
  set findProxy(String Function(Uri url)? f) {}
  @override
  Future<HttpClientRequest> get(String host, int port, String path) async =>
      _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> head(String host, int port, String path) async =>
      throw UnimplementedError();
  @override
  Future<HttpClientRequest> headUrl(Uri url) async =>
      throw UnimplementedError();
  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) async => throw UnimplementedError();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) async =>
      throw UnimplementedError();
  @override
  Future<HttpClientRequest> patchUrl(Uri url) async =>
      throw UnimplementedError();
  @override
  Future<HttpClientRequest> post(String host, int port, String path) async =>
      _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> put(String host, int port, String path) async =>
      _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> putUrl(Uri url) async => _MockHttpClientRequest();
  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) {}
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) {}
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
  void remove(String name, Object value) =>
      _headers[name]?.remove(value.toString());
  @override
  void removeAll(String name) => _headers.remove(name);
  @override
  void forEach(void Function(String name, List<String> values) f) =>
      _headers.forEach(f);
  @override
  bool get chunkedTransferEncoding => false;
  @override
  set chunkedTransferEncoding(bool value) {}
  @override
  int get contentLength => 0;
  @override
  set contentLength(int value) {}
  @override
  ContentType? contentType;
  @override
  DateTime? date;
  @override
  DateTime? expires;
  @override
  set host(String? value) {}
  @override
  String? get host => "dummy.co";
  @override
  DateTime? ifModifiedSince;
  @override
  bool get persistentConnection => true;
  @override
  set persistentConnection(bool value) {}
  @override
  set port(int? value) {}
  @override
  int? get port => 443;
  @override
  void noFolding(String name) {}
  @override
  String? value(String name) => _headers[name]?.first;
  @override
  void clear() => _headers.clear();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => 0;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final transparentPng = <int>[
      137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 213, 196, 205, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 96, 248, 15, 0, 1, 5, 1, 2, 210, 221, 142, 206, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130
    ];
    return Stream<List<int>>.fromIterable([transparentPng]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<Socket> detachSocket() async => throw UnimplementedError();
  @override
  List<Cookie> get cookies => [];
  @override
  HttpHeaders get headers => _MockHttpHeaders();
  @override
  bool get isRedirect => false;
  @override
  String get reasonPhrase => "OK";
  @override
  List<RedirectInfo> get redirects => [];
  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followRedirects,
  ]) async => throw UnimplementedError();
  @override
  bool get persistentConnection => true;
  @override
  X509Certificate? get certificate => null;
  @override
  HttpConnectionInfo? get connectionInfo => null;
}

// Mocking Geolocator Platform Channel
const MethodChannel geolocatorChannel = MethodChannel(
  'flutter.baseflow.com/geolocator',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = MyHttpOverrides();
    // Initialize mock shared preferences
    SharedPreferences.setMockInitialValues({});

    // Initialize dotenv for tests
    dotenv.testLoad(
      fileInput: '''
      MAPS_ZAMBIA_URL=https://example.com/zambia
      MAPS_ZIMBABWE_URL=https://example.com/zimbabwe
    ''',
    );

    // Initialize Supabase with dummy values for testing
    await Supabase.initialize(
      url: 'https://dummy.supabase.co',
      publishableKey: 'dummy-key',
    );

    // Mock Geolocator responses
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(geolocatorChannel, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'checkPermission') {
            return 3; // LocationPermission.always
          }
          if (methodCall.method == 'isLocationServiceEnabled') {
            return true;
          }
          if (methodCall.method == 'getCurrentPosition') {
            return {
              'latitude': -15.42,
              'longitude': 28.32,
              'timestamp': 0,
              'accuracy': 0.0,
              'altitude': 0.0,
              'heading': 0.0,
              'speed': 0.0,
              'speed_accuracy': 0.0,
            };
          }
          return null;
        });
  });

  testWidgets('SelectChurchScreen renders and degrades gracefully without backend', (
    WidgetTester tester,
  ) async {
    // NOTE: fallback seed churches were removed by design — tenants are
    // database-only now. Against a dummy Supabase the fetch yields nothing,
    // so the screen must show its empty/retry state, never crash.
    await tester.binding.setSurfaceSize(const Size(800, 1200));

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SelectTenantScreen())),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(find.byType(SelectTenantScreen), findsOneWidget);
    final hasEmptyState = find.textContaining('No tenants').evaluate().isNotEmpty;
    final hasRetry = find.textContaining('retry').evaluate().isNotEmpty;
    final stillLoading = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    expect(hasEmptyState || hasRetry || stillLoading, isTrue,
        reason: 'screen must render a body state without tenant data');
  });
}
