import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:church_on_app/features/home/presentation/universal_search_screen.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'MAPS_ZAMBIA_URL=');
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
