import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/connect/presentation/prayer_wall_screen.dart';

void main() {
  testWidgets('Prayer wall screen renders without error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: PrayerWallScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(PrayerWallScreen), findsOneWidget);
  });

  testWidgets('Prayer wall screen has a Scaffold', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: PrayerWallScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
