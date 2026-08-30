import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PrayerRequest {
  final String id;
  final String userId;
  final String userName;
  final String? userPhoto;
  final String content;
  final String category;
  final String visibility;
  final int prayerCount;
  final List<String> prayedBy;
  final bool isAnonymous;
  final String? aiEncouragement;
  final DateTime createdAt;

  PrayerRequest({
    required this.id,
    required this.userId,
    required this.userName,
    this.userPhoto,
    required this.content,
    required this.category,
    required this.visibility,
    required this.prayerCount,
    required this.prayedBy,
    required this.isAnonymous,
    this.aiEncouragement,
    required this.createdAt,
  });

  factory PrayerRequest.fromMap(Map<String, dynamic> map) {
    return PrayerRequest(
      id: map['id']?.toString() ?? '',
      userId: map['user_id'] ?? '',
      userName: map['user_name'] ?? 'Believer',
      userPhoto: map['user_photo'],
      content: map['content'] ?? '',
      category: map['category'] ?? 'other',
      visibility: map['visibility'] ?? 'public',
      prayerCount: map['prayer_count'] ?? 0,
      prayedBy: List<String>.from(map['prayed_by'] ?? []),
      isAnonymous: map['is_anonymous'] ?? false,
      aiEncouragement: map['ai_encouragement'],
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class PrayerService {
  final SupabaseClient _client;
  PrayerService(this._client);

  Stream<List<PrayerRequest>> getPrayerStream() {
    return _client
        .from('prayers')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .asyncMap((data) async {
          // Enrich with live profile avatar if snapshot missing — ensures email/Google photo fallback even for old prayers
          final userIds = data.map((m) => m['user_id']?.toString()).whereType<String>().toSet().toList();
          Map<String, Map<String, dynamic>> profiles = {};
          if (userIds.isNotEmpty) {
            try {
              final res = await _client.from('profiles').select('id, full_name, avatar_url').inFilter('id', userIds);
              for (final row in (res as List)) {
                profiles[row['id']?.toString() ?? ''] = Map<String, dynamic>.from(row);
              }
            } catch (_) {}
          }
          return data.map((map) {
            final enriched = Map<String, dynamic>.from(map);
            final uid = map['user_id']?.toString() ?? '';
            final prof = profiles[uid];
            // Only fallback if snapshot photo is empty — preserve anonymous and manual overrides
            if ((enriched['user_photo'] == null || (enriched['user_photo'] as String).isEmpty) && prof != null) {
              final pa = prof['avatar_url']?.toString();
              if (pa != null && pa.isNotEmpty) enriched['user_photo'] = pa;
            }
            if ((enriched['user_name'] == null || (enriched['user_name'] as String).isEmpty || enriched['user_name'] == 'Believer') &&
                prof != null) {
              final pn = prof['full_name']?.toString().trim();
              if (pn != null && pn.isNotEmpty) enriched['user_name'] = pn;
            }
            return PrayerRequest.fromMap(enriched);
          }).toList();
        });
  }

  Future<void> submitPrayer(String content, String category, String visibility, bool isAnonymous) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final aiEncouragements = [
      "God hears every prayer. He is working in ways you cannot see yet.",
      "Be still and know that He is God. Your faith moves mountains.",
      "Cast your anxieties on Him, for He cares for you deeply.",
    ];

    // Prefer profile avatar/name first, then email/Google photo (picture/avatar_url)
    String? resolvedName;
    String? resolvedAvatar;
    try {
      final prof = await _client.from('profiles').select('full_name, avatar_url').eq('id', user.id).maybeSingle();
      resolvedName = prof?['full_name']?.toString().trim();
      final pa = prof?['avatar_url']?.toString().trim();
      if (pa != null && pa.isNotEmpty) resolvedAvatar = pa;
    } catch (_) {}
    resolvedName ??= (user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? 'Believer').toString();
    resolvedAvatar ??= (user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'] ?? user.userMetadata?['avatar'])?.toString();

    await _client.from('prayers').insert({
      'user_id': user.id,
      'user_name': isAnonymous ? 'Anonymous' : resolvedName,
      'user_photo': isAnonymous ? null : resolvedAvatar,
      'content': content,
      'category': category,
      'visibility': visibility,
      'is_anonymous': isAnonymous,
      'prayer_count': 1,
      'prayed_by': [user.id],
      'ai_encouragement': aiEncouragements[DateTime.now().millisecond % aiEncouragements.length],
    });
  }

  // Session-based deduplication
  final Set<String> _localIntercededPrayers = {};

  Future<void> prayForRequest(String prayerId, List<String> currentPrayers) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    if (currentPraisesContains(currentPrayers, user.id) || _localIntercededPrayers.contains(prayerId)) return;

    _localIntercededPrayers.add(prayerId);

    try {
      await _client.from('prayers').update({
        'prayer_count': currentPrayers.length + 1,
        'prayed_by': [...currentPrayers, user.id],
      }).eq('id', prayerId);
    } catch (e) {
      debugPrint('Error interceding for prayer request: $e');
    }
  }

  bool currentPraisesContains(List<String> list, String value) {
    return list.contains(value);
  }
}

final prayerServiceProvider = Provider((ref) => PrayerService(Supabase.instance.client));

final prayerStreamProvider = StreamProvider<List<PrayerRequest>>((ref) {
  return ref.watch(prayerServiceProvider).getPrayerStream();
});

