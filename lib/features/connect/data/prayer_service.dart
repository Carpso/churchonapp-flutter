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
        .map((data) => data.map((map) => PrayerRequest.fromMap(map)).toList());
  }

  Future<void> submitPrayer(String content, String category, String visibility, bool isAnonymous) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final aiEncouragements = [
      "God hears every prayer. He is working in ways you cannot see yet.",
      "Be still and know that He is God. Your faith moves mountains.",
      "Cast your anxieties on Him, for He cares for you deeply.",
    ];

    await _client.from('prayers').insert({
      'user_id': user.id,
      'user_name': isAnonymous ? 'Anonymous' : (user.userMetadata?['name'] ?? 'Believer'),
      'user_photo': isAnonymous ? null : user.userMetadata?['avatar_url'],
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

