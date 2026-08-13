import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:church_on_app/features/bible/presentation/deep_study_suite_screen.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class MockProfileNotifier extends ProfileNotifier {
  @override
  AsyncValue<UserProfile?> build() => const AsyncValue.data(null);

  @override
  Future<void> updateReadingStreak() async {}
}

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'MAPS_ZAMBIA_URL=');
  });

  testWidgets('DeepStudySuiteScreen renders', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => MockProfileNotifier()),
          ],
          child: const MaterialApp(
            home: DeepStudySuiteScreen(),
          ),
        ),
      );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DeepStudySuiteScreen), findsOneWidget);
  });

  testWidgets('DeepStudySuiteScreen shows title', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => MockProfileNotifier()),
          ],
          child: const MaterialApp(
            home: DeepStudySuiteScreen(),
          ),
        ),
      );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('DEEP STUDY'), findsOneWidget);
  });

  testWidgets('DeepStudySuiteScreen has tool matrix', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => MockProfileNotifier()),
          ],
          child: const MaterialApp(
            home: DeepStudySuiteScreen(),
          ),
        ),
      );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Podcast'), findsOneWidget);
    expect(find.text('Atlas'), findsOneWidget);
    expect(find.text('Study Plans'), findsOneWidget);
  });
}
