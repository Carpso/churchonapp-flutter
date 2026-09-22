import 'package:image_picker/image_picker.dart';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_service.dart';
import '../config/env.dart';

class R2Service {
  static const int _maxImageSize = 10 * 1024 * 1024;
  static const int _maxVideoSize = 100 * 1024 * 1024;
  static const int _maxDocumentSize = 20 * 1024 * 1024;

  /// Why the most recent [uploadFile]/[uploadBytes] returned null. Callers can
  /// surface this so a failed upload is never a silent no-op.
  static String? lastError;

  static String? _fail(String message) {
    lastError = message;
    debugPrint('R2 Upload Error: $message');
    return null;
  }

  static const Set<String> _allowedExtensions = {
    '.jpg', '.jpeg', '.png', '.gif', '.webp',
    '.mp4', '.mov', '.avi', '.mkv', '.webm',
    '.pdf', '.doc', '.docx', '.xls', '.xlsx',
    '.txt', '.csv', '.md',
    '.mp3', '.wav', '.aac', '.ogg', '.m4a',
  };

  static String get publicDomain => Env.r2PublicDomain;

  // Legacy signed-URL cache. No longer used for reads (the bucket is public),
  // but kept so `invalidateReadCache` remains a safe no-op for callers.
  static final Map<String, String> _readUrlCache = {};
  static final Map<String, DateTime> _readUrlCacheAt = {};

  /// Resolves an R2 public-domain URL to something the <img>/player can load.
  ///
  /// `media.churchonapp.com` (bucket `choa-sermons-vault`) is now a PUBLIC R2
  /// domain with a CORS policy, so the stored URL is used **as-is** — no edge
  /// round-trip, no 50-minute signed-URL expiry, and no dependency on the
  /// `r2-sign` function for read traffic. (Signing previously produced URLs on
  /// the `*.r2.cloudflarestorage.com` endpoint, which browsers can block.)
  ///
  /// Sensitive material must NOT live in this bucket — KYC files are uploaded to
  /// the private `choa-kyc-vault` bucket instead and are referenced as `r2://…`.
  static Future<String> resolveReadUrl(String url) async {
    // Public bucket → return unchanged. Non-R2 URLs also pass through.
    return url;
  }

  /// Force-clear a cached signed URL so the next resolve call fetches a
  /// fresh one. Used by AppImage retry when a signed URL expires mid-scroll.
  static void invalidateReadCache(String url) {
    _readUrlCache.remove(url);
    _readUrlCacheAt.remove(url);
  }

  final SupabaseClient _client;
  R2Service(this._client);

  Future<String?> uploadAvatar(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null) return null;
    final file = File(picked.path);
    final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final url = await uploadFile(file, 'avatars/$fileName');
    if (url == null) return null;
    final user = _client.auth.currentUser;
    if (user != null) {
      await _client.from('profiles').update({
        'avatar_url': url,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);
    }
    return url;
  }

  // NOTE: no silent fallback to another storage system — every media upload
  // must land in R2 (`media.churchonapp.com`) so URLs are consistent and a
  // failure is visible to the caller instead of scattering files elsewhere.
  Future<String?> uploadFile(File file, String path) async {
    lastError = null;
    try {
      final fileSize = await file.length();
      final extension = path.split('.').last.toLowerCase();

      if (!_allowedExtensions.contains('.$extension')) {
        return _fail('File type .$extension is not allowed');
      }

      final contentType = _getContentType(file.path);
      if (contentType.startsWith('image/') && fileSize > _maxImageSize) {
        return _fail('Image exceeds the 10MB limit');
      }
      if (contentType.startsWith('video/') && fileSize > _maxVideoSize) {
        return _fail('Video exceeds the 100MB limit');
      }
      if (contentType == 'application/pdf' && fileSize > _maxDocumentSize) {
        return _fail('Document exceeds the 20MB limit');
      }

      final response = await _client.functions.invoke('r2-sign', body: {
        'filename': path.split('/').last,
        'contentType': _getContentType(file.path),
        'folder': path.split('/').first,
      });

      if (response.status == 200) {
        final signedUrl = response.data['signedUrl'];
        final publicUrl = response.data['publicUrl'];
        if (signedUrl == null) return _fail('Storage did not return an upload URL');

        final uploadResponse = await http.put(
          Uri.parse(signedUrl),
          body: await file.readAsBytes(),
          headers: {'Content-Type': _getContentType(file.path)},
        );

        if (uploadResponse.statusCode == 200) {
          String url = publicUrl ?? '';
          if (url.contains("media.church-on-app.com")) {
            url = url.replaceAll("media.church-on-app.com", publicDomain);
          }
          return url.isNotEmpty ? url : _fail('Storage returned an empty URL');
        }
        return _fail('Upload rejected by storage (HTTP ${uploadResponse.statusCode})');
      }
      return _fail('Upload could not be authorised (HTTP ${response.status})');
    } catch (e) {
      return _fail(e.toString());
    }
  }

  Future<String?> uploadBytes(Uint8List bytes, String path, {String? contentType, String? bucket}) async {
    lastError = null;
    try {
      final extension = path.split('.').last.toLowerCase();
      if (!_allowedExtensions.contains('.$extension')) {
        return _fail('File type .$extension is not allowed');
      }
      if (bytes.length > _maxImageSize && (contentType?.startsWith('image/') ?? false)) {
        return _fail('Image exceeds the 10MB limit');
      }

      final response = await _client.functions.invoke('r2-sign', body: {
        'filename': path.split('/').last,
        'contentType': contentType ?? 'application/octet-stream',
        'folder': path.split('/').first,
        if (bucket != null) 'bucket': bucket,
      });

      if (response.status == 200) {
        final signedUrl = response.data['signedUrl'];
        final publicUrl = response.data['publicUrl'];
        if (signedUrl == null) return _fail('Storage did not return an upload URL');

        final uploadResponse = await http.put(
          Uri.parse(signedUrl),
          body: bytes,
          headers: {'Content-Type': contentType ?? 'application/octet-stream'},
        );

        if (uploadResponse.statusCode == 200) {
          String url = publicUrl ?? '';
          // Private buckets return an `r2://` reference — never rewrite those.
          if (!url.startsWith('r2://') && url.contains("media.church-on-app.com")) {
            url = url.replaceAll("media.church-on-app.com", publicDomain);
          }
          return url.isNotEmpty ? url : _fail('Storage returned an empty URL');
        }
        return _fail('Upload rejected by storage (HTTP ${uploadResponse.statusCode})');
      }
      return _fail('Upload could not be authorised (HTTP ${response.status})');
    } catch (e) {
      return _fail(e.toString());
    }
  }

  /// Resolves a private-bucket reference (`r2://<bucket>/<key>`, as stored for
  /// KYC documents) into a short-lived signed URL via the `r2-sign` function.
  ///
  /// Anyone (the owner) can read their own `kyc/…` docs; COA staff/superadmins
  /// can read any user's, which is what makes driver/verified-user KYC review
  /// possible. Returns `ref` unchanged when it is already an http(s) URL.
  Future<String?> resolvePrivateUrl(String ref, {int expiresIn = 3600}) async {
    final trimmed = ref.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('r2://')) return trimmed;

    final withoutScheme = trimmed.substring('r2://'.length);
    final slash = withoutScheme.indexOf('/');
    if (slash <= 0 || slash == withoutScheme.length - 1) {
      debugPrint('resolvePrivateUrl: malformed reference "$ref"');
      return null;
    }
    final bucket = withoutScheme.substring(0, slash);
    final key = withoutScheme.substring(slash + 1);
    try {
      final res = await _client.functions.invoke('r2-sign', body: {
        'action': 'read',
        'bucket': bucket,
        'key': key,
      });
      if (res.status == 200) {
        return res.data['signedUrl'] as String?;
      }
      debugPrint('resolvePrivateUrl: r2-sign ${res.status} for $key');
    } catch (e) {
      debugPrint('resolvePrivateUrl failed: $e');
    }
    return null;
  }

  Future<String?> getSignedUrl(String url, {int expiresIn = 3600}) async {
    // The media bucket is PUBLIC + CORS-enabled, so the stored URL is directly
    // usable. Do NOT exchange it for an S3-presigned URL — that points at
    // `*.r2.cloudflarestorage.com`, which browsers can block. Signing is only
    // meaningful for private buckets (see the upload path / `r2://` references).
    final pubDomain = publicDomain.replaceAll('https://', '');
    if (url.startsWith('https://$pubDomain/') || url.startsWith('$pubDomain/')) {
      return url;
    }
    try {
      final r2Prefix = 'https://$pubDomain/';
      if (!url.startsWith(r2Prefix)) return url;

      final key = url.substring(r2Prefix.length);
      final response = await _client.functions.invoke('r2-sign', body: {
        'action': 'read',
        'key': key,
      });

      if (response.status == 200) {
        return response.data['signedUrl'] as String? ?? url;
      }
    } catch (e) {
      debugPrint("R2 getSignedUrl error: $e");
    }
    return url;
  }

  String _getContentType(String path) {
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.gif')) return 'image/gif';
    if (path.endsWith('.webp')) return 'image/webp';
    if (path.endsWith('.mp4')) return 'video/mp4';
    if (path.endsWith('.mov')) return 'video/quicktime';
    if (path.endsWith('.pdf')) return 'application/pdf';
    if (path.endsWith('.mp3')) return 'audio/mpeg';
    if (path.endsWith('.wav')) return 'audio/wav';
    if (path.endsWith('.m4a')) return 'audio/mp4';
    if (path.endsWith('.aac')) return 'audio/aac';
    if (path.endsWith('.ogg')) return 'audio/ogg';
    return 'application/octet-stream';
  }
}

final r2ServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return R2Service(client);
});

