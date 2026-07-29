import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/admin/presentation/widgets/admin_navigation_registry.dart';

void main() {
  testWidgets('AdminNavigationRegistry filters tiles based on role permissions', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ListView(
                children: AdminNavigationRegistry.buildAccessibleTiles(
                  context,
                  isSuperadmin: false,
                  isPastor: true,
                  isBishop: false,
                  isTreasurer: false,
                ),
              );
            },
          ),
        ),
      ),
    );

    // Pastors see Church Management, Giving & Financial Reports, Live Stream Studio, Event Scheduler, Radio Station Mgmt
    expect(find.text('Church Management'), findsOneWidget);
    expect(find.text('Giving & Financial Reports'), findsOneWidget);
    expect(find.text('Live Stream Studio'), findsOneWidget);
    
    // Superadmin tiles should be hidden from pastor
    expect(find.text('Partner Tenants'), findsNothing);
    expect(find.text('Ad Promotions & Coins'), findsNothing);
  });
}
