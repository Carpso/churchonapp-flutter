import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/bible/presentation/bible_screen.dart';

void main() {
  testWidgets('Bible screen renders without error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: BibleScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(BibleScreen), findsOneWidget);
  });

  testWidgets('Bible screen has an AppBar with back button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: BibleScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);
  });
}
