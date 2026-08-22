import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:church_on_app/features/admin/presentation/radio_station_management_screen.dart';
import 'package:church_on_app/features/modules/media/data/radio_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

// The screen gates its body on profileProvider (COA-team-only). Tests must
// override it with a superadmin user or the lock screen renders instead of
// the management UI (FAB, list).

class _FakeProfileNotifier extends ProfileNotifier {
  @override
  AsyncValue<UserProfile?> build() => AsyncValue.data(_superadmin);
}

UserProfile? _superadmin;

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'MAPS_ZAMBIA_URL=');
    _superadmin = UserProfile(
      id: 'admin-1',
      name: 'COA Admin',
      role: 'superadmin',
    );
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            radioStationsFutureProvider.overrideWith((ref) => Future.value(<RadioStation>[])),
            profileProvider.overrideWith(_FakeProfileNotifier.new),
          ],
          child: const MaterialApp(
            home: RadioStationManagementScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    });
  }

  testWidgets('RadioStationManagementScreen renders', (WidgetTester tester) async {
    await pumpScreen(tester);
    expect(find.byType(RadioStationManagementScreen), findsOneWidget);
  });

  testWidgets('RadioStationManagementScreen shows title', (WidgetTester tester) async {
    await pumpScreen(tester);
    expect(find.text('Radio Stations'), findsOneWidget);
  });

  testWidgets('RadioStationManagementScreen has add button', (WidgetTester tester) async {
    await pumpScreen(tester);
    expect(find.text('Add Station'), findsOneWidget);
  });
}
