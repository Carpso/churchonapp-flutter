import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_io/io.dart';

import 'package:church_on_app/core/services/r2_service.dart';

/// Uploads a locally recorded service (the phone-camera / WHIP path) to R2 and
/// points the stream row's `archive_url` at it.
///
/// WHY THIS EXISTS: Cloudflare never records a WHIP/WebRTC broadcast, so for a
/// quick-camera broadcast the local MP4 the studio writes during the service is
/// the ONLY replay that will ever exist. Once `archive_url` is set on an
/// ended/archived row, the `trg_live_stream_recorded_service` trigger fires
/// `sync_recorded_service`, and `playable_recording_url` prefers the R2 master
/// — the sermon replay appears in the Sermons tab with no Cloudflare Stream
/// recording involved.
///
/// Uploads can fail (a rural network dropping mid-service is the norm, not the
/// exception), so a failed attempt is queued in SharedPreferences and retried
/// automatically the next time the studio opens. The local file is NEVER
/// deleted here — the OS manages eviction of the temporary directory.
class ServiceRecordingUpload {
  ServiceRecordingUpload._();

  static const _pendingKey = 'coa_pending_service_recordings';

  /// Uploads [filePath] and archives it onto stream [streamId].
  ///
  /// Returns the stored public URL on success, or null on failure (the local
  /// file is kept either way; call [enqueuePending] to schedule a retry).
  static Future<String?> uploadAndArchive({
    required String streamId,
    required String filePath,
  }) async {
    try {
      final f = File(filePath);
      if (!await f.exists() || await f.length() == 0) {
        debugPrint(
            'Service recording missing/empty - nothing to upload: $filePath');
        return null;
      }

      // One object per stream: re-uploads (manual or queued retry) overwrite
      // idempotently instead of accumulating duplicates in the bucket.
      final key = 'sermons/service-recording/$streamId.mp4';
      final url = await R2Service(Supabase.instance.client)
          .uploadLargeFile(f, key);
      if (url == null) {
        debugPrint('Service recording upload failed: ${R2Service.lastError}');
        return null;
      }

      // Setting archive_url on the row fires trg_live_stream_recorded_service
      // -> sync_recorded_service -> the sermon replay. archive_status='ready'
      // is deliberately NOT in mark_whip_unrecordable's clobber list, so the
      // WHIP trigger will not overwrite it.
      await Supabase.instance.client.from('live_streams').update({
        'archive_url': url,
        'archive_status': 'ready',
      }).eq('id', streamId);

      debugPrint('Service recording archived: $url');
      return url;
    } catch (e) {
      debugPrint('Service recording archive error: $e');
      return null;
    }
  }

  /// Remembers a failed upload so it can be retried later. Idempotent per
  /// stream (a stream only ever has one recording entry).
  static Future<void> enqueuePending(String streamId, String filePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_pendingKey) ?? <String>[];
      final filtered =
          list.where((e) => !e.startsWith('$streamId|')).toList()
            ..add('$streamId|$filePath');
      await prefs.setStringList(_pendingKey, filtered);
    } catch (e) {
      debugPrint('Failed to queue pending service recording: $e');
    }
  }

  /// Retries any queued recordings. Called when the studio opens. Files that
  /// no longer exist (OS-evicted temp) are dropped; successful uploads are
  /// dequeued; failures stay queued for the next attempt.
  static Future<void> retryPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_pendingKey) ?? <String>[];
      if (list.isEmpty) return;
      debugPrint('Retrying ${list.length} pending service recording(s)…');
      final remaining = <String>[];
      for (final entry in list) {
        final i = entry.indexOf('|');
        if (i <= 0) continue;
        final streamId = entry.substring(0, i);
        final path = entry.substring(i + 1);
        final url =
            await uploadAndArchive(streamId: streamId, filePath: path);
        if (url == null) {
          final f = File(path);
          if (await f.exists()) remaining.add(entry);
        }
      }
      await prefs.setStringList(_pendingKey, remaining);
    } catch (e) {
      debugPrint('Pending service-recording retry failed: $e');
    }
  }
}
