import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:church_on_app/core/providers/offline_providers.dart';

// offlineServiceProvider2 aliases offlineServiceProvider, whose OfflineService
// touches Supabase.instance. Initialize a dummy instance so the provider
// resolves (the same pattern as select_church_screen_test).

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://dummy.supabase.co',
      publishableKey: 'dummy-key',
    );
  });

  testWidgets('connectivityStatusProvider returns a stream', (WidgetTester tester) async {
    final container = ProviderContainer();
    final connectivity = container.read(connectivityStatusProvider);
    expect(connectivity, isA<AsyncValue<bool>>());
    container.dispose();
  });

  test('offlineQueueCountProvider is a StreamProvider<int>', () {
    final provider = offlineQueueCountProvider;
    expect(provider, isA<StreamProvider<int>>());
  });

  test('offlineServiceProvider2 creates an OfflineService', () {
    final container = ProviderContainer();
    expect(() => container.read(offlineServiceProvider2), returnsNormally);
    container.dispose();
  });
}
