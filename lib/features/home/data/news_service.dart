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
      // Feeds put the thumbnail in wildly different places — check them all,
      // otherwise global news rendered as a wall of grey placeholders.
      image: _firstNonEmpty([
        json['thumbnail'],
        json['enclosure']?['thumbnail'],
        json['enclosure']?['link'],
        json['media']?['content']?['url'],
        _extractImage(json['content'] ?? ''),
        _extractImage(json['content:encoded'] ?? ''),
        _extractImage(json['description'] ?? ''),
      ]),
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
    if (match != null) return match.group(1);
    // Also cover <media:content url="…"> and <media:thumbnail url="…">.
    final mediaRegex = RegExp(
        r'<(?:media:content|media:thumbnail)[^>]+url="([^">]+)"',
        caseSensitive: false);
    return mediaRegex.firstMatch(description)?.group(1);
  }

  static String _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = (c ?? '').toString().trim();
      if (s.isNotEmpty && s != 'null') return s;
    }
    return '';
  }
}

class NewsService {
  final SupabaseClient _client;
  NewsService(this._client);

  Future<List<NewsArticle>> getPublicNews() async {
    const cacheKey = 'public_news_cache_v1';
    const rssUrl = 'https://news.google.com/rss/search?q=Global+Christian+Church+News&hl=en-US&gl=US&ceid=US:en';

    // 1) Primary: rss2json (JSON, fast). Free tier is rate-limited per day.
    final viaRss2Json = await _fetchViaRss2Json(rssUrl);
    if (viaRss2Json.isNotEmpty) {
      await _writeCache(cacheKey, viaRss2Json);
      return viaRss2Json;
    }

    // 2) Fallback: raw RSS XML through a CORS proxy, parsed with a regex.
    //    Never depends on rss2json's daily quota.
    final viaRawXml = await _fetchViaRawRss(rssUrl);
    if (viaRawXml.isNotEmpty) {
      await _writeCache(cacheKey, viaRawXml);
      return viaRawXml;
    }

    // 3) Fallback: last successful feed (works offline).
    final cached = await _readCache(cacheKey);
    if (cached.isNotEmpty) return cached;

    // 4) Last resort: curated static items so the section is never blank.
    return _curatedFallback();
  }

  Future<List<NewsArticle>> _fetchViaRss2Json(String rssUrl) async {
    try {
      final apiUrl =
          'https://api.rss2json.com/v1/api.json?rss_url=${Uri.encodeComponent(rssUrl)}';
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'ok') {
          final List items = data['items'];
          return items
              .asMap()
              .entries
              .map((e) => NewsArticle.fromJson(e.value, e.key))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('getPublicNews rss2json failed (non-fatal): $e');
    }
    return [];
  }

  Future<List<NewsArticle>> _fetchViaRawRss(String rssUrl) async {
    const proxies = [
      'https://api.allorigins.win/raw?url=',
      'https://corsproxy.io/?',
    ];
    for (final proxy in proxies) {
      try {
        final response = await http
            .get(Uri.parse('$proxy${Uri.encodeComponent(rssUrl)}'))
            .timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final parsed = _parseRssXml(response.body);
          if (parsed.isNotEmpty) return parsed;
        }
      } catch (e) {
        debugPrint('getPublicNews raw rss via $proxy failed (non-fatal): $e');
      }
    }
    return [];
  }

  /// Minimal RSS/Atom parser — extracts `<item>` (RSS) or `<entry>` (Atom)
  /// blocks. Avoids adding an XML dependency; good enough for headline feeds.
  List<NewsArticle> _parseRssXml(String xml) {
    final articles = <NewsArticle>[];
    final itemRegex = RegExp(
      r'<(item|entry)\b[\s\S]*?</\1>',
      caseSensitive: false,
    );
    final blocks = itemRegex.allMatches(xml).toList();
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i].group(0) ?? '';
      final title = _tag(block, 'title');
      if (title.isEmpty) continue;
      final link = _tag(block, 'link') .isNotEmpty
          ? _tag(block, 'link')
          : _attr(block, 'link', 'href');
      final description =
          _tag(block, 'description').isNotEmpty ? _tag(block, 'description') : _tag(block, 'summary');
      final pubDate = _tag(block, 'pubDate').isNotEmpty
          ? _tag(block, 'pubDate')
          : _tag(block, 'updated');
      // Google News / most CMS feeds carry the image in media:content or
      // media:thumbnail rather than <enclosure>.
      final image = _firstOf([
        _attr(block, 'enclosure', 'url'),
        _attr(block, 'media:content', 'url'),
        _attr(block, 'media:thumbnail', 'url'),
        _attr(block, 'content', 'url'),
        NewsArticle._extractImage(description) ?? '',
        NewsArticle._extractImage(_tag(block, 'content:encoded')) ?? '',
      ]);
      articles.add(NewsArticle(
        id: 'rss-$i',
        title: _decode(title),
        source: 'Global News',
        description: _decode(description),
        image: image,
        pubDate: pubDate,
        link: link,
      ));
      if (articles.length >= 20) break;
    }
    return articles;
  }

  /// First non-empty string from a list of candidates.
  static String _firstOf(List<String?> candidates) {
    for (final c in candidates) {
      final s = (c ?? '').trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static String _tag(String block, String tag) {    final m = RegExp(
      '<$tag[^>]*>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    ).firstMatch(block);
    return (m?.group(1) ?? '').replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '').trim();
  }

  static String _attr(String block, String tag, String attr) {
    final m = RegExp(
      '<$tag[^>]*\\b$attr="([^"]*)"',
      caseSensitive: false,
    ).firstMatch(block);
    return (m?.group(1) ?? '').trim();
  }

  static String _decode(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .trim();

  Future<void> _writeCache(String key, List<NewsArticle> articles) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          key, json.encode(articles.map((a) => a.toJson()).toList()));
    } catch (e) {
      debugPrint('news cache write failed (non-fatal): $e');
    }
  }

  Future<List<NewsArticle>> _readCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(key);
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

  /// Static fallback so the Global News section always renders something
  /// useful when every live feed is unreachable/rate-limited.
  List<NewsArticle> _curatedFallback() {
    const sources = [
      ('Christianity Today', 'https://www.christianitytoday.com/'),
      ('Premier Christian News', 'https://premierchristian.news/'),
      ('CBN News', 'https://www1.cbn.com/cbnnews'),
      ('Christian Post', 'https://www.christianpost.com/'),
    ];
    return [
      for (var i = 0; i < sources.length; i++)
        NewsArticle(
          id: 'curated-$i',
          title: 'Visit ${sources[i].$1} for the latest global church news',
          source: sources[i].$1,
          description:
              'Global Christian news and analysis from ${sources[i].$1}.',
          image: '',
          pubDate: '',
          link: sources[i].$2,
        ),
    ];
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
      // Status used to be left NULL, so the writer dashboard counted every
      // published article as zero.
      'status': 'published',
    });

    // Notify church members of new article (fire-and-forget)
    try {
      final author = await _client
          .from('profiles')
          .select('tenant_id')
          .eq('id', authorId)
          .maybeSingle();
      final tenantId = author?['tenant_id']?.toString();
      if (tenantId != null && tenantId.isNotEmpty) {
        _client
            .from('profiles')
            .select('id')
            .eq('tenant_id', tenantId)
            .neq('id', authorId)
            .limit(200)
            .then((members) {
          for (final m in (members as List)) {
            final uid = m['id']?.toString();
            if (uid == null) continue;
            try {
              _client.functions.invoke('push-notifications', body: {
                'userId': uid,
                'title': 'Kingdom News',
                'body': 'New article: "$title" by $authorName',
                'type': 'post',
              });
            } catch (_) {}
          }
        });
      }
    } catch (_) {}
  }
}

final newsServiceProvider = Provider((ref) => NewsService(Supabase.instance.client));

final publicNewsProvider = FutureProvider.autoDispose<List<NewsArticle>>((ref) async {
  return ref.watch(newsServiceProvider).getPublicNews();
});

final newsStreamProvider = StreamProvider<List<NewsArticle>>((ref) {
  return ref.watch(newsServiceProvider).streamNews();
});

