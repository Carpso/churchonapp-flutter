import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class AiChatMessage {
  final String id;
  final String content;
  final String role;
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

  /// Sends a message and streams the assistant's response in real-time.
  ///
  /// Returns a [Stream<String>] of text chunks as they arrive from the Edge Function.
  /// The full accumulated response is saved to the database when the stream completes.
  Stream<String> sendMessageStreaming(String sessionId, String content) async* {
    // 1. Save user message to DB
    await _client.from('ai_chat_messages').insert({
      'session_id': sessionId,
      'role': 'user',
      'content': content,
    });

    // 2. Fetch last 10 messages for conversation history
    final history = await _fetchMessageHistory(sessionId, limit: 10);

    // 3. Fetch user context for personalized responses
    final userContext = await _fetchUserContext();

    // 4. Call the Edge Function via supabase.functions.invoke()
    String fullResponse = '';
    try {
      final result = await _client.functions.invoke('kael-ai', body: {
        'messages': history,
        'userContext': userContext,
        'systemPrompt': 'You are Kael, a deeply knowledgeable, warm, and inspiring AI assistant on Church On App. Provide biblical wisdom, encouragement, clear formatting, and actionable guidance. Never repeat the user question or echo generic greetings.',
      });
      if (result.data is Map<String, dynamic>) {
        final data = result.data as Map<String, dynamic>;
        if (data.containsKey('error')) {
          fullResponse = 'Sorry, I encountered an error: ${data['error']}';
        } else {
          fullResponse = data['response'] as String? ?? data['reply'] as String? ?? jsonEncode(result.data);
        }
      } else if (result.data is List<int>) {
        // Raw bytes (e.g. SSE from Edge Function)
        final raw = utf8.decode(result.data as List<int>);
        fullResponse = _parseSseResponse(raw);
      } else if (result.data is String) {
        fullResponse = result.data as String;
      } else {
        fullResponse = result.data?.toString() ?? 'No response from Kael';
      }
    } catch (e) {
      fullResponse = 'Sorry, I encountered an error: $e';
    }

    // Clean echoed query / repeated greetings
    fullResponse = _cleanResponse(fullResponse, content);
    yield fullResponse;

    // 5. Save the clean assistant response to DB
    if (fullResponse.isNotEmpty) {
      await _client.from('ai_chat_messages').insert({
        'session_id': sessionId,
        'role': 'assistant',
        'content': fullResponse,
      });
    }
  }

  /// Parses SSE (text/event-stream) response and extracts the full text.
  /// Handles both `data: {"chunk": "..."}` and `data: {"response": "..."}` formats.
  static String _parseSseResponse(String raw) {
    if (raw.trim().isEmpty) return '';
    final buffer = StringBuffer();
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data: ')) continue;
      final jsonStr = trimmed.substring(6).trim();
      if (jsonStr.isEmpty) continue;
      try {
        final payload = jsonDecode(jsonStr) as Map<String, dynamic>?;
        if (payload == null) continue;
        if (payload['done'] == true) break;
        final chunk = payload['chunk'] as String? ?? payload['response'] as String? ?? payload['reply'] as String?;
        if (chunk != null && chunk.isNotEmpty) buffer.write(chunk);
      } catch (_) {
        // If not JSON, treat the entire data line as the response text
        buffer.write(jsonStr);
      }
    }
    return buffer.toString();
  }

  static String _cleanResponse(String text, String userContent) {
    if (text.isEmpty) return "I'm here to assist you with any spiritual guidance, scripture study, or church activities!";
    
    var cleaned = text;

    // 1. Remove echoed prompt / user content if returned at start
    final trimmedUser = userContent.trim();
    if (trimmedUser.isNotEmpty && cleaned.toLowerCase().startsWith(trimmedUser.toLowerCase())) {
      cleaned = cleaned.substring(trimmedUser.length).trim();
    }

    // 2. Strip repeated system phrases / greeting prompts
    final patterns = [
      RegExp(r'^(hello!?\s*)?ask kael anything:?\s*', caseSensitive: false),
      RegExp(r'^user query:?\s*.*?\n', caseSensitive: false),
      RegExp(r'^system prompt:?\s*.*?\n', caseSensitive: false),
      RegExp(r'^kael:?\s*', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      cleaned = cleaned.replaceFirst(pattern, '').trim();
    }

    if (cleaned.startsWith(':')) cleaned = cleaned.substring(1).trim();

    return cleaned.isNotEmpty ? cleaned : "I'm here to assist you with any spiritual guidance, scripture study, or church activities!";
  }

  /// Legacy non-streaming send — calls streaming internally and accumulates.
  Future<void> sendMessage(String sessionId, String content) async {
    await for (final _ in sendMessageStreaming(sessionId, content)) {
      // Consume stream to completion
    }
  }

  /// Re-fetches the last assistant message for regeneration.
  Stream<String> regenerateStreaming(String sessionId) async* {
    // Find and delete the last assistant message
    final lastMsg = await _client
        .from('ai_chat_messages')
        .select('id, content')
        .eq('session_id', sessionId)
        .eq('role', 'assistant')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (lastMsg != null) {
      await _client.from('ai_chat_messages').delete().eq('id', lastMsg['id']);
    }

    // Find the last user message to regenerate from
    final lastUserMsg = await _client
        .from('ai_chat_messages')
        .select('content')
        .eq('session_id', sessionId)
        .eq('role', 'user')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (lastUserMsg == null) return;

    // Re-send using the streaming pipeline
    yield* sendMessageStreaming(sessionId, lastUserMsg['content'] as String);
  }

  Future<List<Map<String, String>>> _fetchMessageHistory(String sessionId, {int limit = 10}) async {
    final messages = await _client
        .from('ai_chat_messages')
        .select('role, content')
        .eq('session_id', sessionId)
        .order('created_at', ascending: false)
        .limit(limit);

    // Reverse so oldest first (chronological order for LLM)
    final reversed = messages.reversed.toList();

    return reversed.map((m) => {
      'role': m['role'] as String,
      'content': m['content'] as String,
    }).toList();
  }

  Future<Map<String, dynamic>?> _fetchUserContext() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final profile = await _client
          .from('profiles')
          .select('full_name, role, coins, level')
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) return null;

      // Fetch church name from tenant
      String? churchName;
      final tenantRes = await _client
          .from('tenants')
          .select('name')
          .limit(1)
          .maybeSingle();
      churchName = tenantRes?['name'] as String?;

      // Fetch quiz streak
      int streak = 0;
      try {
        final streakRes = await _client
            .from('quiz_streaks')
            .select('current_streak')
            .eq('user_id', user.id)
            .maybeSingle();
        streak = (streakRes?['current_streak'] as num?)?.toInt() ?? 0;
      } catch (_) {
        // Streak table may not exist
      }

      return {
        'name': profile['full_name'] ?? 'User',
        'role': profile['role'] ?? 'member',
        'church_name': churchName ?? 'your church',
        'streak': streak,
        'level': profile['level'] ?? 'Beginner',
        'coins': profile['coins'] ?? 0,
      };
    } catch (e) {
      debugPrint('[Kael] Failed to fetch user context: $e');
      return null;
    }
  }


}

final aiChatServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return AiChatService(client);
});
