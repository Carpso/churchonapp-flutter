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

  static const Set<String> _allowedExtensions = {
    '.jpg', '.jpeg', '.png', '.gif', '.webp',
    '.mp4', '.mov', '.avi', '.mkv', '.webm',
    '.pdf', '.doc', '.docx', '.xls', '.xlsx',
    '.mp3', '.wav', '.aac', '.ogg',
  };

  static String get publicDomain => Env.r2PublicDomain;

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

  Future<String?> uploadFile(File file, String path) async {
    try {
      final fileSize = await file.length();
      final extension = path.split('.').last.toLowerCase();

      if (!_allowedExtensions.contains('.$extension')) {
        debugPrint("R2 Upload Error: File type .$extension not allowed");
        return null;
      }

      final contentType = _getContentType(file.path);
      if (contentType.startsWith('image/') && fileSize > _maxImageSize) {
        debugPrint("R2 Upload Error: Image exceeds 10MB limit");
        return null;
      }
      if (contentType.startsWith('video/') && fileSize > _maxVideoSize) {
        debugPrint("R2 Upload Error: Video exceeds 100MB limit");
        return null;
      }
      if (contentType == 'application/pdf' && fileSize > _maxDocumentSize) {
        debugPrint("R2 Upload Error: Document exceeds 20MB limit");
        return null;
      }

      final response = await _client.functions.invoke('r2-sign', body: {
        'filename': path.split('/').last,
        'contentType': _getContentType(file.path),
        'folder': path.split('/').first,
      });

      if (response.status == 200) {
        final signedUrl = response.data['signedUrl'];
        final publicUrl = response.data['publicUrl'];

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
          return url.isNotEmpty ? url : null;
        }
      }
      return await _uploadToSupabaseStorageFallback(file, path);
    } catch (e) {
      debugPrint("R2 Upload Error: $e, trying Supabase Storage fallback...");
      return _uploadToSupabaseStorageFallback(file, path);
    }
  }

  Future<String?> uploadBytes(Uint8List bytes, String path, {String? contentType}) async {
    try {
      final extension = path.split('.').last.toLowerCase();
      if (!_allowedExtensions.contains('.$extension')) {
        debugPrint("R2 Upload Error: File type .$extension not allowed");
        return null;
      }
      if (bytes.length > _maxImageSize && (contentType?.startsWith('image/') ?? false)) {
        debugPrint("R2 Upload Error: Image exceeds 10MB limit");
        return null;
      }

      final response = await _client.functions.invoke('r2-sign', body: {
        'filename': path.split('/').last,
        'contentType': contentType ?? 'application/octet-stream',
        'folder': path.split('/').first,
      });

      if (response.status == 200) {
        final signedUrl = response.data['signedUrl'];
        final publicUrl = response.data['publicUrl'];

        final uploadResponse = await http.put(
          Uri.parse(signedUrl),
          body: bytes,
          headers: {'Content-Type': contentType ?? 'application/octet-stream'},
        );

        if (uploadResponse.statusCode == 200) {
          String url = publicUrl ?? '';
          if (url.contains("media.church-on-app.com")) {
            url = url.replaceAll("media.church-on-app.com", publicDomain);
          }
          return url.isNotEmpty ? url : null;
        }
        debugPrint('R2 Upload Error: PUT failed with ${uploadResponse.statusCode}');
      } else {
        debugPrint('R2 Upload Error: r2-sign failed with ${response.status}');
      }
    } catch (e) {
      debugPrint('R2 Upload Error: $e');
    }
    return null;
  }

  Future<String?> getSignedUrl(String url, {int expiresIn = 3600}) async {
    try {
      final pubDomain = publicDomain.replaceAll('https://', '');
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

  Future<String?> _uploadToSupabaseStorageFallback(File file, String path) async {
    try {
      const bucket = 'sermons-vault';
      final storagePath = path;
      await _client.storage.from(bucket).upload(
        storagePath,
        file,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );
      return _client.storage.from(bucket).getPublicUrl(storagePath);
    } catch (e) {
      debugPrint("Supabase Storage Fallback Upload Error: $e");
      return null;
    }
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
    return 'application/octet-stream';
  }
}

final r2ServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return R2Service(client);
});

