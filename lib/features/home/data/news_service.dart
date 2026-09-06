import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toJson() => {
        'title': title,
        'source': source,
        'description': description,
        'content': content,
        'image': image,
        'pubDate': pubDate,
        'link': link,
      };

  factory NewsArticle.fromCacheJson(Map<String, dynamic> json) {
    return NewsArticle(
      id: json['id']?.toString() ?? 'news-cached-${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] ?? '',
      source: json['source'] ?? 'Church News',
      description: json['description'] ?? '',
      content: json['content'] ?? '',
      image: json['image'] ?? '',
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
  final SupabaseClient _client;
  NewsService(this._client);

  Future<List<NewsArticle>> getPublicNews() async {
    const cacheKey = 'public_news_cache_v1';
    try {
      const rssUrl = 'https://news.google.com/rss/search?q=Global+Christian+Church+News&hl=en-US&gl=US&ceid=US:en';
      final apiUrl = 'https://api.rss2json.com/v1/api.json?rss_url=${Uri.encodeComponent(rssUrl)}';

      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'ok') {
          final List items = data['items'];
          final articles = items.asMap().entries.map((e) => NewsArticle.fromJson(e.value, e.key)).toList();
          // Cache the last good feed so the section never disappears when the
          // rss2json free tier (limited requests/day) starts rate-limiting.
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(cacheKey, json.encode(articles.map((a) => a.toJson()).toList()));
          } catch (e) {
            debugPrint('news cache write failed (non-fatal): $e');
          }
          return articles;
        }
      }
    } catch (e) {
      debugPrint('getPublicNews failed (non-fatal): $e');
    }
    // Fall back to the last successful feed.
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        final list = (json.decode(cached) as List)
            .map((e) => NewsArticle.fromCacheJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) return list;
      }
    } catch (e) {
      debugPrint('news cache read failed (non-fatal): $e');
    }
    return [];
  }

  Stream<List<NewsArticle>> streamNews() {
    // NOTE: no `.order()` on the realtime stream — server-side ordering on
    // realtime channels caused refresh loops + a blank/white home section
    // (same root cause as chat/social). Sort + cap client-side instead.
    return _client
        .from('kingdom_news')
        .stream(primaryKey: ['id'])
        .limit(10)
        .map((data) {
      final list = data.map((map) => NewsArticle.fromSupabase(map)).toList()
        ..sort((a, b) => b.pubDate.compareTo(a.pubDate));
      return list.take(10).toList();
    }).handleError((error, stack) {
      debugPrint('news_stream error (non-fatal): $error');
      return <NewsArticle>[];
    });
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

final publicNewsProvider = FutureProvider.autoDispose<List<NewsArticle>>((ref) async {
  return ref.watch(newsServiceProvider).getPublicNews();
});

final newsStreamProvider = StreamProvider<List<NewsArticle>>((ref) {
  return ref.watch(newsServiceProvider).streamNews();
});

