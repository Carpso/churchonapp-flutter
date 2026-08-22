import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/admin/presentation/widgets/pastor_telemetry_widget.dart';

void main() {
  testWidgets('PastorTelemetryWidget renders financial breakdown and metrics', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PastorTelemetryWidget(
            totalTithes: 5000.0,
            totalOfferings: 3000.0,
            totalPledges: 2000.0,
            activeMembersCount: 450,
            averageAttendance: 380,
          ),
        ),
      ),
    );

    expect(find.text('Ministry Telemetry'), findsOneWidget);
    expect(find.text('Tithes'), findsOneWidget);
    expect(find.text('K 5K'), findsOneWidget);
    expect(find.text('Offerings'), findsOneWidget);
    expect(find.text('K 3K'), findsOneWidget);
    expect(find.text('Pledges'), findsOneWidget);
    expect(find.text('K 2K'), findsOneWidget);
    expect(find.text('450'), findsOneWidget);
    expect(find.text('380'), findsOneWidget);
  });
}
