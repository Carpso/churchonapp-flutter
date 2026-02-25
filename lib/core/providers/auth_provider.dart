import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';


class AuthState {
  final User? user;
  final bool isLoading;

  AuthState({this.user, this.isLoading = false});
}

class AuthNotifier extends Notifier<AuthState> {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  AuthState build() {
    try {
      final client = _client;
      client.auth.onAuthStateChange.listen((data) {
        state = AuthState(user: data.session?.user);
      });
      return AuthState(user: client.auth.currentUser);
    } catch (e) {
      debugPrint("AuthNotifier build error: $e");
      return AuthState(user: null);
    }
  }


  Future<void> signIn(String email, String password) async {
    state = AuthState(user: state.user, isLoading: true);
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } catch (e) {
      state = AuthState(user: state.user, isLoading: false);
      rethrow;
    }
  }

  Future<void> signUp(String email, String password, String name) async {
    state = AuthState(user: state.user, isLoading: true);
    try {
      await _client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );
      // Profile creation is now handled by ProfileNotifier._init on first login
      // to avoid RLS/Session timing issues during signup.
    } catch (e) {
      state = AuthState(user: state.user, isLoading: false);
      rethrow;
    } finally {
      state = AuthState(user: state.user, isLoading: false);
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});

