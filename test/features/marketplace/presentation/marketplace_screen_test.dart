import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:church_on_app/features/marketplace/presentation/marketplace_screen.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'MAPS_ZAMBIA_URL=');
  });
  testWidgets('MarketplaceScreen renders', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(
            home: MarketplaceScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.byType(MarketplaceScreen), findsOneWidget);
  });

  testWidgets('MarketplaceScreen shows title', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(
            home: MarketplaceScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.text('Kingdom Marketplace'), findsOneWidget);
  });

  testWidgets('MarketplaceScreen has search categories', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(
            home: MarketplaceScreen(),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.text('ALL'), findsOneWidget);
    expect(find.text('BOOKSHOP'), findsOneWidget);
  });
}
