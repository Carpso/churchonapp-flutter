import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class AiChatMessage {
  final String id;
  final String content;
  final String role; // user, assistant
  final DateTime createdAt;

  AiChatMessage({
    required this.id,
    required this.content,
    required this.role,
    required this.createdAt,
  });

  factory AiChatMessage.fromMap(Map<String, dynamic> map) {
    return AiChatMessage(
      id: map['id'],
      content: map['content'],
      role: map['role'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}

class AiChatService {
  final SupabaseClient _client;

  AiChatService(this._client);

  Stream<List<AiChatMessage>> getMessagesStream(String sessionId) {
    return _client
        .from('ai_chat_messages')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('created_at', ascending: true)
        .map((data) => data.map((map) => AiChatMessage.fromMap(map)).toList());
  }

  Future<String> createSession(String title) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    final response = await _client.from('ai_chat_sessions').insert({
      'user_id': user.id,
      'title': title,
    }).select().single();

    return response['id'];
  }

  Future<void> sendMessage(String sessionId, String content) async {
    // 1. Insert user message
    await _client.from('ai_chat_messages').insert({
      'session_id': sessionId,
      'role': 'user',
      'content': content,
    });

    // 2. In a real VPS setup, the background worker would pick this up and generate a response.
    // For demonstration, we simulate a response from Kael AI.
    await Future.delayed(const Duration(seconds: 1));
    await _client.from('ai_chat_messages').insert({
      'session_id': sessionId,
      'role': 'assistant',
      'content': "Praise the Lord! I am Kael, your Kingdom AI assistant. I've received your message: '$content'. How can I further assist your spiritual journey today?",
    });
  }
}

final aiChatServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return AiChatService(client);
});
