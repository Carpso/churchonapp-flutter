import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

class ChatMessage {
  final String id;
  final String text;
  final String senderId;
  final DateTime createdAt;
  final bool isMe;

  final String? mediaUrl;
  final String? mediaType;
  final String? stickerId;
  final String? fileName;

  ChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.createdAt,
    required this.isMe,
    this.mediaUrl,
    this.mediaType = 'text',
    this.stickerId,
    this.fileName,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map, String currentUserId) {
    return ChatMessage(
      id: map['id'],
      text: map['content'] ?? '',
      senderId: map['sender_id'] ?? '',
      createdAt: DateTime.parse(map['created_at']),
      isMe: map['sender_id'] == currentUserId,
      mediaUrl: map['media_url'],
      mediaType: map['media_type'] ?? 'text',
      stickerId: map['sticker_id'],
      fileName: map['file_name'],
    );
  }
}

class ChatService {
  final SupabaseClient _client;

  ChatService(this._client);

  Stream<List<ChatMessage>> streamMessages(String otherUserId) {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return Stream.value([]);

    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => data
            .where((map) => 
                (map['sender_id'] == currentUserId && map['receiver_id'] == otherUserId) ||
                (map['sender_id'] == otherUserId && map['receiver_id'] == currentUserId)
            )
            .map((map) => ChatMessage.fromMap(map, currentUserId))
            .toList());
  }

  Stream<List<ChatMessage>> streamGroupMessages(String groupId) {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return Stream.value([]);

    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .order('created_at', ascending: false)
        .map((data) => data
            .map((map) => ChatMessage.fromMap(map, currentUserId))
            .toList());
  }

  Future<void> sendGroupMessage(String groupId, String content, {String? mediaUrl, String? mediaType, String? stickerId, String? fileName}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('messages').insert({
      'sender_id': user.id,
      'group_id': groupId,
      'content': content,
      'media_url': mediaUrl,
      'media_type': mediaType ?? 'text',
      'sticker_id': stickerId,
      'file_name': fileName,
    });
  }

  Future<void> sendMessage(String receiverId, String content, {String? mediaUrl, String? mediaType, String? stickerId, String? fileName}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('messages').insert({
      'sender_id': user.id,
      'receiver_id': receiverId,
      'content': content,
      'media_url': mediaUrl,
      'media_type': mediaType ?? 'text',
      'sticker_id': stickerId,
      'file_name': fileName,
    });
  }
}

final chatServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return ChatService(client);
});

