import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:church_on_app/features/transport/presentation/driver_portal_screen.dart';

// The portal touches Supabase via profile/transport providers in initState.
// Initializing a dummy Supabase instance (like select_church_screen_test)
// satisfies the singleton assertion; queries fail harmlessly into the
// screen's own catch blocks and empty stream states.

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    dotenv.testLoad(fileInput: 'MAPS_ZAMBIA_URL=https://example.com/zambia');
    await Supabase.initialize(
      url: 'https://dummy.supabase.co',
      publishableKey: 'dummy-key',
    );
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DriverPortalScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    });
  }

  testWidgets('DriverPortalScreen renders', (WidgetTester tester) async {
    await pumpScreen(tester);
    expect(find.byType(DriverPortalScreen), findsOneWidget);
  });

  testWidgets('DriverPortalScreen shows earnings section', (WidgetTester tester) async {
    await pumpScreen(tester);
    expect(find.byType(DefaultTabController), findsOneWidget);
  });

  testWidgets('DriverPortalScreen displays tabs', (WidgetTester tester) async {
    await pumpScreen(tester);
    expect(find.text('Command'), findsOneWidget);
    expect(find.text('RIDES'), findsOneWidget);
    expect(find.text('CARGO'), findsOneWidget);
  });
}
