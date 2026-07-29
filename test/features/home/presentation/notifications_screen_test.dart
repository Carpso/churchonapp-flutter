import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:church_on_app/features/home/presentation/notifications_screen.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'MAPS_ZAMBIA_URL=');
  });
  testWidgets('NotificationsScreen renders', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsStreamProvider.overrideWith((ref) => Stream.value(<Map<String, dynamic>>[])),
          ],
          child: const MaterialApp(
            home: NotificationsScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  testWidgets('NotificationsScreen shows title', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsStreamProvider.overrideWith((ref) => Stream.value(<Map<String, dynamic>>[])),
          ],
          child: const MaterialApp(
            home: NotificationsScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.text('Kingdom Alerts'), findsOneWidget);
  });

  testWidgets('NotificationsScreen has category tabs', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsStreamProvider.overrideWith((ref) => Stream.value(<Map<String, dynamic>>[])),
          ],
          child: const MaterialApp(
            home: NotificationsScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Prayer'), findsOneWidget);
    expect(find.text('Sermon'), findsOneWidget);
  });

  testWidgets('NotificationsScreen shows empty state', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsStreamProvider.overrideWith((ref) => Stream.value(<Map<String, dynamic>>[])),
          ],
          child: const MaterialApp(
            home: NotificationsScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.text('You\'re all caught up'), findsOneWidget);
  });
}
