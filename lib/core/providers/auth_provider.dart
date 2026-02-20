import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthState {
  final User? user;
  final bool isLoading;

  AuthState({this.user, this.isLoading = false});
}

class AuthNotifier extends Notifier<AuthState> {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  AuthState build() {
    _client.auth.onAuthStateChange.listen((data) {
      state = AuthState(user: data.session?.user);
    });
    return AuthState(user: _client.auth.currentUser);
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
