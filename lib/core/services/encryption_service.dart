import 'dart:convert';
import 'package:universal_io/io.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  static const int _ivLength = 16;
  static const int _saltLength = 16;

  /// Standardized Key Derivation: Derives AES-256 key from user secret and salt
  static Uint8List deriveKey(String secret, Uint8List salt) {
    final combined = utf8.encode('$secret:${base64.encode(salt)}');
    final hash = sha256.convert(combined);
    return Uint8List.fromList(hash.bytes);
  }

  static Uint8List _generateSalt() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(_saltLength, (_) => random.nextInt(256)));
  }

  static Uint8List _generateIv() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(_ivLength, (_) => random.nextInt(256)));
  }

  static Future<EncryptedDocument> encryptFile(File file, String userSecret) async {
    final fileBytes = await file.readAsBytes();
    return encryptBytes(fileBytes, userSecret);
  }

  static EncryptedDocument encryptBytes(Uint8List fileBytes, String userSecret) {
    final salt = _generateSalt();
    final iv = _generateIv();
    final key = deriveKey(userSecret, salt);

    final encrypter = encrypt.Encrypter(encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(fileBytes, iv: encrypt.IV(iv));

    return EncryptedDocument(
      data: Uint8List.fromList(encrypted.bytes),
      salt: salt,
      iv: iv,
    );
  }

  static Uint8List decryptFile(Uint8List encryptedData, String userSecret, Uint8List salt, Uint8List iv) {
    final key = deriveKey(userSecret, salt);
    final encrypter = encrypt.Encrypter(encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc));
    final decrypted = encrypter.decryptBytes(encrypt.Encrypted(encryptedData), iv: encrypt.IV(iv));
    return Uint8List.fromList(decrypted);
  }

  /// Alias for backward compatibility
  static Uint8List deriveKeyFromSalt(String secret, Uint8List salt) => deriveKey(secret, salt);
}

class EncryptedDocument {
  final Uint8List data;
  final Uint8List salt;
  final Uint8List iv;

  EncryptedDocument({required this.data, required this.salt, required this.iv});

  Map<String, dynamic> toJson() => {
    'salt': base64.encode(salt),
    'iv': base64.encode(iv),
  };
}
