import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/env.dart';


class AuthState {
  final User? user;
  final bool isLoading;
  final String? errorMessage;

  AuthState({this.user, this.isLoading = false, this.errorMessage});

  AuthState copyWith({User? user, bool? isLoading, String? errorMessage}) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
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
    state = AuthState(user: state.user, isLoading: true, errorMessage: null);
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } catch (e) {
      state = AuthState(user: state.user, isLoading: false, errorMessage: e.toString());
      rethrow;
    } finally {
      state = AuthState(user: state.user, isLoading: false, errorMessage: state.errorMessage);
    }
  }

  Future<void> signInWithGoogle() async {
    state = AuthState(user: state.user, isLoading: true, errorMessage: null);
    try {
      // 1. Initialize Google Sign In
      // serverClientId is required to get the idToken for Supabase
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: Env.googleWebClientId,
      );

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        state = AuthState(user: state.user, isLoading: false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw 'No ID Token found.';
      }

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } catch (e) {
      state = AuthState(user: state.user, isLoading: false, errorMessage: e.toString());
      rethrow;
    } finally {
      state = AuthState(user: state.user, isLoading: false, errorMessage: state.errorMessage);
    }
  }

  Future<void> signUp(String email, String password, String name) async {
    state = AuthState(user: state.user, isLoading: true, errorMessage: null);
    try {
      await _client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );
      // Profile creation is now handled by ProfileNotifier._init on first login
      // to avoid RLS/Session timing issues during signup.
    } catch (e) {
      state = AuthState(user: state.user, isLoading: false, errorMessage: e.toString());
      rethrow;
    } finally {
      state = AuthState(user: state.user, isLoading: false);
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    await GoogleSignIn().signOut();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});

