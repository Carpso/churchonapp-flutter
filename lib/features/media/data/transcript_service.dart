import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A timed transcript cue parsed from `media_transcripts.segments`.
class TranscriptSegment {
  final Duration start;
  final Duration end;
  final String text;

  const TranscriptSegment({
    required this.start,
    required this.end,
    required this.text,
  });

  factory TranscriptSegment.fromMap(Map<String, dynamic> map) {
    final start = (map['start'] as num?)?.toDouble() ?? 0;
    final end = (map['end'] as num?)?.toDouble() ?? start;
    return TranscriptSegment(
      start: Duration(milliseconds: (start * 1000).round()),
      end: Duration(milliseconds: (end * 1000).round()),
      text: (map['text'] ?? '').toString(),
    );
  }
}

/// A Bible reference detected inside the transcript.
class TranscriptVerseMarker {
  final String reference;
  final String book;
  final int chapter;
  final int verse;
  final int? verseEnd;
  final Duration? start;
  final Duration? end;
  final String raw;

  const TranscriptVerseMarker({
    required this.reference,
    required this.book,
    required this.chapter,
    required this.verse,
    this.verseEnd,
    this.start,
    this.end,
    this.raw = '',
  });

  factory TranscriptVerseMarker.fromMap(Map<String, dynamic> map) {
    final startSec = (map['start_seconds'] as num?)?.toDouble();
    final endSec = (map['end_seconds'] as num?)?.toDouble();
    return TranscriptVerseMarker(
      reference: (map['reference'] ?? '').toString(),
      book: (map['book'] ?? '').toString(),
      chapter: (map['chapter'] as num?)?.toInt() ?? 0,
      verse: (map['verse'] as num?)?.toInt() ?? 0,
      verseEnd: (map['verse_end'] as num?)?.toInt(),
      start: startSec == null ? null : Duration(milliseconds: (startSec * 1000).round()),
      end: endSec == null ? null : Duration(milliseconds: (endSec * 1000).round()),
      raw: (map['raw'] ?? '').toString(),
    );
  }
}

/// One Whisper transcript row (`media_transcripts`).
class MediaTranscript {
  final String id;
  final String? tenantId;
  final String? sermonId;
  final String? liveStreamId;
  final String sourceUrl;
  final String? language;
  final String status; // pending | processing | ready | failed
  final String? error;
  final String transcript;
  final String vtt;
  final List<TranscriptSegment> segments;
  final List<TranscriptVerseMarker> verseMarkers;
  final double? durationSeconds;
  final int wordCount;
  final String? model;
  final int chunkIndex;
  final int chunkTotal;

  const MediaTranscript({
    required this.id,
    this.tenantId,
    this.sermonId,
    this.liveStreamId,
    this.sourceUrl = '',
    this.language,
    this.status = 'pending',
    this.error,
    this.transcript = '',
    this.vtt = '',
    this.segments = const [],
    this.verseMarkers = const [],
    this.durationSeconds,
    this.wordCount = 0,
    this.model,
    this.chunkIndex = 0,
    this.chunkTotal = 1,
  });

  bool get isReady => status == 'ready';
  bool get isWorking => status == 'pending' || status == 'processing';
  bool get isFailed => status == 'failed';

  factory MediaTranscript.fromMap(Map<String, dynamic> map) {
    return MediaTranscript(
      id: (map['id'] ?? '').toString(),
      tenantId: map['tenant_id']?.toString(),
      sermonId: map['sermon_id']?.toString(),
      liveStreamId: map['live_stream_id']?.toString(),
      sourceUrl: (map['source_url'] ?? '').toString(),
      language: map['language']?.toString(),
      status: (map['status'] ?? 'pending').toString(),
      error: map['error']?.toString(),
      transcript: (map['transcript'] ?? '').toString(),
      vtt: (map['vtt'] ?? '').toString(),
      segments: _listOfMaps(map['segments'])
          .map(TranscriptSegment.fromMap)
          .toList(),
      verseMarkers: _listOfMaps(map['verse_markers'])
          .map(TranscriptVerseMarker.fromMap)
          .toList(),
      durationSeconds: (map['duration_seconds'] as num?)?.toDouble(),
      wordCount: (map['word_count'] as num?)?.toInt() ?? 0,
      model: map['model']?.toString(),
      chunkIndex: (map['chunk_index'] as num?)?.toInt() ?? 0,
      chunkTotal: (map['chunk_total'] as num?)?.toInt() ?? 1,
    );
  }

  static List<Map<String, dynamic>> _listOfMaps(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  /// The cue that should be on screen at [position], or null.
  TranscriptSegment? segmentAt(Duration position) {
    for (final s in segments) {
      if (position >= s.start && position <= s.end) return s;
    }
    return null;
  }

  /// A transcript search hit for a sermon / recording.
  static MediaTranscriptSearchHit hitFromMap(Map<String, dynamic> map) =>
      MediaTranscriptSearchHit.fromMap(map);
}

class MediaTranscriptSearchHit {
  final String id;
  final String? sermonId;
  final String? liveStreamId;
  final String title;
  final String preacher;
  final String snippet;
  final String streamUrl;
  final Duration start;

  const MediaTranscriptSearchHit({
    required this.id,
    this.sermonId,
    this.liveStreamId,
    required this.title,
    required this.preacher,
    required this.snippet,
    required this.streamUrl,
    required this.start,
  });

  factory MediaTranscriptSearchHit.fromMap(Map<String, dynamic> map) {
    final sec = (map['start_seconds'] as num?)?.toDouble() ?? 0;
    return MediaTranscriptSearchHit(
      id: (map['id'] ?? '').toString(),
      sermonId: map['sermon_id']?.toString(),
      liveStreamId: map['live_stream_id']?.toString(),
      title: (map['title'] ?? 'Recording').toString(),
      preacher: (map['preacher'] ?? '').toString(),
      snippet: (map['snippet'] ?? '').toString(),
      streamUrl: (map['stream_url'] ?? '').toString(),
      start: Duration(milliseconds: (sec * 1000).round()),
    );
  }
}

class TranscriptService {
  final SupabaseClient _client;
  TranscriptService(this._client);

  static const _select =
      'id,tenant_id,sermon_id,live_stream_id,source_url,language,status,error,'
      'transcript,vtt,segments,verse_markers,duration_seconds,word_count,model,'
      'chunk_index,chunk_total,created_at,updated_at';

  Future<MediaTranscript?> fetchForSermon(String sermonId) async {
    try {
      final row = await _client
          .from('media_transcripts')
          .select(_select)
          .eq('sermon_id', sermonId)
          .maybeSingle();
      return row == null ? null : MediaTranscript.fromMap(row);
    } catch (e) {
      debugPrint('fetchForSermon transcript failed: $e');
      return null;
    }
  }

  Future<MediaTranscript?> fetchForLiveStream(String liveStreamId) async {
    try {
      final row = await _client
          .from('media_transcripts')
          .select(_select)
          .eq('live_stream_id', liveStreamId)
          .maybeSingle();
      return row == null ? null : MediaTranscript.fromMap(row);
    } catch (e) {
      debugPrint('fetchForLiveStream transcript failed: $e');
      return null;
    }
  }

  /// Enqueues a transcript (idempotent server-side) then kicks the Edge Function
  /// so processing starts immediately. Returns the freshest known row.
  Future<MediaTranscript?> requestTranscription({
    String? sermonId,
    String? liveStreamId,
    bool force = false,
  }) async {
    final queued = await _client.rpc('request_transcription', params: {
      'p_sermon_id': sermonId,
      'p_live_stream_id': liveStreamId,
    });
    Map<String, dynamic>? row;
    if (queued is Map) {
      final t = queued['transcript'];
      if (t is Map) row = t.cast<String, dynamic>();
    }

    try {
      await _client.functions.invoke('transcribe-media', body: {
        'sermonId': sermonId,
        'liveStreamId': liveStreamId,
        'force': force,
      });
    } catch (e) {
      // The row is already queued; a sweep will finish it if the invoke fails.
      debugPrint('transcribe-media invoke failed (queued for sweep): $e');
    }
    return row == null ? null : MediaTranscript.fromMap(row);
  }

  Future<List<MediaTranscriptSearchHit>> searchTranscripts(String query) async {
    try {
      final res = await _client.rpc('search_transcripts', params: {
        'p_query': query,
        'p_limit': 20,
      });
      if (res is! List) return const [];
      return res
          .whereType<Map>()
          .map((e) => MediaTranscriptSearchHit.fromMap(e.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      debugPrint('searchTranscripts failed: $e');
      return const [];
    }
  }

  /// Builds a `.vtt` file body (server writes one, this is the offline fallback).
  String buildVtt(MediaTranscript transcript) {
    if (transcript.vtt.trim().isNotEmpty) return transcript.vtt;
    final buf = StringBuffer('WEBVTT\n\n');
    for (final s in transcript.segments) {
      buf.writeln('${_vttTime(s.start)} --> ${_vttTime(s.end)}');
      buf.writeln(s.text);
      buf.writeln();
    }
    return buf.toString();
  }

  static String _vttTime(Duration d) {
    String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
    return '${p(d.inHours)}:${p(d.inMinutes % 60)}:${p(d.inSeconds % 60)}.${p(d.inMilliseconds % 1000, 3)}';
  }
}

final transcriptServiceProvider =
    Provider<TranscriptService>((ref) => TranscriptService(Supabase.instance.client));

/// Transcript for a sermon (null until one is requested).
final sermonTranscriptProvider =
    FutureProvider.autoDispose.family<MediaTranscript?, String>((ref, sermonId) {
  return ref.watch(transcriptServiceProvider).fetchForSermon(sermonId);
});

/// Transcript for a live-stream recording.
final liveStreamTranscriptProvider =
    FutureProvider.autoDispose.family<MediaTranscript?, String>((ref, liveStreamId) {
  return ref.watch(transcriptServiceProvider).fetchForLiveStream(liveStreamId);
});

/// Persisted subtitles/captions on/off preference.
class CaptionsNotifier extends Notifier<bool> {
  static const _key = 'player_captions_enabled';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(_key);
      if (value != null && value != state) state = value;
    } catch (e) {
      debugPrint('captions load failed: $e');
    }
  }

  Future<void> toggle() async {
    state = !state;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, state);
    } catch (e) {
      debugPrint('captions persist failed: $e');
    }
  }
}

final captionsEnabledProvider =
    NotifierProvider<CaptionsNotifier, bool>(CaptionsNotifier.new);
