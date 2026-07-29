import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:church_on_app/features/bible/presentation/study_plans_screen.dart';
import 'package:church_on_app/features/bible/data/reading_plan_service.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'MAPS_ZAMBIA_URL=');
  });

  testWidgets('StudyPlansScreen renders', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readingPlansProvider.overrideWith((ref) => []),
          ],
          child: const MaterialApp(
            home: StudyPlansScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.byType(StudyPlansScreen), findsOneWidget);
  });

  testWidgets('StudyPlansScreen shows title', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readingPlansProvider.overrideWith((ref) => []),
          ],
          child: const MaterialApp(
            home: StudyPlansScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.text('Study Plans'), findsOneWidget);
  });

  testWidgets('StudyPlansScreen shows empty state', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readingPlansProvider.overrideWith((ref) => []),
          ],
          child: const MaterialApp(
            home: StudyPlansScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.text('No Reading Plans'), findsOneWidget);
  });
}
