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
  static const String _apiUrl = 'https://api-inference.huggingface.co/models/google/flan-t5-base';

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
    await _client.from('ai_chat_messages').insert({
      'session_id': sessionId,
      'role': 'user',
      'content': content,
    });

    final response = await _generateResponse(content);

    await _client.from('ai_chat_messages').insert({
      'session_id': sessionId,
      'role': 'assistant',
      'content': response,
    });
  }

  Future<String> _generateResponse(String userMessage) async {
    try {
      final token = Env.huggingFaceToken;
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final http.Response response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: headers,
            body: jsonEncode({'inputs': userMessage}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.isNotEmpty && data[0].containsKey('generated_text')) {
          final text = data[0]['generated_text'] as String;
          if (text.trim().isNotEmpty) return text.trim();
        }
      }
    } catch (e) {
      debugPrint('AI chat request failed: $e');
    }

    return _fallbackResponse(userMessage);
  }

  String _fallbackResponse(String userMessage) {
    final msg = userMessage.toLowerCase();

    if (msg.contains('prayer') || msg.contains('pray')) {
      return "May the Lord hear your prayers and grant you peace. 'Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God.' — Philippians 4:6. How can I pray with you today?";
    }
    if (msg.contains('bible') || msg.contains('scripture') || msg.contains('verse') || msg.contains('word')) {
      return "The Word of God is a lamp to our feet and a light to our path. 'For the word of God is alive and active. Sharper than any double-edged sword.' — Hebrews 4:12. Would you like a specific verse or passage?";
    }
    if (msg.contains('help') || msg.contains('guidance') || msg.contains('direction')) {
      return "Trust in the Lord with all your heart and lean not on your own understanding. In all your ways acknowledge Him, and He will make your paths straight. — Proverbs 3:5-6. I'm here to help guide you in your spiritual walk.";
    }
    if (msg.contains('worship') || msg.contains('praise')) {
      return "Praise the Lord! Worship is a beautiful expression of our love for God. 'Enter his gates with thanksgiving and his courts with praise.' — Psalm 100:4. Let us rejoice in the Lord always!";
    }
    if (msg.contains('faith') || msg.contains('believe') || msg.contains('trust')) {
      return "Faith is the substance of things hoped for, the evidence of things not seen. — Hebrews 11:1. Your faith in God can move mountains. Keep believing and trusting in His perfect plan for your life.";
    }
    if (msg.contains('sin') || msg.contains('forgive') || msg.contains('repent')) {
      return "If we confess our sins, He is faithful and just to forgive us our sins and to cleanse us from all unrighteousness. — 1 John 1:9. God's mercy is new every morning.";
    }
    if (msg.contains('love') || msg.contains('god')) {
      return "For God so loved the world that He gave His one and only Son, that whoever believes in Him shall not perish but have eternal life. — John 3:16. God's love for you is unfailing and eternal.";
    }
    if (msg.contains('church') || msg.contains('fellowship') || msg.contains('community')) {
      return "The church is the body of Christ, where we grow together in faith and love. 'Let us consider how we may spur one another on toward love and good deeds, not giving up meeting together.' — Hebrews 10:24-25.";
    }
    if (msg.contains('thank') || msg.contains('grateful') || msg.contains('blessing')) {
      return "Give thanks to the Lord, for He is good; His love endures forever. — Psalm 118:1. Gratitude opens the door to more blessings. Count your blessings and see how God has been faithful!";
    }
    if (msg.contains('peace') || msg.contains('anxiety') || msg.contains('fear') || msg.contains('worry')) {
      return "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus. — Philippians 4:6-7.";
    }

    return "Praise the Lord! I am Kael, your Kingdom AI assistant. I've received your message: '$userMessage'. How can I further assist your spiritual journey today?";
  }
}

final aiChatServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return AiChatService(client);
});

