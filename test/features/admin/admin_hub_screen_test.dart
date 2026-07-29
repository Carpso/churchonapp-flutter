import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/admin/presentation/admin_hub_screen.dart';

void main() {
  testWidgets('Admin hub screen renders without error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: AdminHubScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(AdminHubScreen), findsOneWidget);
  });
}
