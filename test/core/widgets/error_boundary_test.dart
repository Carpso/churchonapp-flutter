import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/core/widgets/error_boundary.dart';

void main() {
  testWidgets('CustomErrorBoundary shows error UI', (WidgetTester tester) async {
    final errorDetails = FlutterErrorDetails(
      exception: Exception('Test error message'),
      stack: StackTrace.current,
    );

    await tester.pumpWidget(
      CustomErrorBoundary(errorDetails: errorDetails),
    );
    await tester.pump();

    expect(find.text('App Recovered'), findsOneWidget);
    expect(find.text('An unexpected error occurred.'), findsOneWidget);
    expect(find.textContaining('Exception'), findsWidgets);
    expect(find.text('RETURN TO HOME'), findsOneWidget);
  });

  testWidgets('CustomErrorBoundary shows long error text', (WidgetTester tester) async {
    final errorDetails = FlutterErrorDetails(
      exception: Exception('A very long error message that should be truncated in the UI'),
      stack: StackTrace.current,
    );

    await tester.pumpWidget(
      CustomErrorBoundary(errorDetails: errorDetails),
    );
    await tester.pump();

    expect(find.text('RETURN TO HOME'), findsOneWidget);
    expect(find.text('An unexpected error occurred.'), findsOneWidget);
  });
}
