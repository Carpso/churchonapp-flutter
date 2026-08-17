import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Two-factor authentication backed by Supabase Auth native MFA.
///
/// The TOTP secret lives ONLY on the Supabase Auth server (enroll/verify/
/// unenroll via the MFA API). Nothing secret is ever stored in `profiles`
/// or derived client-side, so no RLS policy can leak it and no client
/// can forge verification.
class TwoFactorService {
  final SupabaseClient _client;

  TwoFactorService(this._client);

  /// Enroll a new TOTP factor. Returns the QR code (SVG data URI) +
  /// raw secret shown once to the user. The factor is not active until
  /// [verifyAndActivate] succeeds.
  Future<AuthMFAEnrollResponse> enroll() async {
    return _client.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'ChurchOnApp',
    );
  }

  /// Confirm enrollment (and complete the login challenge when signing in)
  /// with the 6-digit code from the authenticator app. Server-side check.
  Future<void> verifyAndActivate({required String factorId, required String code}) async {
    await _client.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  /// Disable 2FA: unenroll all totp factors.
  Future<void> disable2fa() async {
    final factors = await _client.auth.mfa.listFactors();
    for (final factor in factors.totp) {
      await _client.auth.mfa.unenroll(factor.id);
    }
  }

  /// Whether the current user has an active (verified) totp factor.
  Future<bool> is2faEnabled() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final factors = await _client.auth.mfa.listFactors();
    return factors.totp.isNotEmpty;
  }
}

final twoFactorServiceProvider = Provider((ref) {
  return TwoFactorService(Supabase.instance.client);
});

final is2faEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(twoFactorServiceProvider).is2faEnabled();
});