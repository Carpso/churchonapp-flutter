import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LiveStreamStatus {
  final bool isLive;
  final String? streamUrl;
  final String? title;
  final int viewerCount;

  LiveStreamStatus({
    required this.isLive,
    this.streamUrl,
    this.title,
    this.viewerCount = 0,
  });

  factory LiveStreamStatus.fromMap(Map<String, dynamic> map) {
    return LiveStreamStatus(
      isLive: map['is_live'] ?? false,
      streamUrl: map['stream_url'],
      title: map['title'] ?? 'Church Service',
      viewerCount: map['viewer_count'] ?? 0,
    );
  }
}

class LiveStreamingService {
  final SupabaseClient _client;
  LiveStreamingService(this._client);

  Stream<LiveStreamStatus> streamLiveStatus(String churchId) {
    return _client
        .from('church_live_status')
        .stream(primaryKey: ['id'])
        .eq('church_id', churchId)
        .limit(1)
        .map((data) => data.isNotEmpty 
            ? LiveStreamStatus.fromMap(data.first) 
            : LiveStreamStatus(isLive: false));
  }

  Future<void> setLiveStatus(String churchId, bool isLive, {String? streamUrl, String? title}) async {
    await _client.from('church_live_status').upsert({
      'church_id': churchId,
      'is_live': isLive,
      if (streamUrl != null) 'stream_url': streamUrl,
      if (title != null) 'title': title,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}

final liveStreamingServiceProvider = Provider((ref) => LiveStreamingService(Supabase.instance.client));

final liveStatusProvider = StreamProvider.family<LiveStreamStatus, String>((ref, churchId) {
  return ref.watch(liveStreamingServiceProvider).streamLiveStatus(churchId);
});

