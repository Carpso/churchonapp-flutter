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
    expect(find.text('Alerts'), findsOneWidget);
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
    expect(find.text('No notifications yet'), findsOneWidget);
  });
}
