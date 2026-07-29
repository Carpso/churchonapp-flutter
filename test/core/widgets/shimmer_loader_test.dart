import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';

void main() {
  testWidgets('ShimmerLoader.rectangular renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ShimmerLoader.rectangular(height: 100)),
      ),
    );
    await tester.pump();
    expect(find.byType(ShimmerLoader), findsOneWidget);
  });

  testWidgets('ShimmerLoader.circular renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ShimmerLoader.circular(width: 50, height: 50)),
      ),
    );
    await tester.pump();
    expect(find.byType(ShimmerLoader), findsOneWidget);
  });

  testWidgets('ListSkeleton renders correct count', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ListSkeleton(count: 3)),
      ),
    );
    await tester.pump();
    expect(find.byType(ListSkeleton), findsOneWidget);
  });
}
