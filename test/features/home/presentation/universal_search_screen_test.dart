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
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(
            home: UniversalSearchScreen(),
          ),
        ),
      );
      await tester.pump();
      final textField = find.byType(TextField);
      await tester.enterText(textField, 'nothingmatches');
      await tester.pump();
    });
    expect(find.text('No Matches Found'), findsOneWidget);
  });
}
