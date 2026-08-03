import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';

class AuthState {
  final User? user;
  final bool isLoading;
  final String? errorMessage;
  final bool requires2FA;

  AuthState({this.user, this.isLoading = false, this.errorMessage, this.requires2FA = false});

  AuthState copyWith({User? user, bool? isLoading, String? errorMessage, bool? requires2FA}) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      requires2FA: requires2FA ?? this.requires2FA,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  SupabaseClient get _client => Supabase.instance.client;

  /// Redirect target for OAuth flows. On web this is the app's own origin
  /// (e.g. https://churchonapp.com) — never null, otherwise GoTrue falls back
  /// to the project Site URL which defaults to http://localhost:3000.
  /// On mobile it's the app deep link scheme.
  String get _oauthRedirectTo =>
      kIsWeb ? Uri.base.origin : 'io.supabase.churchonapp://login-callback';

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
      final authResult = await _client.auth.signInWithPassword(email: email, password: password);

      try {
        final uid = _client.auth.currentUser?.id;
        if (uid != null) {
          await _client.from('login_history').insert({
            'user_id': uid,
            'status': 'success',
            'device_info': 'Flutter App',
            'user_agent': 'ChurchOnApp/Flutter',
          });
        }
      } catch (logErr) {
        debugPrint('Failed to log login history: $logErr');
      }

      // Check if 2FA is enabled — if so, do NOT set user yet
      if (authResult.user != null) {
        try {
          final profile = await _client
              .from('profiles')
              .select('totp_enabled')
              .eq('id', authResult.user!.id)
              .maybeSingle();
          final totpEnabled = profile?['totp_enabled'] == true;
          if (totpEnabled) {
            state = AuthState(user: null, isLoading: false, requires2FA: true);
            return;
          }
        } catch (e) {
          debugPrint('2FA check failed, proceeding without 2FA: $e');
        }
      }

      state = AuthState(user: authResult.user, isLoading: false);
    } catch (e) {
      state = AuthState(user: state.user, isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> signInWithGoogle() async {
    state = AuthState(user: state.user, isLoading: true, errorMessage: null);
    try {
      final rawClientId = Env.googleWebClientId.trim();
      final webClientId = rawClientId.isNotEmpty ? rawClientId : null;

      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: kIsWeb ? webClientId : null,
        serverClientId: webClientId,
      );

      try {
        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          state = AuthState(user: state.user, isLoading: false);
          return;
        }

        final googleAuth = await googleUser.authentication;
        final accessToken = googleAuth.accessToken;
        final idToken = googleAuth.idToken;

        if (idToken != null) {
          final response = await _client.auth.signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken,
            accessToken: accessToken,
          );
          if (response.user != null) {
            state = AuthState(user: response.user, isLoading: false);
          }
        } else {
          // Fallback to Supabase OAuth if ID token missing
          await _client.auth.signInWithOAuth(
            OAuthProvider.google,
            redirectTo: _oauthRedirectTo,
          );
        }
      } catch (nativeError) {
        debugPrint("Native Google Sign-In failed: $nativeError. Attempting OAuth redirect fallback.");
        await _client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: _oauthRedirectTo,
        );
      }

      try {
        final uid = _client.auth.currentUser?.id;
        if (uid != null) {
          await _client.from('login_history').insert({
            'user_id': uid,
            'status': 'success',
            'device_info': 'Flutter App (Google)',
            'user_agent': 'ChurchOnApp/Flutter',
          });
        }
      } catch (logErr) {
        debugPrint('Failed to log login history: $logErr');
      }
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
    } catch (e) {
      state = AuthState(user: state.user, isLoading: false, errorMessage: e.toString());
      rethrow;
    } finally {
      state = AuthState(user: state.user, isLoading: false);
    }
  }

  Future<bool> complete2FA(String code) async {
    try {
      state = state.copyWith(isLoading: true);
      final factors = await _client.auth.mfa.listFactors();
      final totpFactors = factors.totp;
      if (totpFactors.isEmpty) {
        state = state.copyWith(isLoading: false, errorMessage: "No 2FA factors found");
        return false;
      }
      final totpFactor = totpFactors.first;
      await _client.auth.mfa.challengeAndVerify(
        factorId: totpFactor.id,
        code: code,
      );
      state = state.copyWith(isLoading: false, requires2FA: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('remember_me');
    await prefs.remove('remembered_email');
    await _client.auth.signOut();
    await GoogleSignIn().signOut();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
