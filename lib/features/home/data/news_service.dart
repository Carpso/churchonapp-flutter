import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NewsArticle {
  final String id;
  final String title;
  final String source;
  final String description;
  final String content;
  final String image;
  final String pubDate;
  final String link;
  final bool isLocal;

  NewsArticle({
    required this.id,
    required this.title,
    required this.source,
    required this.description,
    this.content = '',
    required this.image,
    required this.pubDate,
    required this.link,
    this.isLocal = false,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json, int index) {
    return NewsArticle(
      id: 'news-$index',
      title: json['title'] ?? '',
      source: json['author'] ?? 'Church News',
      description: json['description'] ?? '',
      image: json['enclosure']?['link'] ?? 
             _extractImage(json['description'] ?? '') ?? 
             '',
      pubDate: json['pubDate'] ?? '',
      link: json['link'] ?? '',
    );
  }

  factory NewsArticle.fromSupabase(Map<String, dynamic> map) {
    return NewsArticle(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? '',
      source: map['author_name'] ?? 'Writer',
      description: map['excerpt'] ?? '',
      content: map['content'] ?? '',
      image: map['image_url'] ?? '',
      pubDate: map['created_at'] ?? '',
      link: '',
      isLocal: true,
    );
  }

  static String? _extractImage(String description) {
    final imgRegex = RegExp(r'<img[^>]+src="([^">]+)"', caseSensitive: false);
    final match = imgRegex.firstMatch(description);
    return match?.group(1);
  }
}

class NewsService {
  final SupabaseClient _client;
  NewsService(this._client);

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
      return [];
    }
  }

  Stream<List<NewsArticle>> streamNews() {
    return _client
        .from('kingdom_news')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => data.map((map) => NewsArticle.fromSupabase(map)).toList());
  }

  Future<void> publishArticle({
    required String title,
    required String excerpt,
    required String content,
    required String imageUrl,
    required String authorId,
    required String authorName,
  }) async {
    await _client.from('kingdom_news').insert({
      'title': title,
      'excerpt': excerpt,
      'content': content,
      'image_url': imageUrl,
      'author_id': authorId,
      'author_name': authorName,
    });
  }
}

final newsServiceProvider = Provider((ref) => NewsService(Supabase.instance.client));

final publicNewsProvider = FutureProvider<List<NewsArticle>>((ref) async {
  return ref.watch(newsServiceProvider).getPublicNews();
});

final newsStreamProvider = StreamProvider<List<NewsArticle>>((ref) {
  return ref.watch(newsServiceProvider).streamNews();
});

