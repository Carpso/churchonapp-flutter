import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:church_on_app/features/transport/presentation/ride_request_screen.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class MockAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => AuthState(user: null);
}

class MockProfileNotifier extends ProfileNotifier {
  @override
  AsyncValue<UserProfile?> build() => const AsyncValue.data(null);
}

class MockTenantNotifier extends CurrentTenantNotifier {
  @override
  Tenant? build() => null;
}

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'MAPS_ZAMBIA_URL=');
  });

  testWidgets('RideRequestScreen renders with mode ride', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => MockAuthNotifier()),
            profileProvider.overrideWith(() => MockProfileNotifier()),
            currentTenantProvider.overrideWith(() => MockTenantNotifier()),
          ],
          child: const MaterialApp(
            home: RideRequestScreen(mode: 'ride'),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.byType(RideRequestScreen), findsOneWidget);
  });

  testWidgets('RideRequestScreen renders with mode delivery', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => MockAuthNotifier()),
            profileProvider.overrideWith(() => MockProfileNotifier()),
            currentTenantProvider.overrideWith(() => MockTenantNotifier()),
          ],
          child: const MaterialApp(
            home: RideRequestScreen(mode: 'delivery'),
          ),
        ),
      );
      await tester.pump();
    });
    expect(find.byType(RideRequestScreen), findsOneWidget);
  });
}
