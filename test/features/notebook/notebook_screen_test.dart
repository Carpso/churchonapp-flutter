import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/notebook/presentation/notebook_screen.dart';

void main() {
  testWidgets('Notebook screen renders without error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: NotebookScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(NotebookScreen), findsOneWidget);
  });

  testWidgets('Notebook screen has a Scaffold', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: NotebookScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
