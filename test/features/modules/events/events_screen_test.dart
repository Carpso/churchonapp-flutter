import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/modules/events/presentation/events_screen.dart';

void main() {
  testWidgets('Events screen renders without error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: EventsScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(EventsScreen), findsOneWidget);
  });

  testWidgets('Events screen has AppBar with tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: EventsScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
  });
}
