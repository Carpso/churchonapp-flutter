import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/widgets/kingdom_logo.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class MockTenantNotifier extends CurrentTenantNotifier {
  final Tenant? _tenant;
  MockTenantNotifier(this._tenant);

  @override
  Tenant? build() => _tenant;
}

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
  Future<HttpClientRequest> delete(String host, int port, String path) => throw UnimplementedError();
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => throw UnimplementedError();
  @override
  set findProxy(String Function(Uri url)? f) {}
  @override
  Future<HttpClientRequest> get(String host, int port, String path) => throw UnimplementedError();
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> head(String host, int port, String path) => throw UnimplementedError();
  @override
  Future<HttpClientRequest> headUrl(Uri url) => throw UnimplementedError();
  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) => throw UnimplementedError();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => throw UnimplementedError();
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) => throw UnimplementedError();
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => throw UnimplementedError();
  @override
  Future<HttpClientRequest> post(String host, int port, String path) => throw UnimplementedError();
  @override
  Future<HttpClientRequest> postUrl(Uri url) => throw UnimplementedError();
  @override
  Future<HttpClientRequest> put(String host, int port, String path) => throw UnimplementedError();
  @override
  Future<HttpClientRequest> putUrl(Uri url) => throw UnimplementedError();
  @override
  set badCertificateCallback(bool Function(X509Certificate cert, String host, int port)? callback) {}
  @override
  set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri url, String? proxyHost, int? proxyPort)? f) {}
  @override
  set keyLog(void Function(String line)? callback) {}
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  bool bufferOutput = false;
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
  Future addStream(Stream<List<int>> stream) => Future.value();
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
  @override
  Future<HttpClientResponse> get done => throw UnimplementedError();
  @override
  void write(Object? object) {}
  @override
  void writeAll(Iterable objects, [String separator = ""]) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? object = ""]) {}
  @override
  HttpHeaders get headers => throw UnimplementedError();
  @override
  List<Cookie> get cookies => throw UnimplementedError();
  @override
  String get method => throw UnimplementedError();
  @override
  Uri get uri => throw UnimplementedError();
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  Future flush() async {}
}

class _MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
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
  @override
  Future<Socket> detachSocket() => throw UnimplementedError();
  @override
  List<Cookie> get cookies => [];
  @override
  HttpHeaders get headers => throw UnimplementedError();
  @override
  bool get isRedirect => false;
  @override
  String get reasonPhrase => "OK";
  @override
  List<RedirectInfo> get redirects => [];
  @override
  Future<HttpClientResponse> redirect([String? method, Uri? url, bool? followRedirects]) => throw UnimplementedError();
  @override
  bool get persistentConnection => true;
  @override
  X509Certificate? get certificate => null;
  @override
  HttpConnectionInfo? get connectionInfo => null;
}

final List<int> _transparentImage = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

void main() {
  setUp(() {
    HttpOverrides.global = MyHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  testWidgets('KingdomLogo renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentTenantProvider.overrideWith(() => MockTenantNotifier(null)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: KingdomLogo()),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(KingdomLogo), findsOneWidget);
  });

  testWidgets('KingdomLogo custom size works', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentTenantProvider.overrideWith(() => MockTenantNotifier(null)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: KingdomLogo(size: 80)),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(KingdomLogo), findsOneWidget);
  });
}
