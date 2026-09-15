import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/services/r2_service.dart';
import 'package:church_on_app/core/services/encryption_service.dart';

enum KycStatus { unverified, pending, verified, rejected }

class KycDocument {
  final String id;
  final String type;
  final String url;
  final String status;

  KycDocument({required this.id, required this.type, required this.url, required this.status});

  factory KycDocument.fromMap(Map<String, dynamic> map) => KycDocument(
    id: map['id']?.toString() ?? '',
    type: map['document_type']?.toString() ?? 'id',
    url: map['url']?.toString() ?? '',
    status: map['status']?.toString() ?? 'pending',
  );
}

class KycService {
  final SupabaseClient _client;

  KycService(this._client);

  Future<KycStatus> getStatus() async {
    final user = _client.auth.currentUser;
    if (user == null) return KycStatus.unverified;
    final res = await _client.from('profiles').select('kyc_status').eq('id', user.id).maybeSingle();
    if (res == null) return KycStatus.unverified;
    final status = (res['kyc_status'] as String?) ?? 'unverified';
    switch (status) {
      case 'pending': return KycStatus.pending;
      case 'verified': return KycStatus.verified;
      case 'rejected': return KycStatus.rejected;
      default: return KycStatus.unverified;
    }
  }

  String _deriveEncryptionKey(String userId) => deriveUserKey(userId);

  /// Derives the per-user KYC encryption key.
  ///
  /// PUBLIC + static on purpose: a reviewer (COA/superadmin) decrypts documents
  /// they did not create, so the same derivation must be reusable from the KYC
  /// review screen.
  static String deriveUserKey(String userId) {
    final configSecret = const String.fromEnvironment('KYC_ENCRYPTION_SECRET',
        defaultValue: 'churchonapp-kyc-v1');
    final hash = sha256.convert(utf8.encode('$userId-$configSecret'));
    return hash.toString();
  }

  /// Downloads a stored (private, encrypted) KYC document, decrypts it, and
  /// returns the raw bytes — ready to render as an image / open as a PDF.
  ///
  /// Works for the owner AND for COA reviewers (`r2-sign` allows COA staff to
  /// read any user's `kyc/…` object).
  static Future<Uint8List?> fetchDecryptedDocument({
    required Map<String, dynamic> doc,
    required String userId,
  }) async {
    final ref = doc['url']?.toString() ?? '';
    final saltB64 = doc['encrypted_key']?.toString() ?? '';
    final ivB64 = doc['encryption_iv']?.toString() ?? '';
    if (ref.isEmpty || saltB64.isEmpty || ivB64.isEmpty) {
      debugPrint('KYC: document missing url/salt/iv — cannot decrypt');
      return null;
    }
    try {
      final client = Supabase.instance.client;
      final signed = await R2Service(client).resolvePrivateUrl(ref);
      if (signed == null) {
        debugPrint('KYC: could not sign $ref');
        return null;
      }
      final res = await http.get(Uri.parse(signed));
      if (res.statusCode != 200) {
        debugPrint('KYC: download failed ${res.statusCode}');
        return null;
      }
      return EncryptionService.decryptFile(
        res.bodyBytes,
        deriveUserKey(userId),
        base64.decode(saltB64),
        base64.decode(ivB64),
      );
    } catch (e) {
      debugPrint('KYC: decrypt failed: $e');
      return null;
    }
  }

  Future<void> submitDocument({required String filePath, required String documentType}) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return submitDocumentBytes(bytes: bytes, documentType: documentType);
  }

  Future<void> submitDocumentBytes({required Uint8List bytes, required String documentType}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    final userSecret = _deriveEncryptionKey(user.id);
    final encrypted = EncryptionService.encryptBytes(bytes, userSecret);

    final fileName = '${user.id}_${documentType}_${DateTime.now().millisecondsSinceEpoch}.enc';
    final r2 = R2Service(_client);
    // SECURITY: KYC must NOT go in the public media bucket. Target the private
    // `choa-kyc-vault` bucket; the returned value is an `r2://` reference, not
    // a public URL.
    final url = await r2.uploadBytes(encrypted.data, 'kyc/$fileName',
        contentType: 'application/octet-stream', bucket: 'choa-kyc-vault');
    if (url == null) throw Exception("Upload failed");

    await _client.from('kyc_documents').insert({
      'user_id': user.id,
      'document_type': documentType,
      'url': url,
      'status': 'pending',
      'encrypted_key': base64.encode(encrypted.salt),
      'encryption_iv': base64.encode(encrypted.iv),
    });

    await _client.from('profiles').update({'kyc_status': 'pending'}).eq('id', user.id);
  }

  Future<void> submitSelfie({required String filePath}) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return submitSelfieBytes(bytes: bytes);
  }

  Future<void> submitSelfieBytes({required Uint8List bytes}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    final userSecret = _deriveEncryptionKey(user.id);
    final encrypted = EncryptionService.encryptBytes(bytes, userSecret);

    final fileName = '${user.id}_selfie_${DateTime.now().millisecondsSinceEpoch}.enc';
    final r2 = R2Service(_client);
    // SECURITY: KYC must NOT go in the public media bucket. Target the private
    // `choa-kyc-vault` bucket; the returned value is an `r2://` reference, not
    // a public URL.
    final url = await r2.uploadBytes(encrypted.data, 'kyc/$fileName',
        contentType: 'application/octet-stream', bucket: 'choa-kyc-vault');
    if (url == null) throw Exception("Upload failed");

    await _client.from('kyc_documents').insert({
      'user_id': user.id,
      'document_type': 'selfie',
      'url': url,
      'status': 'pending',
      'encrypted_key': base64.encode(encrypted.salt),
      'encryption_iv': base64.encode(encrypted.iv),
    });
  }

  Future<List<KycDocument>> getDocuments() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    final data = await _client.from('kyc_documents').select().eq('user_id', user.id).order('created_at', ascending: false);
    return (data as List).map((map) => KycDocument.fromMap(map)).toList();
  }
}

final kycServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return KycService(client);
});

final kycStatusProvider = FutureProvider<KycStatus>((ref) {
  return ref.watch(kycServiceProvider).getStatus();
});
