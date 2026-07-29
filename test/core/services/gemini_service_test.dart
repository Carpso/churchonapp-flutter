import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/core/services/gemini_service.dart';

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: '''
      GEMINI_API_KEY=test-key
    ''');
  });

  test('GeminiService can be instantiated', () {
    final service = GeminiService();
    expect(service, isA<GeminiService>());
  });

  /* test('chat() returns empty string on error (no real API key)', () async {
    final service = GeminiService();
    final result = await service.chat('Hello');
    expect(result, '');
  }); */

  test('generateFinancialReport handles exception gracefully', () async {
    final service = GeminiService();
    final result = await service.generateFinancialReport({
      'total': 1000,
      'income': 800,
      'expenses': 200,
    });
    expect(result, contains('1000'));
    expect(result, contains('The AI Prophet is currently meditating'));
  });

  test('optimizeLogisticsRoute handles exception gracefully', () async {
    final service = GeminiService();
    final result = await service.optimizeLogisticsRoute({
      'origin': 'Lusaka',
      'destination': 'Ndola',
      'cargo': 'Bibles',
    });
    expect(result['ai_response'], 'Route optimization unavailable at this time.');
  });

  test('moderateSocialPost handles exception gracefully', () async {
    final service = GeminiService();
    final result = await service.moderateSocialPost('Testimony content');
    expect(result['weight'], 0.0);
    expect(result['category'], 'System');
    expect(result['justification'], 'Gatekeeper currently offline.');
  });
}
