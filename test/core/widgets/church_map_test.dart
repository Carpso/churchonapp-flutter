import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/core/widgets/church_map.dart';

void main() {
  testWidgets('ChurchMap renders without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChurchMap(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ChurchMap), findsOneWidget);
  });
}
