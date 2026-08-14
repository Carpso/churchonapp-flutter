import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/config/env.dart';

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

  static const _errorPrefix = 'Sorry, I encountered an error';
static const _fallbackResponses = [
      "I'm here to help with your spiritual questions and church activities.",
      "How can I assist you today with scripture or church matters?",
      "I'm ready to guide you — what's on your mind regarding faith or church?",
    ];

  Stream<List<AiChatMessage>> getMessagesStream(String sessionId) {
    return _client
        .from('ai_chat_messages')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .map((data) {
      final messages = data.map((map) => AiChatMessage.fromMap(map)).toList();
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return messages;
    });
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
  Stream<String> sendMessageStreaming(String sessionId, String content) {
    return _send(sessionId, content, insertUserMessage: true);
  }

  /// Legacy non-streaming send — calls streaming internally and accumulates.
  Future<void> sendMessage(String sessionId, String content) async {
    await for (final _ in sendMessageStreaming(sessionId, content)) {
      // Consume stream to completion
    }
  }

  /// Re-fetches the last assistant message for regeneration.
  /// Does NOT duplicate the user message — it reuses the last user row.
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

    // Re-send using the streaming pipeline without re-inserting the user row
    yield* _send(sessionId, lastUserMsg['content'] as String, insertUserMessage: false);
  }

  Stream<String> _send(
    String sessionId,
    String content, {
    required bool insertUserMessage,
  }) async* {
    if (insertUserMessage) {
      await _client.from('ai_chat_messages').insert({
        'session_id': sessionId,
        'role': 'user',
        'content': content,
      });
    }

    // Fetch last 10 messages for conversation history (error rows excluded)
    final history = await _fetchMessageHistory(sessionId, limit: 10);

    // Fetch user context for personalized responses
    final userContext = await _fetchUserContext();

    String fullResponse = '';
    var isError = false;
    try {
      var isFirstChunk = true;
      await for (final rawChunk in _streamKael(history, userContext)) {
        var chunk = rawChunk;
        if (isFirstChunk) {
          chunk = _cleanResponse(chunk, content, allowFallback: false);
          isFirstChunk = false;
        }
        chunk = _stripMarkers(chunk);
        if (chunk.isEmpty) continue;
        fullResponse += chunk;
        yield chunk;
      }
      if (fullResponse.trim().isEmpty) {
        final fallback = _fallbackResponses.firstWhere(
          (r) => !fullResponse.toLowerCase().contains(r.toLowerCase()),
          orElse: () => _fallbackResponses[0],
        );
        fullResponse = fallback;
        yield fullResponse;
      }
      if (fullResponse.startsWith(_errorPrefix)) isError = true;
    } catch (e) {
      debugPrint('[Kael] request failed: $e');
      fullResponse = '$_errorPrefix: $e';
      isError = true;
      yield fullResponse;
    }

    // Save the clean assistant response to DB (never persist error text)
    if (!isError && fullResponse.trim().isNotEmpty) {
      await _client.from('ai_chat_messages').insert({
        'session_id': sessionId,
        'role': 'assistant',
        'content': fullResponse.trim(),
      });
    }
  }

  /// Streams Kael's reply from the Edge Function.
  ///
  /// Primary path: true SSE streaming over raw HTTP (incremental chunks, no
  /// 60s functions.invoke timeout). Fallback: buffered functions.invoke.
  Stream<String> _streamKael(
    List<Map<String, String>> history,
    Map<String, dynamic>? userContext,
  ) async* {
    try {
      final token = _client.auth.currentSession?.accessToken;
      if (token != null) {
        final uri = Uri.parse('${Env.supabaseUrl}/functions/v1/kael-ai');
        final httpClient = http.Client();
        try {
          final request = http.Request('POST', uri)
            ..headers.addAll({
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'text/event-stream',
            })
            ..body = jsonEncode({
              'messages': history,
              'userContext': userContext,
              'action': 'chat',
            });

          final streamed = await httpClient.send(request);
          if (streamed.statusCode == 200) {
            var handled = false;
            await for (final line in streamed.stream
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
              final trimmed = line.trim();
              if (!trimmed.startsWith('data: ')) continue;
              final jsonStr = trimmed.substring(6).trim();
              if (jsonStr.isEmpty) continue;
              Map<String, dynamic>? payload;
              try {
                payload = jsonDecode(jsonStr) as Map<String, dynamic>;
              } catch (_) {
                continue;
              }
              handled = true;
              if (payload['done'] == true) break;
              if (payload['error'] != null) {
                yield '$_errorPrefix: ${payload['error']}';
                return;
              }
              final chunk = payload['chunk'] as String? ?? payload['response'] as String?;
              if (chunk != null && chunk.isNotEmpty) yield chunk;
            }
            if (handled) return;
          } else {
            debugPrint('[Kael] SSE HTTP ${streamed.statusCode}, falling back to invoke');
          }
        } finally {
          httpClient.close();
        }
      }
    } catch (e) {
      debugPrint('[Kael] SSE streaming failed, falling back to invoke: $e');
    }

    // Buffered fallback — same contract, parsed from a single response.
    try {
      final result = await _client.functions.invoke('kael-ai', body: {
        'messages': history,
        'userContext': userContext,
        'action': 'chat',
      });
      final parsed = _parseInvokeResult(result.data);
      if (parsed.isNotEmpty) yield parsed;
    } catch (e) {
      throw Exception('$_errorPrefix: $e');
    }
  }

  /// Parses a buffered functions.invoke result (Map JSON, SSE bytes, or String).
  static String _parseInvokeResult(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data.containsKey('error')) {
        return '$_errorPrefix: ${data['error']}';
      }
      final text = data['response'] as String? ?? data['reply'] as String?;
      return (text == null || text.isEmpty) ? '' : text;
    }
    if (data is List<int>) {
      return _parseSseResponse(utf8.decode(data));
    }
    if (data is String) return data;
    return data?.toString() ?? '';
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

  static const _markerPatterns = [
    '[INST]', '[/INST]', '<s>', '</s>', '<|system|>', '<|user|>', '<|assistant|>', '<|endoftext|>',
  ];

  static String _stripMarkers(String text) {
    var cleaned = text;
    for (final marker in _markerPatterns) {
      cleaned = cleaned.replaceAll(marker, '');
    }
    return cleaned;
  }

  /// Strips leading echoes / prompt artifacts from the first streamed chunk.
  static String _cleanResponse(String text, String userContent, {bool allowFallback = true}) {
    if (text.trim().isEmpty) {
      if (allowFallback) {
        final fallback = _fallbackResponses.firstWhere(
          (r) => text.toLowerCase().contains(r.toLowerCase()) == false,
          orElse: () => _fallbackResponses[0],
        );
        return fallback;
      }
      return '';
    }

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

    return cleaned;
  }

  Future<List<Map<String, String>>> _fetchMessageHistory(String sessionId, {int limit = 10}) async {
    final messages = await _client
        .from('ai_chat_messages')
        .select('role, content')
        .eq('session_id', sessionId)
        .order('created_at', ascending: false)
        .limit(limit);

    // Reverse so oldest first (chronological order for LLM), excluding error rows
    final reversed = messages.reversed.toList();

    return reversed
        .where((m) => !((m['content'] as String? ?? '').startsWith(_errorPrefix)))
        .map((m) => {
              'role': m['role'] as String,
              'content': m['content'] as String,
            })
        .toList();
  }

  Future<Map<String, dynamic>?> _fetchUserContext() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final profile = await _client
          .from('profiles')
          .select('full_name, role, coins, level, tenant_id')
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) return null;

      // Fetch church name from the user's OWN tenant (never the first tenant in the table)
      String? churchName;
      final tenantId = profile['tenant_id'];
      if (tenantId != null) {
        try {
          final tenantRes = await _client
              .from('tenants')
              .select('name')
              .eq('id', tenantId)
              .maybeSingle();
          churchName = tenantRes?['name'] as String?;
        } catch (e) {
          debugPrint('[Kael] Tenant lookup failed (tenant_id may be text): $e');
        }
      }

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
