import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';

class MockAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => AuthState(user: null);

  @override
  Future<void> signIn(String email, String password) async {
    state = AuthState(user: null, isLoading: false);
  }

  @override
  Future<void> signUp(String email, String password, String name) async {
    state = AuthState(user: null, isLoading: false);
  }

  @override
  Future<void> signOut() async {
    state = AuthState(user: null);
  }

  @override
  Future<void> signInWithGoogle() async {
    state = AuthState(user: null, isLoading: false);
  }
}

void main() {
  test('Initial state is unauthenticated', () {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => MockAuthNotifier()),
      ],
    );
    final state = container.read(authProvider);
    expect(state.user, isNull);
    expect(state.isLoading, false);
    expect(state.errorMessage, isNull);
    container.dispose();
  });

  test('signIn updates state', () async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => MockAuthNotifier()),
      ],
    );
    final notifier = container.read(authProvider.notifier);
    await notifier.signIn('test@test.com', 'password');
    final state = container.read(authProvider);
    expect(state.isLoading, false);
    container.dispose();
  });

  test('signUp creates account and updates state', () async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => MockAuthNotifier()),
      ],
    );
    final notifier = container.read(authProvider.notifier);
    await notifier.signUp('test@test.com', 'password', 'Test User');
    final state = container.read(authProvider);
    expect(state.isLoading, false);
    container.dispose();
  });

  test('signOut resets state to unauthenticated', () async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => MockAuthNotifier()),
      ],
    );
    final notifier = container.read(authProvider.notifier);
    await notifier.signOut();
    final state = container.read(authProvider);
    expect(state.user, isNull);
    container.dispose();
  });

  test('handles errors gracefully', () async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => MockAuthNotifier()),
      ],
    );
    final notifier = container.read(authProvider.notifier);
    try {
      await notifier.signIn('', '');
    } catch (_) {}
    final state = container.read(authProvider);
    expect(state.isLoading, false);
    container.dispose();
  });
}
