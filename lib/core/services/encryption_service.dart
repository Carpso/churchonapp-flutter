import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  static const int _ivLength = 16;

  static Uint8List _deriveKey(String secret) {
    final hash = sha256.convert(utf8.encode(secret));
    return Uint8List.fromList(hash.bytes);
  }

  static Uint8List _generateIv() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(_ivLength, (_) => random.nextInt(256)));
  }

  static EncryptedDocument encryptFile(File file, String userSecret) {
    final key = _deriveKey(userSecret);
    final iv = _generateIv();
    final fileBytes = file.readAsBytesSync();
    return _encryptBytes(fileBytes, key, iv);
  }

  static Uint8List decryptFile(Uint8List encryptedData, String userSecret, Uint8List salt, Uint8List iv) {
    final key = deriveKeyFromSalt(userSecret, salt);
    final encrypter = encrypt.Encrypter(encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc));
    final decrypted = encrypter.decryptBytes(encrypt.Encrypted(encryptedData), iv: encrypt.IV(iv));
    return Uint8List.fromList(decrypted);
  }

  static EncryptedDocument _encryptBytes(Uint8List data, Uint8List key, Uint8List iv) {
    final encrypter = encrypt.Encrypter(encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(data, iv: encrypt.IV(iv));
    return EncryptedDocument(
      data: Uint8List.fromList(encrypted.bytes),
      salt: key,
      iv: iv,
    );
  }

  static Uint8List deriveKeyFromSalt(String secret, Uint8List salt) {
    final hash = sha256.convert(utf8.encode('$secret-${base64.encode(salt)}'));
    return Uint8List.fromList(hash.bytes);
  }
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
