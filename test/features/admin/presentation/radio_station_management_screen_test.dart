import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:church_on_app/features/admin/presentation/radio_station_management_screen.dart';
import 'package:church_on_app/features/modules/media/data/radio_service.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'MAPS_ZAMBIA_URL=');
  });

  testWidgets('RadioStationManagementScreen renders', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            radioStationsFutureProvider.overrideWith((ref) => Future.value(<RadioStation>[])),
          ],
          child: const MaterialApp(
            home: RadioStationManagementScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.byType(RadioStationManagementScreen), findsOneWidget);
  });

  testWidgets('RadioStationManagementScreen shows title', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            radioStationsFutureProvider.overrideWith((ref) => Future.value(<RadioStation>[])),
          ],
          child: const MaterialApp(
            home: RadioStationManagementScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.text('Radio Stations'), findsOneWidget);
  });

  testWidgets('RadioStationManagementScreen has add button', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            radioStationsFutureProvider.overrideWith((ref) => Future.value(<RadioStation>[])),
          ],
          child: const MaterialApp(
            home: RadioStationManagementScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.text('Add Station'), findsOneWidget);
  });
}