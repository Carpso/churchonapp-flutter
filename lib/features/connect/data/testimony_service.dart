import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Testimony {
  final String id;
  final String userId;
  final String userName;
  final String? userPhoto;
  final String content;
  final String? imageUrl;
  final int praiseCount;
  final List<String> praisedBy;
  final DateTime createdAt;

  Testimony({
    required this.id,
    required this.userId,
    required this.userName,
    this.userPhoto,
    required this.content,
    this.imageUrl,
    required this.praiseCount,
    required this.praisedBy,
    required this.createdAt,
  });

  factory Testimony.fromMap(Map<String, dynamic> map) {
    return Testimony(
      id: map['id']?.toString() ?? '',
      userId: map['user_id'] ?? '',
      userName: map['user_name'] ?? 'Believer',
      userPhoto: map['user_photo'],
      content: map['content'] ?? '',
      imageUrl: map['image_url'],
      praiseCount: map['praise_count'] ?? map['likes'] ?? 0,
      praisedBy: map['praised_by'] != null 
          ? List<String>.from(map['praised_by']) 
          : <String>[],
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
    );
  }
}

class TestimonyService {
  final SupabaseClient _client;
  TestimonyService(this._client);

  // Session-based deduplication fallback for older database schema
  final Set<String> _localPraisedTestimonies = {};

  Stream<List<Testimony>> getTestimoniesStream() {
    return _client
        .from('testimonies')
        .stream(primaryKey: ['id'])
        .asyncMap((data) async {
          // Enrich with live profile avatar when snapshot missing — profile
          // photo first, then email/Google photo fallback (matches prayer wall).
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
            final prof = profiles[map['user_id']?.toString() ?? ''];
            if ((enriched['user_photo'] == null || (enriched['user_photo'] as String).isEmpty) && prof != null) {
              final pa = prof['avatar_url']?.toString();
              if (pa != null && pa.isNotEmpty) enriched['user_photo'] = pa;
            }
            if ((enriched['user_name'] == null || (enriched['user_name'] as String).isEmpty || enriched['user_name'] == 'Believer') &&
                prof != null) {
              final pn = prof['full_name']?.toString().trim();
              if (pn != null && pn.isNotEmpty) enriched['user_name'] = pn;
            }
            return Testimony.fromMap(enriched);
          }).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
  }

  Future<void> submitTestimony(String content, String? imageUrl) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    // Profile photo first, then email/Google photo (avatar_url → picture).
    String resolvedName;
    String? resolvedAvatar;
    String? tenantId;
    try {
      final prof = await _client
          .from('profiles')
          .select('full_name, avatar_url, tenant_id')
          .eq('id', user.id)
          .maybeSingle();
      resolvedName = prof?['full_name']?.toString().trim() ?? '';
      final pa = prof?['avatar_url']?.toString().trim();
      if (pa != null && pa.isNotEmpty) resolvedAvatar = pa;
      tenantId = prof?['tenant_id']?.toString();
    } catch (_) {
      resolvedName = '';
    }
    if (resolvedName.isEmpty) {
      resolvedName = (user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? 'Believer').toString();
    }
    resolvedAvatar ??= (user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'] ?? user.userMetadata?['avatar'])?.toString();

    try {
      // 1. Try to insert using new columns
      await _client.from('testimonies').insert({
        'user_id': user.id,
        'user_name': resolvedName,
        'user_photo': resolvedAvatar,
        'content': content,
        'image_url': imageUrl,
        'tenant_id': tenantId,
        'praise_count': 0,
        'praised_by': [],
      });
    } catch (e) {
      debugPrint('Insert testimony using new columns failed, falling back: $e');
      // 2. Fallback: try to insert using baseline columns
      await _client.from('testimonies').insert({
        'user_id': user.id,
        'user_name': resolvedName,
        'content': content,
        'category': 'General',
        'tenant_id': tenantId,
        'likes': 0,
      });
    }
  }

  Future<void> praiseTestimony(String testimonyId, List<String> currentPraises) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    if (currentPraises.contains(user.id) || _localPraisedTestimonies.contains(testimonyId)) {
      return;
    }

    _localPraisedTestimonies.add(testimonyId);

    try {
      // 1. Try to update using new columns
      await _client.from('testimonies').update({
        'praise_count': currentPraises.length + 1,
        'praised_by': [...currentPraises, user.id],
      }).eq('id', testimonyId);
    } catch (e) {
      debugPrint('Praising testimony using new columns failed, falling back to likes: $e');
      // 2. Fallback: update likes column
      try {
        final record = await _client.from('testimonies').select('likes').eq('id', testimonyId).single();
        final currentLikes = (record['likes'] as int?) ?? 0;
        await _client.from('testimonies').update({
          'likes': currentLikes + 1,
        }).eq('id', testimonyId);
      } catch (err) {
        debugPrint('Fallback to likes failed: $err');
      }
    }
  }
}

final testimonyServiceProvider = Provider((ref) => TestimonyService(Supabase.instance.client));

final testimonyStreamProvider = StreamProvider<List<Testimony>>((ref) {
  return ref.watch(testimonyServiceProvider).getTestimoniesStream();
});

