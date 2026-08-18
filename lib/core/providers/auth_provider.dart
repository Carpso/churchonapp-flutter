import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';
import '../services/tenant_service.dart';

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

      // Check if 2FA is enabled (server-side factor check) — if so, do NOT
      // set user yet; the session is at AAL1 until the code is verified.
      if (authResult.user != null) {
        try {
          final factors = authResult.user?.factors ?? const <Factor>[];
          final requires2fa =
              factors.any((f) => f.status == FactorStatus.verified);
          if (requires2fa) {
            state = AuthState(user: null, isLoading: false, requires2FA: true);
            return;
          }
        } catch (e) {
          debugPrint('2FA check failed, proceeding without 2FA: $e');
        }
      }

      state = AuthState(user: authResult.user, isLoading: false);
    } catch (e) {
      var message = _friendlyAuthError(e);
      state = AuthState(user: state.user, isLoading: false, errorMessage: message);
      rethrow;
    }
  }

  static String _friendlyAuthError(Object e) {
    final msg = e.toString();
    final lower = msg.toLowerCase();
    if (lower.contains('invalid login credentials') || lower.contains('invalid_credentials')) {
      return 'Wrong email or password. Please check and try again.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Please confirm your email address first, then sign in.';
    }
    if (lower.contains('rate limit') || lower.contains('too many')) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    if (e is AuthException && e.message.isNotEmpty) {
      return e.message;
    }
    return msg;
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
      state = AuthState(user: state.user, isLoading: false, errorMessage: _friendlyAuthError(e));
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
    
    // Clear current tenant context to prevent data leakage on next login
    await ref.read(currentTenantProvider.notifier).setTenant(null);
    
    await _client.auth.signOut();
    await GoogleSignIn().signOut();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
