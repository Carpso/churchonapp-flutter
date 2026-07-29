import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/connect/presentation/connect_screen.dart';

void main() {
  testWidgets('Connect screen renders without error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: ConnectScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(ConnectScreen), findsOneWidget);
  });

  testWidgets('Connect screen has floating action button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: ConnectScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
