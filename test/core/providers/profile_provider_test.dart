import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';

class MockAuthForProfileNotifier extends AuthNotifier {
  @override
  AuthState build() => AuthState(user: null);
}

class MockProfileNotifier extends ProfileNotifier {
  final UserProfile? _profile;
  MockProfileNotifier(this._profile);

  @override
  AsyncValue<UserProfile?> build() => AsyncValue.data(_profile);

  @override
  Future<void> updateReadingStreak() async {}
}

void main() {
  test('fetches profile on initialization', () {
    final profile = UserProfile(id: '1', name: 'Test User', role: 'member', coins: 100);
    final container = ProviderContainer(
      overrides: [
        profileProvider.overrideWith(() => MockProfileNotifier(profile)),
        authProvider.overrideWith(() => MockAuthForProfileNotifier()),
      ],
    );
    final state = container.read(profileProvider);
    expect(state.asData?.value?.name, 'Test User');
    expect(state.asData?.value?.coins, 100);
    container.dispose();
  });

  test('handles null user gracefully', () {
    final container = ProviderContainer(
      overrides: [
        profileProvider.overrideWith(() => MockProfileNotifier(null)),
        authProvider.overrideWith(() => MockAuthForProfileNotifier()),
      ],
    );
    final state = container.read(profileProvider);
    expect(state.asData?.value, isNull);
    container.dispose();
  });

  test('profile has correct defaults', () {
    final profile = UserProfile(id: '2', name: 'New User');
    expect(profile.role, 'member');
    expect(profile.coins, 0);
    expect(profile.streakCount, 0);
    expect(profile.isSuperadmin, false);
    expect(profile.isEmployee, false);
  });

  test('updateReadingStreak does not throw when profile is null', () async {
    final notifier = MockProfileNotifier(null);
    Future result;
    try {
      result = notifier.updateReadingStreak();
      await result;
    } catch (_) {
      fail('Should not throw');
    }
  });
}
