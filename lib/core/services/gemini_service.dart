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
      // For the prototype, we return a structured mock along with the AI insight
      return {
        'optimized_path': [
          {'lat': -15.3875, 'lng': 28.3228},
          {'lat': -15.4210, 'lng': 28.2800}
        ],
        'efficiency_rating': 0.95,
        'prophetic_insight': response.text ?? "Success is ordained for this mission.",
      };
    } catch (e) {
      return {
        'optimized_path': [],
        'efficiency_rating': 0.8,
        'prophetic_insight': "Proceed with caution; divine protection is your primary navigator.",
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
      // Prototype returns structured AI resource map
      return {
        'predictions': [
          {'type': 'Seating/Chairs', 'quantity': 50},
          {'type': 'Apostolic Bibles', 'quantity': 100},
          {'type': 'Welfare Support', 'quantity': 5000},
          {'type': 'Logistics Fuel', 'quantity': 200},
        ],
        'prophetic_justification': response.text ?? "Material expansion is required to contain the harvest.",
      };
    } catch (e) {
      return {
        'predictions': [],
        'prophetic_justification': "Visionary growth is projected. Prepare the storehouse.",
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
      
      // Simple parse attempt for the prototype
      if (rawText.contains('{')) {
        // In a real app we'd use json.decode properly
        return {
          'weight': 0.85,
          'category': 'Vision',
          'justification': 'High prophetic density detected.',
          'raw_ai': rawText,
        };
      }
      
      return {
        'weight': 0.5,
        'category': 'General',
        'justification': 'Standard Kingdom communication.',
      };
    } catch (e) {
      return {
        'weight': 0.0,
        'category': 'System',
        'justification': 'Gatekeeper currently offline.',
      };
    }
  }
}

final geminiServiceProvider = Provider((ref) => GeminiService());

