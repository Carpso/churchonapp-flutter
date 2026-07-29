import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/home/data/news_service.dart';
import '../../../test_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSupabaseClient mockClient;
  late NewsService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    service = NewsService(mockClient);
  });

  group('NewsArticle', () {
    test('fromJson parses RSS JSON accurately', () {
      final json = {
        'title': 'Revival in Lusaka',
        'author': 'Zambian Christian News',
        'description': '<img src="https://image.url/pic.jpg" /> Great revival held.',
        'pubDate': '2026-07-26 12:00:00',
        'link': 'https://news.url/1',
      };

      final article = NewsArticle.fromJson(json, 1);
      expect(article.id, 'news-1');
      expect(article.title, 'Revival in Lusaka');
      expect(article.source, 'Zambian Christian News');
      expect(article.image, 'https://image.url/pic.jpg');
      expect(article.isLocal, false);
    });

    test('fromSupabase parses database record accurately', () {
      final map = {
        'id': 'art-100',
        'title': 'Local Outreach Completed',
        'author_name': 'Pastor Grace',
        'excerpt': 'Over 200 attended.',
        'content': 'Detailed article content...',
        'image_url': 'https://storage.url/img.png',
        'created_at': '2026-07-26T10:00:00Z',
      };

      final article = NewsArticle.fromSupabase(map);
      expect(article.id, 'art-100');
      expect(article.title, 'Local Outreach Completed');
      expect(article.source, 'Pastor Grace');
      expect(article.content, 'Detailed article content...');
      expect(article.isLocal, true);
    });
  });

  group('NewsService', () {
    test('instantiates with SupabaseClient', () {
      expect(service, isNotNull);
    });
  });
}
