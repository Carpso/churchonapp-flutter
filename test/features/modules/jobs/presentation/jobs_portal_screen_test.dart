import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:lucide_icons/lucide_icons.dart';
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

  testWidgets('JobsPortalScreen exposes search action (snackbar stub)', (WidgetTester tester) async {
    // The portal replaced its inline search TextField with an app-bar search
    // action that currently surfaces a placeholder snackbar.
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
    await tester.tap(find.byIcon(LucideIcons.search));    await tester.pump();
    expect(find.text('Search jobs feature'), findsOneWidget);
  });
}