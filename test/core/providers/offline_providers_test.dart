import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/providers/offline_providers.dart';

void main() {
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
    // Just verify the provider resolves without errors
    expect(() => container.read(offlineServiceProvider2), returnsNormally);
    container.dispose();
  });
}
