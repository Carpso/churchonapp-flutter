import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime createdAt;
  final bool isMe;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.createdAt,
    required this.isMe,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map, String currentUserId) {
    return ChatMessage(
      id: map['id']?.toString() ?? '',
      senderId: map['user_id'] ?? '',
      senderName: map['user_name'] ?? 'Member',
      content: map['message'] ?? '',
      createdAt: DateTime.parse(map['created_at']),
      isMe: map['user_id'] == currentUserId,
    );
  }
}

class ChatService {
  final SupabaseClient _client;
  ChatService(this._client);

  Stream<List<ChatMessage>> getMessagesStream(String channelId) {
    final currentUserId = _client.auth.currentUser?.id ?? '';
    
    return _client
        .from('stream_chats')
        .stream(primaryKey: ['id'])
        .eq('stream_id', channelId)
        .order('created_at')
        .map((data) => data.map((map) => ChatMessage.fromMap(map, currentUserId)).toList());
  }

  Future<void> sendMessage(String channelId, String message) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('stream_chats').insert({
      'stream_id': channelId,
      'user_id': user.id,
      'user_name': user.userMetadata?['name'] ?? 'Member',
      'message': message,
    });
  }
}

final chatServiceProvider = Provider((ref) => ChatService(Supabase.instance.client));

final chatMessagesProvider = StreamProvider.family<List<ChatMessage>, String>((ref, channelId) {
  return ref.watch(chatServiceProvider).getMessagesStream(channelId);
});
