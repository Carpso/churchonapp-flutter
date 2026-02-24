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
      praiseCount: map['praise_count'] ?? 0,
      praisedBy: List<String>.from(map['praised_by'] ?? []),
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class TestimonyService {
  final SupabaseClient _client;
  TestimonyService(this._client);

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

    await _client.from('testimonies').insert({
      'user_id': user.id,
      'user_name': user.userMetadata?['full_name'] ?? 'Believer',
      'user_photo': user.userMetadata?['avatar_url'],
      'content': content,
      'image_url': imageUrl,
      'praise_count': 0,
      'praised_by': [],
    });
  }

  Future<void> praiseTestimony(String testimonyId, List<String> currentPraises) async {
    final user = _client.auth.currentUser;
    if (user == null || currentPraises.contains(user.id)) return;

    await _client.from('testimonies').update({
      'praise_count': currentPraises.length + 1,
      'praised_by': [...currentPraises, user.id],
    }).eq('id', testimonyId);
  }
}

final testimonyServiceProvider = Provider((ref) => TestimonyService(Supabase.instance.client));

final testimonyStreamProvider = StreamProvider<List<Testimony>>((ref) {
  return ref.watch(testimonyServiceProvider).getTestimoniesStream();
});
