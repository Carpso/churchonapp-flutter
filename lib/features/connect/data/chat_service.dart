import 'dart:async';
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
  final bool isRead;

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
    this.isRead = false,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map, String currentUserId) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    final isReadRaw = map['is_read'];
    final readCountRaw = (map['read_count'] as num?)?.toInt() ?? 0;
    final isRead = isReadRaw == true || isReadRaw == 1 || readCountRaw > 0;
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
      readCount: readCountRaw,
      isRead: isRead,
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
        .limit(100)
        .asyncMap((data) async {
          final seenIds = <String>{};
          final filtered = data
              .where((map) => seenIds.add(map['id'] as String))
              .toList();
          // Sort client-side (realtime streams can't reliably order).
          filtered.sort((a, b) {
            final ta = a['created_at']?.toString() ?? '';
            final tb = b['created_at']?.toString() ?? '';
            return tb.compareTo(ta);
          });
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
        .limit(100)
        .asyncMap((data) async {
          final seenIds = <String>{};
          final filtered = data
              .where((map) => seenIds.add(map['id'] as String))
              .toList();
          filtered.sort((a, b) {
            final ta = a['created_at']?.toString() ?? '';
            final tb = b['created_at']?.toString() ?? '';
            return tb.compareTo(ta);
          });
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

        // Fire push notification to recipient (fire-and-forget)
        _notifyMessage(receiverId, content);

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

  /// Mark messages as read for the current user.
  /// Updates both is_read and read_count for backward compatibility with the
  /// chat bubble's double-tick logic (readCount >0 or isRead true => blue ticks).
  Future<void> markAsRead(String senderId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client
          .from('messages')
          .update({'is_read': true, 'read_count': 1})
          .eq('sender_id', senderId)
          .eq('receiver_id', user.id)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('markAsRead error: $e');
    }
  }

  /// Mark all unread messages in the current conversation (1-1 or group) as read.
  /// Called automatically when the chat screen is open and new messages arrive.
  Future<void> markConversationAsRead(String otherUserId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client
          .from('messages')
          .update({'is_read': true, 'read_count': 1})
          .eq('sender_id', otherUserId)
          .eq('receiver_id', user.id)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('markConversationAsRead error: $e');
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
      // community_group_members.user_id FKs to auth.users (not profiles.id), so
      // PostgREST cannot embed profiles directly. Fetch memberships, then a
      // separate profiles query, and shape as {user_id, profiles: {...}}.
      final memberships = List<Map<String, dynamic>>.from(await _client
          .from('community_group_members')
          .select('user_id')
          .eq('group_id', groupId)
          .limit(limit));
      final userIds = memberships.map((m) => m['user_id']?.toString()).whereType<String>().toSet().toList();
      Map<String, Map<String, dynamic>> profileMap = {};
      if (userIds.isNotEmpty) {
        try {
          final res = await _client
              .from('profiles')
              .select('id, full_name, avatar_url, username')
              .inFilter('id', userIds);
          for (final row in (res as List)) {
            profileMap[row['id']?.toString() ?? ''] = Map<String, dynamic>.from(row);
          }
        } catch (_) {}
      }
      return memberships.map((m) {
        final uid = m['user_id']?.toString() ?? '';
        return {
          'user_id': uid,
          'profiles': profileMap[uid],
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // Typing indicators via Supabase Realtime broadcast.
  // Uses a per-conversation channel: typing_<sorted_ids>
  final Map<String, StreamController<bool>> _typingControllers = {};

  Stream<bool> typingStream(String otherUserId) {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return const Stream.empty();
    final sortedIds = [currentUserId, otherUserId]..sort();
    final channelName = 'typing_${sortedIds[0]}_${sortedIds[1]}';
    _typingControllers[channelName] ??= StreamController<bool>.broadcast();
    // Subscribe to broadcast channel for remote typing
    try {
      final channel = _client.channel(channelName);
      channel.onBroadcast(event: 'typing', callback: (payload) {
        final isTyping = payload['isTyping'] == true && payload['userId'] != currentUserId;
        _typingControllers[channelName]?.add(isTyping);
      }).subscribe();
    } catch (_) {}
    return _typingControllers[channelName]!.stream;
  }

  Future<void> setTyping(String otherUserId, bool isTyping) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return;
    final sortedIds = [currentUserId, otherUserId]..sort();
    final channelName = 'typing_${sortedIds[0]}_${sortedIds[1]}';
    try {
      final channel = _client.channel(channelName);
      await channel.sendBroadcastMessage(event: 'typing', payload: {'userId': currentUserId, 'isTyping': isTyping});
    } catch (_) {}
  }

  Future<void> _notifyMessage(String receiverId, String content) async {
    try {
      final senderName = _client.auth.currentUser?.userMetadata?['full_name'] ?? 'Someone';
      final preview = content.length > 50 ? '${content.substring(0, 50)}...' : content;
      await _client.functions.invoke('push-notifications', body: {
        'userId': receiverId,
        'title': senderName,
        'body': preview,
        'type': 'chat_message',
        'referenceId': receiverId,
        'channelId': 'messages',
      });
    } catch (_) {
      // Fire-and-forget — notification failure is non-critical
    }
  }
}

final chatServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return ChatService(client);
});
