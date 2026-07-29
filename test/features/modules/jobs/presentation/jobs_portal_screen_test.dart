import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:church_on_app/features/modules/jobs/presentation/jobs_portal_screen.dart';
import 'package:church_on_app/features/modules/jobs/data/jobs_service.dart';
import 'package:church_on_app/features/modules/jobs/data/job_model.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'MAPS_ZAMBIA_URL=');
  });

  testWidgets('JobsPortalScreen renders', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jobsPortalProvider.overrideWith((ref) => Stream.value(<Job>[])),
          ],
          child: const MaterialApp(
            home: JobsPortalScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.byType(JobsPortalScreen), findsOneWidget);
  });

  testWidgets('JobsPortalScreen shows title', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jobsPortalProvider.overrideWith((ref) => Stream.value(<Job>[])),
          ],
          child: const MaterialApp(
            home: JobsPortalScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.text('Jobs & Volunteering'), findsOneWidget);
  });

  testWidgets('JobsPortalScreen has search field', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jobsPortalProvider.overrideWith((ref) => Stream.value(<Job>[])),
          ],
          child: const MaterialApp(
            home: JobsPortalScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.byType(TextField), findsWidgets);
  });
}