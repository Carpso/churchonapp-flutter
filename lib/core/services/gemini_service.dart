import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-side AI generation proxy.
///
/// All AI calls are forwarded to the `kael-ai` Edge Function, which holds the
/// `GEMINI_API_KEY` / `HUGGINGFACE_TOKEN` secrets in its environment. The
/// client never embeds an AI API key (removed in the 2026-08-13 security
/// sprint). Non-chat actions return `{ "response": "..." }`.
class GeminiService {
  final SupabaseClient? _client;

  GeminiService([this._client]);

  Future<String> _generate(String action, String prompt) async {
    final client = _client;
    if (client == null) return ''; // offline/fallback path (tests, pre-auth)
    try {
      final res = await client.functions.invoke('kael-ai', body: {
        'action': action,
        'prompt': prompt,
      });
      final data = res.data;
      if (data is Map && data['response'] is String) {
        return data['response'] as String;
      }
      return '';
    } catch (e) {
      debugPrint('GeminiService $_generate error: $e');
      return '';
    }
  }

  Future<String> generateFinancialReport(Map<String, dynamic> stats) async {
    final prompt = "As an Apostolic Financial Oversight Agent, analyze these monthly church stats: $stats. "
                  "Provide a concise report (max 200 words) with: 1. Financial Health Summary, 2. Growth Trends, "
                  "3. A 'Prophetic Action' for the upcoming month to increase stewardship.";

    final text = await _generate('report', prompt);
    return text.isNotEmpty ? text : "The AI Prophet is currently meditating. Statistics confirm K ${stats['total']} in total volume.";
  }

  Future<Map<String, dynamic>> optimizeLogisticsRoute(Map<String, dynamic> missionData) async {
    final prompt = "As a Logistics Strategist, optimize this cargo mission: $missionData. "
                  "Provide: 1. A verified optimized route plan, 2. Efficiency factor (0.0 to 1.0), "
                  "3. A 'Prophetic Logistics' insight to ensure the safety and success of the cargo.";

    final text = await _generate('report', prompt);
    return {
      'ai_response': text.isNotEmpty ? text : "Success is ordained for this mission.",
    };
  }

  Future<Map<String, dynamic>> predictApostolicResourceNeeds(Map<String, dynamic> hubData) async {
    final prompt = "As an Apostolic Oversight Strategist, analyze this regional church hub: $hubData. "
                  "Predict the material resource needs for the next 3 months (chairs, Bibles, welfare funds, fuel). "
                  "Provide: 1. A list of resource types with predicted quantities, 2. A 'Prophetic Justification' for each allocation.";

    final text = await _generate('report', prompt);
    return {
      'ai_response': text.isNotEmpty ? text : "Material expansion is required to contain the harvest.",
    };
  }

  Future<Map<String, dynamic>> moderateSocialPost(String content) async {
    final prompt = "As a Gatekeeper AI, analyze this social post/testimony: \"$content\". "
                  "Provide: 1. A 'Prophetic Weight' (double 0.0 to 1.0) based on spiritual impact and clarity. "
                  "2. A category (Testimony, Vision, Exhortation, Warning). "
                  "3. A 'Justification' for this weight. "
                  "Return in JSON format: {\"weight\": 0.8, \"category\": \"Testimony\", \"justification\": \"...\"}";

    final rawText = await _generate('report', prompt);

    if (rawText.isNotEmpty) {
      try {
        final parsed = jsonDecode(rawText) as Map<String, dynamic>;
        return {
          'weight': (parsed['weight'] as num?)?.toDouble() ?? 0.5,
          'category': parsed['category']?.toString() ?? 'General',
          'justification': parsed['justification']?.toString() ?? 'Standard communication.',
        };
      } catch (_) {
        return {
          'weight': 0.5,
          'category': 'General',
          'justification': rawText,
        };
      }
    }
    return {
      'weight': 0.0,
      'category': 'System',
      'justification': 'Gatekeeper currently offline.',
    };
  }

  Future<List<Map<String, dynamic>>> generateBibleQuizQuestions({
    required int count,
    String? category,
    String? difficulty,
    List<String>? excludeQuestions,
  }) async {
    final catHint = category != null ? "Category: $category. " : "";
    final diffHint = difficulty != null ? "Difficulty: $difficulty. " : "";
    final excludeHint = excludeQuestions != null && excludeQuestions.isNotEmpty
        ? "Do NOT repeat any of these questions: ${excludeQuestions.join('; ')}. "
        : "";
    final prompt = "You are a Bible quiz expert. Generate $count multiple-choice Bible quiz questions. "
        "$catHint$diffHint${excludeHint}Each question must be factual, scripture-based, and theologically sound. "
        "Return ONLY valid JSON array — no markdown, no code fences. "
        "Each item: {"
        "\"question\": \"...\", "
        "\"options\": [\"A\", \"B\", \"C\", \"D\"], "
        "\"correct_answer\": 0, "
        "\"difficulty\": \"Easy|Medium|Hard\", "
        "\"category\": \"People|History|NT|OT|Prophecy|Miracles|Scripture|Language|Law|Angels\", "
        "\"scripture_reference\": \"Book Chapter:Verse\""
        "}";

    final raw = await _generate('report', prompt);
    if (raw.isEmpty) return [];

    final cleaned = raw
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();

    List<dynamic> parsed = [];
    try {
      parsed = (jsonDecode(cleaned) as List?) ?? [];
    } catch (_) {
      final match = RegExp(r'\[[\s\S]*\]').firstMatch(cleaned);
      if (match != null) {
        try {
          parsed = jsonDecode(match.group(0)!) as List? ?? [];
        } catch (_) {
          return [];
        }
      } else {
        return [];
      }
    }

    return parsed.cast<Map<String, dynamic>>();
  }
}

final geminiServiceProvider = Provider((ref) => GeminiService(Supabase.instance.client));
