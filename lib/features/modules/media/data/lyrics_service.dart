import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class WorshipLyric {
  final String id;
  final String title;
  final String artist;
  final String lyrics;
  final String? chords;
  final String category; // 'praise', 'worship', 'hymn', 'gospel', 'contemporary'
  final String? key; // Musical key: C, D, E, etc.
  final int? bpm;
  final String? tenantId;
  final String? createdBy;
  final DateTime createdAt;
  final bool isGlobal;

  WorshipLyric({
    required this.id,
    required this.title,
    required this.artist,
    required this.lyrics,
    this.chords,
    required this.category,
    this.key,
    this.bpm,
    this.tenantId,
    this.createdBy,
    required this.createdAt,
    this.isGlobal = false,
  });

  factory WorshipLyric.fromMap(Map<String, dynamic> map) {
    return WorshipLyric(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? '',
      artist: map['artist'] ?? 'Unknown',
      lyrics: map['lyrics'] ?? '',
      chords: map['chords'],
      category: map['category'] ?? 'worship',
      key: map['musical_key'],
      bpm: map['bpm'] as int?,
      tenantId: map['tenant_id'],
      createdBy: map['created_by'],
      createdAt: DateTime.parse(
          map['created_at'] ?? DateTime.now().toIso8601String()),
      isGlobal: map['is_global'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'artist': artist,
        'lyrics': lyrics,
        'chords': chords,
        'category': category,
        'musical_key': key,
        'bpm': bpm,
        'tenant_id': tenantId,
        'created_by': createdBy,
        'is_global': isGlobal,
      };
}

class Setlist {
  final String id;
  final String title;
  final String? serviceDate;
  final String tenantId;
  final List<String> songIds;
  final String? createdBy;
  final DateTime createdAt;

  Setlist({
    required this.id,
    required this.title,
    this.serviceDate,
    required this.tenantId,
    required this.songIds,
    this.createdBy,
    required this.createdAt,
  });

  factory Setlist.fromMap(Map<String, dynamic> map) {
    final ids = map['song_ids'];
    List<String> songList = [];
    if (ids is List) {
      songList = ids.map((e) => e.toString()).toList();
    }
    return Setlist(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? '',
      serviceDate: map['service_date'],
      tenantId: map['tenant_id'] ?? '',
      songIds: songList,
      createdBy: map['created_by'],
      createdAt: DateTime.parse(
          map['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class LyricsService {
  final SupabaseClient _client;
  final Ref _ref;

  LyricsService(this._client, this._ref);

  /// Get all lyrics: global + tenant-specific.
  Stream<List<WorshipLyric>> getLyricsStream({String? category}) {
    final tenant = _ref.watch(currentTenantProvider);
    // Fetch all lyrics where is_global = true OR tenant_id matches
    var query = _client.from('worship_lyrics').stream(primaryKey: ['id']);

    // Stream API doesn't support OR filters, so we fetch all and filter client-side
    return query.order('title', ascending: true).map((data) {
      return data
          .where((map) {
            final isGlobal = map['is_global'] == true;
            final matchesTenant =
                tenant != null && map['tenant_id'] == tenant.id;
            final matchesCategory =
                category == null || map['category'] == category;
            return (isGlobal || matchesTenant) && matchesCategory;
          })
          .map((map) => WorshipLyric.fromMap(map))
          .toList();
    });
  }

  /// Search lyrics by title or artist.
  Future<List<WorshipLyric>> searchLyrics(String query) async {
    final tenant = _ref.read(currentTenantProvider);
    final results = await _client
        .from('worship_lyrics')
        .select()
        .or('title.ilike.%$query%,artist.ilike.%$query%')
        .order('title', ascending: true)
        .limit(50);

    return (results as List)
        .where((map) {
          final isGlobal = map['is_global'] == true;
          final matchesTenant =
              tenant != null && map['tenant_id'] == tenant.id;
          return isGlobal || matchesTenant;
        })
        .map((map) => WorshipLyric.fromMap(map))
        .toList();
  }

  /// Get a single lyric by ID.
  Future<WorshipLyric?> getLyricById(String id) async {
    final data = await _client
        .from('worship_lyrics')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return WorshipLyric.fromMap(data);
  }

  /// Create a new lyric.
  Future<WorshipLyric> createLyric(WorshipLyric lyric) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final tenant = _ref.read(currentTenantProvider);

    final data = await _client.from('worship_lyrics').insert({
      ...lyric.toMap(),
      'tenant_id': lyric.tenantId ?? tenant?.id,
      'created_by': user.id,
    }).select().single();

    return WorshipLyric.fromMap(data);
  }

  /// Request or toggle permission to air song globally across all churches.
  Future<void> setGlobalAirPermission(String lyricId, bool isGlobal) async {
    await _client
        .from('worship_lyrics')
        .update({'is_global': isGlobal})
        .eq('id', lyricId);
  }

  /// Update an existing lyric.
  Future<void> updateLyric(String id, Map<String, dynamic> updates) async {
    await _client.from('worship_lyrics').update(updates).eq('id', id);
  }

  /// Delete a lyric.
  Future<void> deleteLyric(String id) async {
    await _client.from('worship_lyrics').delete().eq('id', id);
  }

  // ── Setlist Operations ─────────────────────────────

  /// Get all setlists for the current tenant.
  Stream<List<Setlist>> getSetlistsStream() {
    final tenant = _ref.watch(currentTenantProvider);
    if (tenant == null) return Stream.value([]);

    return _client
        .from('worship_setlists')
        .stream(primaryKey: ['id'])
        .eq('tenant_id', tenant.id)
        .order('created_at', ascending: false)
        .map((data) => data.map((map) => Setlist.fromMap(map)).toList());
  }

  /// Create a new setlist.
  Future<Setlist> createSetlist({
    required String title,
    required List<String> songIds,
    String? serviceDate,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final tenant = _ref.read(currentTenantProvider);
    if (tenant == null) throw Exception('No church selected');

    final data = await _client.from('worship_setlists').insert({
      'title': title,
      'song_ids': songIds,
      'service_date': serviceDate,
      'tenant_id': tenant.id,
      'created_by': user.id,
    }).select().single();

    return Setlist.fromMap(data);
  }

  /// Update setlist song order.
  Future<void> updateSetlistSongs(
      String setlistId, List<String> songIds) async {
    await _client
        .from('worship_setlists')
        .update({'song_ids': songIds})
        .eq('id', setlistId);
  }

  /// Delete a setlist.
  Future<void> deleteSetlist(String id) async {
    await _client.from('worship_setlists').delete().eq('id', id);
  }
}

// ── Providers ──────────────────────────────────────────

final lyricsServiceProvider = Provider(
  (ref) => LyricsService(Supabase.instance.client, ref),
);

final lyricsStreamProvider = StreamProvider<List<WorshipLyric>>(
  (ref) => ref.watch(lyricsServiceProvider).getLyricsStream(),
);

final lyricsByCategoryProvider =
    StreamProvider.family<List<WorshipLyric>, String>(
  (ref, category) =>
      ref.watch(lyricsServiceProvider).getLyricsStream(category: category),
);

final setlistsStreamProvider = StreamProvider<List<Setlist>>(
  (ref) => ref.watch(lyricsServiceProvider).getSetlistsStream(),
);

final lyricsSearchProvider =
    FutureProvider.family<List<WorshipLyric>, String>(
  (ref, query) => ref.watch(lyricsServiceProvider).searchLyrics(query),
);
