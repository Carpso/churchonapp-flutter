import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:church_on_app/main.dart' as app;

/// Real-device smoke test (Firebase Test Lab).
/// Verifies the app boots and renders its first frame without crashing.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches and renders first frame', (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));

    expect(tester.takeException(), isNull,
        reason: 'App crashed during startup');
    expect(find.byType(app.ChurchOnApp), findsOneWidget);
  });
}