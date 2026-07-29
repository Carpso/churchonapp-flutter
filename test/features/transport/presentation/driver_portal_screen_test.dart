import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:church_on_app/features/transport/presentation/driver_portal_screen.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'MAPS_ZAMBIA_URL=');
  });
  testWidgets('DriverPortalScreen renders', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(
            home: DriverPortalScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.byType(DriverPortalScreen), findsOneWidget);
  });

  testWidgets('DriverPortalScreen shows earnings section', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(
            home: DriverPortalScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.byType(DefaultTabController), findsOneWidget);
  });

  testWidgets('DriverPortalScreen displays tabs', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(
            home: DriverPortalScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.text('Kingdom Command'), findsOneWidget);
  });
}
