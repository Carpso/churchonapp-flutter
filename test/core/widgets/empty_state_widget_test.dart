import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/empty_state_widget.dart';

void main() {
  testWidgets('Empty state widget renders icon and title', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyStateWidget(
            icon: LucideIcons.inbox,
            title: 'No items',
          ),
        ),
      ),
    );
    expect(find.text('No items'), findsOneWidget);
  });

  testWidgets('Empty state widget shows subtitle when provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyStateWidget(
            icon: LucideIcons.inbox,
            title: 'No items',
            subtitle: 'Add some items to get started',
          ),
        ),
      ),
    );
    expect(find.text('No items'), findsOneWidget);
    expect(find.text('Add some items to get started'), findsOneWidget);
  });

  testWidgets('Empty state widget renders action button when provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyStateWidget(
            icon: LucideIcons.inbox,
            title: 'No items',
            actionLabel: 'Add Item',
            onAction: null,
          ),
        ),
      ),
    );
    expect(find.text('Add Item'), findsOneWidget);
  });

  testWidgets('Empty state action button triggers callback', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyStateWidget(
            icon: LucideIcons.inbox,
            title: 'No items',
            actionLabel: 'Add Item',
            onAction: () => tapped = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add Item'));
    expect(tapped, isTrue);
  });
}
