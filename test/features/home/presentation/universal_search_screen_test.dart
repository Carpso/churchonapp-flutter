import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/home/presentation/universal_search_screen.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'MAPS_ZAMBIA_URL=');
  });

  // UniversalSearchScreen searches the Bible and the church social graph on
  // open, both via `Supabase.instance`. Uninitialised, those reads assert
  // `_instance._isInitialized` and the widget tree throws before the screen
  // ever paints. Dummy values let it render; every query fails harmlessly and
  // the screen already handles a failed search.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://dummy.supabase.co',
      publishableKey: 'dummy-key',
    );
  });
  testWidgets('UniversalSearchScreen renders', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(
            home: UniversalSearchScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.byType(UniversalSearchScreen), findsOneWidget);
  });

  testWidgets('UniversalSearchScreen has search input', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(
            home: UniversalSearchScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('UniversalSearchScreen shows quick suggestions', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(
            home: UniversalSearchScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.text('QUICK SUGGESTIONS'), findsOneWidget);
  });

  testWidgets('UniversalSearchScreen shows no results empty state', (WidgetTester tester) async {
    // No runAsync: the debounce Timer runs on fake clock via pump(duration).
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: UniversalSearchScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'nothingmatches');
    // Advance past the 350ms debounce so _search fires, then let its
    // Supabase-less failure land in the catch → empty state.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('No matches found'), findsOneWidget);
  });
}
