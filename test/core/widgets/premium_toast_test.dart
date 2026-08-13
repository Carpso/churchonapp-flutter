import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';

void main() {
  testWidgets('PremiumToast.showSuccess displays without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => PremiumToast.showSuccess(context, 'Success message'),
            child: const Text('Show'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.text('Success message'), findsOneWidget);
    // Let the auto-dismiss timer fire so the test ends with no pending timers.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('PremiumToast.showError displays without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => PremiumToast.showError(context, 'Error message'),
            child: const Text('Show'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.text('Error message'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('PremiumToast.showInfo displays without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => PremiumToast.showInfo(context, 'Info message'),
            child: const Text('Show'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.text('Info message'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
