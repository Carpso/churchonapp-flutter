import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NewsArticle {
  final String id;
  final String title;
  final String source;
  final String description;
  final String image;
  final String pubDate;
  final String link;

  NewsArticle({
    required this.id,
    required this.title,
    required this.source,
    required this.description,
    required this.image,
    required this.pubDate,
    required this.link,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json, int index) {
    return NewsArticle(
      id: 'news-$index',
      title: json['title'] ?? '',
      source: json['author'] ?? 'Church News',
      description: json['description'] ?? '',
      image: json['enclosure']?['link'] ?? 
             _extractImage(json['description'] ?? '') ?? 
             'https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=800',
      pubDate: json['pubDate'] ?? '',
      link: json['link'] ?? '',
    );
  }

  static String? _extractImage(String description) {
    final imgRegex = RegExp(r'<img[^>]+src="([^">]+)"', caseSensitive: false);
    final match = imgRegex.firstMatch(description);
    return match?.group(1);
  }
}

class NewsService {
  Future<List<NewsArticle>> getPublicNews() async {
    try {
      const rssUrl = 'https://news.google.com/rss/search?q=Global+Christian+Church+News&hl=en-US&gl=US&ceid=US:en';
      final apiUrl = 'https://api.rss2json.com/v1/api.json?rss_url=${Uri.encodeComponent(rssUrl)}';
      
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'ok') {
          final List items = data['items'];
          return items.asMap().entries.map((e) => NewsArticle.fromJson(e.value, e.key)).toList();
        }
      }
      return [];
    } catch (e) {
      print('Error fetching news: $e');
      return [];
    }
  }
}

final newsServiceProvider = Provider((ref) => NewsService());

final newsProvider = FutureProvider<List<NewsArticle>>((ref) async {
  return ref.watch(newsServiceProvider).getPublicNews();
});
