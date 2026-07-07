import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TwoFactorService {
  final SupabaseClient _client;

  TwoFactorService(this._client);

  static const _totpIntervalSeconds = 30;
  static const _totpDigits = 6;
  static const _issuer = 'ChurchOnApp';

  String _encryptSecret(String secret, String userId) {
    final key = sha256.convert(utf8.encode('$userId-coa-totp-v1'));
    final iv = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final secretBytes = utf8.encode(secret);
    final encrypted = <int>[];
    encrypted.addAll(iv);
    for (int i = 0; i < secretBytes.length; i++) {
      encrypted.add(secretBytes[i] ^ key.bytes[i % key.bytes.length]);
    }
    return base64.encode(encrypted);
  }

  String _decryptSecret(String encryptedBase64, String userId) {
    final key = sha256.convert(utf8.encode('$userId-coa-totp-v1'));
    final encrypted = base64.decode(encryptedBase64);
    final decrypted = <int>[];
    for (int i = 16; i < encrypted.length; i++) {
      decrypted.add(encrypted[i] ^ key.bytes[(i - 16) % key.bytes.length]);
    }
    return utf8.decode(decrypted);
  }

  String _base32Encode(List<int> bytes) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final result = StringBuffer();
    int bits = 0;
    int bitCount = 0;

    for (final byte in bytes) {
      bits = (bits << 8) | byte;
      bitCount += 8;
      while (bitCount >= 5) {
        bitCount -= 5;
        result.write(alphabet[(bits >> bitCount) & 0x1F]);
      }
    }
    if (bitCount > 0) {
      result.write(alphabet[(bits << (5 - bitCount)) & 0x1F]);
    }

    return result.toString();
  }

  List<int> _generateSecret() {
    final random = Random.secure();
    return List.generate(20, (_) => random.nextInt(256));
  }

  String generateSecretBase32() {
    return _base32Encode(_generateSecret());
  }

  String generateOtpAuthUrl(String secretBase32, String email) {
    return 'otpauth://totp/$_issuer:${Uri.encodeComponent(email)}?secret=$secretBase32&issuer=$_issuer&algorithm=SHA1&digits=$_totpDigits&period=$_totpIntervalSeconds';
  }

  int _timeCounter() {
    return (DateTime.now().millisecondsSinceEpoch / 1000 / _totpIntervalSeconds).floor();
  }

  int generateTotp(String secretBase32) {
    final secret = _base32Decode(secretBase32);
    final counter = _timeCounter();
    final counterBytes = List<int>.generate(8, (i) => (counter >> (56 - i * 8)) & 0xFF);

    final hmac = Hmac(sha1, secret).convert(counterBytes);
    final offset = hmac.bytes[hmac.bytes.length - 1] & 0xF;
    final code = ((hmac.bytes[offset] & 0x7F) << 24) |
        ((hmac.bytes[offset + 1] & 0xFF) << 16) |
        ((hmac.bytes[offset + 2] & 0xFF) << 8) |
        (hmac.bytes[offset + 3] & 0xFF);

    return code % pow(10, _totpDigits).toInt();
  }

  List<int> _base32Decode(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final clean = input.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
    final result = <int>[];
    int bits = 0;
    int bitCount = 0;

    for (final char in clean.split('')) {
      bits = (bits << 5) | alphabet.indexOf(char);
      bitCount += 5;
      if (bitCount >= 8) {
        bitCount -= 8;
        result.add((bits >> bitCount) & 0xFF);
      }
    }
    return result;
  }

  bool verifyTotp(String secretBase32, int code) {
    final expected = generateTotp(secretBase32);
    if (expected == code) return true;

    for (int offset = -1; offset <= 1; offset += 2) {
      final originalTime = _timeCounter();
      final adjustedBytes = List<int>.generate(8, (i) => ((originalTime + offset) >> (56 - i * 8)) & 0xFF);
      final hmac2 = Hmac(sha1, _base32Decode(secretBase32)).convert(adjustedBytes);
      final offset2 = hmac2.bytes[hmac2.bytes.length - 1] & 0xF;
      final code2 = ((hmac2.bytes[offset2] & 0x7F) << 24) |
          ((hmac2.bytes[offset2 + 1] & 0xFF) << 16) |
          ((hmac2.bytes[offset2 + 2] & 0xFF) << 8) |
          (hmac2.bytes[offset2 + 3] & 0xFF);
      if (code2 % pow(10, _totpDigits).toInt() == code) return true;
    }
    return false;
  }

  Future<void> enable2fa(String secretBase32) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    final encrypted = _encryptSecret(secretBase32, user.id);

    await _client.from('profiles').update({
      'totp_secret': encrypted,
      'totp_enabled': true,
    }).eq('id', user.id);
  }

  Future<void> disable2fa() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    await _client.from('profiles').update({
      'totp_secret': null,
      'totp_enabled': false,
    }).eq('id', user.id);
  }

  Future<bool> is2faEnabled() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    final res = await _client
        .from('profiles')
        .select('totp_enabled')
        .eq('id', user.id)
        .maybeSingle();

    return res?['totp_enabled'] == true;
  }

  Future<String?> getSecret() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final res = await _client
        .from('profiles')
        .select('totp_secret')
        .eq('id', user.id)
        .maybeSingle();

    final encrypted = res?['totp_secret']?.toString();
    if (encrypted == null) return null;

    try {
      return _decryptSecret(encrypted, user.id);
    } catch (_) {
      return null;
    }
  }
}

final twoFactorServiceProvider = Provider((ref) {
  return TwoFactorService(Supabase.instance.client);
});

final is2faEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(twoFactorServiceProvider).is2faEnabled();
});
