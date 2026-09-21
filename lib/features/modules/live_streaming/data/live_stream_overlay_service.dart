import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/services/supabase_service.dart';

/// One ephemeral "on air" overlay row per live stream: the verse of the moment,
/// the streamer's scrolling theme/message and the ticker settings.
///
/// Transported over Supabase Realtime so a change made in the studio appears on
/// every viewer within a second.
class LiveStreamOverlay {
  final String streamId;
  final String? verseText;
  final String? verseRef;
  final String? tickerMessage;
  final int tickerSpeed;
  final bool tickerEnabled;
  final String? logoUrl;
  final String? speakerName;
  final String? speakerTitle;
  final String? speakerChurch;
  final String? caption;

  const LiveStreamOverlay({
    required this.streamId,
    this.verseText,
    this.verseRef,
    this.tickerMessage,
    this.tickerSpeed = 40,
    this.tickerEnabled = true,
    this.logoUrl,
    this.speakerName,
    this.speakerTitle,
    this.speakerChurch,
    this.caption,
  });

  bool get hasVerse =>
      (verseText != null && verseText!.trim().isNotEmpty) ||
      (verseRef != null && verseRef!.trim().isNotEmpty);

  bool get hasSpeaker =>
      (speakerName != null && speakerName!.trim().isNotEmpty) ||
      (speakerTitle != null && speakerTitle!.trim().isNotEmpty) ||
      (speakerChurch != null && speakerChurch!.trim().isNotEmpty);

  bool get hasCaption =>
      caption != null && caption!.trim().isNotEmpty;

  factory LiveStreamOverlay.fromMap(Map<String, dynamic> map) {
    return LiveStreamOverlay(
      streamId: map['stream_id']?.toString() ?? '',
      verseText: map['verse_text']?.toString(),
      verseRef: map['verse_ref']?.toString(),
      tickerMessage: map['ticker_message']?.toString(),
      tickerSpeed: (map['ticker_speed'] as num?)?.toInt() ?? 40,
      tickerEnabled: map['ticker_enabled'] as bool? ?? true,
      logoUrl: map['logo_url']?.toString(),
      speakerName: map['speaker_name']?.toString(),
      speakerTitle: map['speaker_title']?.toString(),
      speakerChurch: map['speaker_church']?.toString(),
      caption: map['caption']?.toString(),
    );
  }
}

class LiveStreamOverlayService {
  final SupabaseClient _client;
  LiveStreamOverlayService(this._client);

  /// Realtime overlay for a stream. Emits `null` when no overlay row exists yet.
  Stream<LiveStreamOverlay?> watchOverlay(String streamId) {
    return _client
        .from('live_stream_overlays')
        .stream(primaryKey: ['stream_id'])
        .eq('stream_id', streamId)
        .map((rows) {
      if (rows.isEmpty) return null;
      return LiveStreamOverlay.fromMap(Map<String, dynamic>.from(rows.first));
    });
  }

  Future<LiveStreamOverlay?> fetchOverlay(String streamId) async {
    try {
      final row = await _client
          .from('live_stream_overlays')
          .select()
          .eq('stream_id', streamId)
          .maybeSingle();
      if (row == null) return null;
      return LiveStreamOverlay.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  /// Publish the verse and/or ticker. Omitted fields are left untouched.
  Future<void> publishOverlay({
    required String streamId,
    required String? tenantId,
    String? verseText,
    String? verseRef,
    String? tickerMessage,
    int? tickerSpeed,
    bool? tickerEnabled,
    String? logoUrl,
    String? speakerName,
    String? speakerTitle,
    String? speakerChurch,
    String? caption,
    bool clearVerse = false,
    bool clearSpeaker = false,
    bool clearCaption = false,
  }) async {
    final payload = <String, dynamic>{
      'stream_id': streamId,
      'tenant_id': tenantId,
      'updated_by': _client.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      if (clearVerse) 'verse_text': null,
      if (clearVerse) 'verse_ref': null,
      if (verseText != null) 'verse_text': verseText,
      if (verseRef != null) 'verse_ref': verseRef,
      if (tickerMessage != null) 'ticker_message': tickerMessage,
      if (tickerSpeed != null) 'ticker_speed': tickerSpeed,
      if (tickerEnabled != null) 'ticker_enabled': tickerEnabled,
      if (logoUrl != null) 'logo_url': logoUrl,
      if (clearSpeaker) 'speaker_name': null,
      if (clearSpeaker) 'speaker_title': null,
      if (clearSpeaker) 'speaker_church': null,
      if (speakerName != null) 'speaker_name': speakerName,
      if (speakerTitle != null) 'speaker_title': speakerTitle,
      if (speakerChurch != null) 'speaker_church': speakerChurch,
      if (clearCaption) 'caption': null,
      if (caption != null) 'caption': caption,
    };

    await _client.from('live_stream_overlays').upsert(
          payload,
          onConflict: 'stream_id',
        );
  }
}

final liveStreamOverlayServiceProvider = Provider<LiveStreamOverlayService>((ref) {
  return LiveStreamOverlayService(ref.watch(supabaseServiceProvider).client);
});

/// Realtime overlay for a single stream id (value-equal String key → safe family).
final liveStreamOverlayProvider =
    StreamProvider.family<LiveStreamOverlay?, String>((ref, streamId) {
  return ref.watch(liveStreamOverlayServiceProvider).watchOverlay(streamId);
});
