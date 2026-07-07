import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

class ChatMessage {
  final String id;
  final String text;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
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
    required this.senderName,
    this.senderAvatar,
    required this.createdAt,
    required this.isMe,
    this.mediaUrl,
    this.mediaType = 'text',
    this.stickerId,
    this.fileName,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map, String currentUserId) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    return ChatMessage(
      id: map['id'],
      text: map['content'] ?? '',
      senderId: map['sender_id'] ?? '',
      senderName: profile?['full_name'] ?? map['sender_name'] ?? 'Member',
      senderAvatar: profile?['avatar_url'] ?? map['sender_avatar'],
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

  // ── 1-to-1 DM stream ─────────────────────────────────────────────────────
  Stream<List<ChatMessage>> streamMessages(String otherUserId) {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return Stream.value([]);

    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => data
            .where((map) =>
                (map['sender_id'] == currentUserId &&
                    map['receiver_id'] == otherUserId) ||
                (map['sender_id'] == otherUserId &&
                    map['receiver_id'] == currentUserId))
            .map((map) => ChatMessage.fromMap(map, currentUserId))
            .toList());
  }

  // ── Group message stream (with sender name join) ──────────────────────────
  Stream<List<ChatMessage>> streamGroupMessages(String groupId) {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return Stream.value([]);

    // Use postgres changes for real-time group messages with profile join
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .order('created_at', ascending: false)
        .asyncMap((data) async {
          // Batch-fetch sender profiles to avoid N+1
          final senderIds = data.map((m) => m['sender_id'] as String).toSet().toList();
          Map<String, Map<String, dynamic>> profiles = {};
          if (senderIds.isNotEmpty) {
            try {
              final res = await _client
                  .from('profiles')
                  .select('id, full_name, avatar_url')
                  .inFilter('id', senderIds);
              for (final p in res) {
                profiles[p['id'] as String] = p;
              }
            } catch (e) {
              debugPrint('Failed to load sender profiles: $e');
            }
          }
          return data.map((map) {
            final enriched = Map<String, dynamic>.from(map);
            enriched['profiles'] = profiles[map['sender_id']];
            return ChatMessage.fromMap(enriched, currentUserId);
          }).toList();
        });
  }

  // ── Send group message ────────────────────────────────────────────────────
  Future<void> sendGroupMessage(
    String groupId,
    String content, {
    String? mediaUrl,
    String? mediaType,
    String? stickerId,
    String? fileName,
  }) async {
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

  // ── Send 1-to-1 message ───────────────────────────────────────────────────
  Future<void> sendMessage(
    String receiverId,
    String content, {
    String? mediaUrl,
    String? mediaType,
    String? stickerId,
    String? fileName,
  }) async {
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

  // ── Fetch church members for DM list ─────────────────────────────────────
  Future<List<Map<String, dynamic>>> fetchChurchMembers({int limit = 20}) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return [];
    try {
      final res = await _client
          .from('profiles')
          .select('id, full_name, avatar_url, role')
          .neq('id', currentUserId)
          .limit(limit);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
  }

  // ── Fetch group members ───────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> fetchGroupMembers(String groupId, {int limit = 5}) async {
    try {
      final res = await _client
          .from('group_members')
          .select('user_id, profiles(id, full_name, avatar_url)')
          .eq('group_id', groupId)
          .limit(limit);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
  }
}

final chatServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return ChatService(client);
});
