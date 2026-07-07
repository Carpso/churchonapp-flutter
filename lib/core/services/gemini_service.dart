import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/env.dart';

class GeminiService {
  late final GenerativeModel _model;

  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: Env.geminiApiKey,
    );
  }

  Future<String> generateFinancialReport(Map<String, dynamic> stats) async {
    final prompt = "As an Apostolic Financial Oversight Agent, analyze these monthly church stats: $stats. "
                  "Provide a concise report (max 200 words) with: 1. Financial Health Summary, 2. Growth Trends, "
                  "3. A 'Prophetic Action' for the upcoming month to increase stewardship.";

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return response.text ?? "Unable to generate spiritual insights at this time.";
    } catch (e) {
      return "The AI Prophet is currently meditating. Statistics confirm K ${stats['total']} in total volume.";
    }
  }

  Future<Map<String, dynamic>> optimizeLogisticsRoute(Map<String, dynamic> missionData) async {
    final prompt = "As a Kingdom Logistics Strategist, optimize this cargo mission: $missionData. "
                  "Provide: 1. A verified optimized route plan, 2. Efficiency factor (0.0 to 1.0), "
                  "3. A 'Prophetic Logistics' insight to ensure the safety and success of the cargo.";

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return {
        'ai_response': response.text ?? "Success is ordained for this mission.",
      };
    } catch (e) {
      return {
        'ai_response': "Route optimization unavailable at this time.",
      };
    }
  }

  Future<Map<String, dynamic>> predictApostolicResourceNeeds(Map<String, dynamic> hubData) async {
    final prompt = "As an Apostolic Oversight Strategist, analyze this regional church hub: $hubData. "
                  "Predict the material resource needs for the next 3 months (chairs, Bibles, welfare funds, fuel). "
                  "Provide: 1. A list of resource types with predicted quantities, 2. A 'Prophetic Justification' for each allocation.";

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return {
        'ai_response': response.text ?? "Material expansion is required to contain the harvest.",
      };
    } catch (e) {
      return {
        'ai_response': "Resource prediction unavailable at this time.",
      };
    }
  }

  Future<Map<String, dynamic>> moderateSocialPost(String content) async {
    final prompt = "As a Kingdom Gatekeeper AI, analyze this social post/testimony: \"$content\". "
                  "Provide: 1. A 'Prophetic Weight' (double 0.0 to 1.0) based on spiritual impact and clarity. "
                  "2. A category (Testimony, Vision, Exhortation, Warning). "
                  "3. A 'Justification' for this weight. "
                  "Return in JSON format: {\"weight\": 0.8, \"category\": \"Testimony\", \"justification\": \"...\"}";

    try {
      final textContent = [Content.text(prompt)];
      final response = await _model.generateContent(textContent);
      final rawText = response.text ?? "";
      
      try {
        final parsed = jsonDecode(rawText) as Map<String, dynamic>;
        return {
          'weight': (parsed['weight'] as num?)?.toDouble() ?? 0.5,
          'category': parsed['category']?.toString() ?? 'General',
          'justification': parsed['justification']?.toString() ?? 'Standard Kingdom communication.',
        };
      } catch (_) {
        return {
          'weight': 0.5,
          'category': 'General',
          'justification': rawText.isNotEmpty ? rawText : 'Standard Kingdom communication.',
        };
      }
    } catch (e) {
      return {
        'weight': 0.0,
        'category': 'System',
        'justification': 'Gatekeeper currently offline.',
      };
    }
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

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      final raw = response.text ?? '[]';
      final cleaned = raw
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();

      List<dynamic> parsed = [];
      try {
        parsed = (jsonDecode(cleaned) as List?) ?? [];
      } catch (_) {
        // Try to extract array from markdown
        final match = RegExp(r'\[[\s\S]*\]').firstMatch(cleaned);
        if (match != null) {
          parsed = jsonDecode(match.group(0)!) as List? ?? [];
        } else {
          return [];
        }
      }

      return parsed.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint("Gemini quiz generation failed: $e");
      return [];
    }
  }
}

final geminiServiceProvider = Provider((ref) => GeminiService());

