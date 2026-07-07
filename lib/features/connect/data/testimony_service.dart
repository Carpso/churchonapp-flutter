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
      userPhoto: map['user_photo'] ?? "https://i.pravatar.cc/100?u=${map['user_id']}",
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
        .order('created_at', ascending: false)
        .map((data) => data.map((map) => Testimony.fromMap(map)).toList());
  }

  Future<void> submitTestimony(String content, String? imageUrl) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Try to insert using new columns
      await _client.from('testimonies').insert({
        'user_id': user.id,
        'user_name': user.userMetadata?['full_name'] ?? 'Believer',
        'user_photo': user.userMetadata?['avatar_url'],
        'content': content,
        'image_url': imageUrl,
        'praise_count': 0,
        'praised_by': [],
      });
    } catch (e) {
      debugPrint('Insert testimony using new columns failed, falling back: $e');
      // 2. Fallback: try to insert using baseline columns
      await _client.from('testimonies').insert({
        'user_id': user.id,
        'user_name': user.userMetadata?['full_name'] ?? 'Believer',
        'content': content,
        'category': 'General',
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

