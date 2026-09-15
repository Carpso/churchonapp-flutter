import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Result of a Cloudflare Stream VOD upload.
class VodUploadResult {
  final String uid;
  final String hlsUrl;
  final String thumbnailUrl;
  final int durationSeconds;

  const VodUploadResult({
    required this.uid,
    required this.hlsUrl,
    required this.thumbnailUrl,
    required this.durationSeconds,
  });

  bool get hasPlayback => hlsUrl.isNotEmpty;
}

/// Uploads sermon/teaching video to Cloudflare Stream via Direct Creator
/// Upload, so Cloudflare transcodes the source into an adaptive-bitrate HLS
/// ladder (up to the source resolution, e.g. 1080p) with an auto-generated
/// thumbnail — i.e. proper streaming VOD rather than a raw progressive file.
class VodUploadService {
  final SupabaseClient _client;
  VodUploadService(this._client);

  Future<VodUploadResult?> uploadVideo(
    Uint8List bytes, {
    required String filename,
    String? churchId,
    int maxDurationSeconds = 14400,
  }) async {
    try {
      final res = await _client.functions.invoke('cloudflare-stream', body: {
        'action': 'create_upload_url',
        'max_duration_seconds': maxDurationSeconds,
        'meta': {
          'name': filename,
          if (churchId != null) 'church_id': churchId,
        },
      });

      final data = res.data as Map<String, dynamic>?;
      if (data == null || data['success'] != true) {
        debugPrint('VOD: create_upload_url failed: ${data?['error']}');
        return null;
      }

      final uploadURL = data['uploadURL'] as String?;
      final uid = data['uid'] as String?;
      if (uploadURL == null || uid == null) {
        debugPrint('VOD: create_upload_url returned no uploadURL/uid');
        return null;
      }

      final put = await http.put(
        Uri.parse(uploadURL),
        body: bytes,
        headers: const {'Content-Type': 'application/octet-stream'},
      );
      if (put.statusCode < 200 || put.statusCode >= 300) {
        debugPrint('VOD: upload PUT failed ${put.statusCode} ${put.body}');
        return null;
      }

      // Poll until Cloudflare finishes transcoding (up to ~3 minutes).
      for (var i = 0; i < 36; i++) {
        await Future.delayed(const Duration(seconds: 5));
        final poll = await _client.functions.invoke('cloudflare-stream', body: {
          'action': 'get_video',
          'video_id': uid,
        });
        final pd = poll.data as Map<String, dynamic>?;
        if (pd != null && pd['success'] == true && pd['readyToStream'] == true) {
          return VodUploadResult(
            uid: uid,
            hlsUrl: (pd['hls'] as String?) ?? '',
            thumbnailUrl: (pd['thumbnail'] as String?) ?? '',
            durationSeconds: (pd['duration'] as num?)?.round() ?? 0,
          );
        }
      }

      // Upload accepted but still transcoding — caller can fall back or retry.
      debugPrint('VOD: upload accepted but still processing (uid=$uid)');
      return VodUploadResult(
        uid: uid,
        hlsUrl: '',
        thumbnailUrl: '',
        durationSeconds: 0,
      );
    } catch (e) {
      debugPrint('VOD upload error: $e');
      return null;
    }
  }
}

final vodUploadServiceProvider = Provider((ref) {
  return VodUploadService(ref.watch(supabaseServiceProvider).client);
});
