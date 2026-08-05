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
  final String? reaction;
  final String? replyToId;
  final String? replyToText;
  final int readCount;

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
    this.reaction,
    this.replyToId,
    this.replyToText,
    this.readCount = 0,
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
      reaction: map['reaction'],
      replyToId: map['reply_to_id'],
      replyToText: map['reply_to_text'],
      readCount: (map['read_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatService {
  final SupabaseClient _client;

  ChatService(this._client);

  Stream<List<ChatMessage>> streamMessages(String otherUserId) {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return Stream.value([]);

    final sortedIds = [currentUserId, otherUserId]..sort();
    final conversationId = '${sortedIds[0]}_${sortedIds[1]}';

    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .asyncMap((data) async {
          final seenIds = <String>{};
          final filtered = data
              .where((map) => seenIds.add(map['id'] as String))
              .toList();
          final senderIds = filtered.map((m) => m['sender_id'] as String).toSet().toList();
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
          return filtered.map((map) {
            final enriched = Map<String, dynamic>.from(map);
            enriched['profiles'] = profiles[map['sender_id']];
            return ChatMessage.fromMap(enriched, currentUserId);
          }).toList();
        });
  }

  Stream<List<ChatMessage>> streamGroupMessages(String groupId) {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return Stream.value([]);

    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('community_group_id', groupId)
        .order('created_at', ascending: false)
        .asyncMap((data) async {
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

  Future<void> sendGroupMessage(
    String groupId,
    String content, {
    String? mediaUrl,
    String? mediaType,
    String? stickerId,
    String? fileName,
    String? replyToId,
    String? replyToText,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");
    try {
      await _client.from('messages').insert({
        'sender_id': user.id,
        'user_id': user.id,
        'community_group_id': groupId,
        'conversation_id': 'community_group_$groupId',
        'content': content,
        'media_url': mediaUrl,
        'media_type': mediaType ?? 'text',
        'sticker_id': stickerId,
        'file_name': fileName,
        'reply_to_id': replyToId,
        'reply_to_text': replyToText,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('sendGroupMessage error: $e. Retrying resilient insert...');
      try {
        await _client.from('messages').insert({
          'sender_id': user.id,
          'community_group_id': groupId,
          'content': content,
          'media_url': mediaUrl,
          'media_type': mediaType ?? 'text',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (err) {
        debugPrint('Resilient sendGroupMessage fallback error: $err');
        rethrow;
      }
    }
  }

  Future<void> sendMessage(
    String receiverId,
    String content, {
    String? mediaUrl,
    String? mediaType,
    String? stickerId,
    String? fileName,
    String? replyToId,
    String? replyToText,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");
    final sortedIds = [user.id, receiverId]..sort();
    final conversationId = '${sortedIds[0]}_${sortedIds[1]}';
    try {
      await _client.from('messages').insert({
        'sender_id': user.id,
        'user_id': user.id,
        'receiver_id': receiverId,
        'content': content,
        'media_url': mediaUrl,
        'media_type': mediaType ?? 'text',
        'sticker_id': stickerId,
        'file_name': fileName,
        'reply_to_id': replyToId,
        'reply_to_text': replyToText,
        'conversation_id': conversationId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('sendMessage error: $e. Retrying resilient insert...');
      try {
        await _client.from('messages').insert({
          'sender_id': user.id,
          'receiver_id': receiverId,
          'content': content,
          'media_url': mediaUrl,
          'media_type': mediaType ?? 'text',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (err) {
        debugPrint('Resilient sendMessage fallback error: $err');
        rethrow;
      }
    }
  }

  /// Mark messages as read for the current user
  Future<void> markAsRead(String senderId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client
          .from('messages')
          .update({'is_read': true})
          .eq('sender_id', senderId)
          .eq('receiver_id', user.id)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('markAsRead error: $e');
    }
  }

  /// Fetch church members for DM list, scoped to user's tenant
  Future<List<Map<String, dynamic>>> fetchChurchMembers({int limit = 30, String? tenantId}) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return [];
    try {
      var query = _client
          .from('profiles')
          .select('id, full_name, avatar_url, role, tenant_id')
          .neq('id', currentUserId);

      if (tenantId != null && tenantId.isNotEmpty) {
        query = query.eq('tenant_id', tenantId);
      }

      final res = await query.limit(limit);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchGroupMembers(String groupId, {int limit = 5}) async {
    try {
      final res = await _client
          .from('community_group_members')
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
