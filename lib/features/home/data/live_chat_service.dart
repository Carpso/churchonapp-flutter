import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class LiveChatMessage {
  final String id;
  final String text;
  final String senderId;
  final String senderName;
  final String? senderPhoto;
  final DateTime createdAt;
  final bool isMe;

  LiveChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    this.senderPhoto,
    required this.createdAt,
    required this.isMe,
  });

  factory LiveChatMessage.fromMap(Map<String, dynamic> map, String currentUserId) {
    return LiveChatMessage(
      id: map['id']?.toString() ?? '',
      text: map['content'] ?? '',
      senderId: map['user_id'] ?? '',
      senderName: map['user_name'] ?? 'Believer',
      senderPhoto: map['user_photo'],
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
      isMe: map['user_id'] == currentUserId,
    );
  }
}

class LiveChatService {
  final SupabaseClient _client;

  LiveChatService(this._client);

  Stream<List<LiveChatMessage>> streamLiveMessages(String tenantId) {
    final currentUserId = _client.auth.currentUser?.id ?? '';

    return _client
        .from('live_chat_messages')
        .stream(primaryKey: ['id'])
        .eq('tenant_id', tenantId)
        .limit(50)
        .map((data) => data
            .map((map) => LiveChatMessage.fromMap(map, currentUserId))
            .toList()
            .reversed
            .toList());
  }

  Future<void> sendLiveMessage({
    required String tenantId,
    required String content,
    required String userName,
    String? userPhoto,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('live_chat_messages').insert({
      'tenant_id': tenantId,
      'user_id': user.id,
      'user_name': userName,
      'user_photo': userPhoto,
      'content': content,
    });
  }
}

final liveChatServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return LiveChatService(client);
});

final liveChatStreamProvider = StreamProvider.family<List<LiveChatMessage>, String>((ref, tenantId) {
  return ref.watch(liveChatServiceProvider).streamLiveMessages(tenantId);
});

