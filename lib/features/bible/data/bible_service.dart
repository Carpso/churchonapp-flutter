import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BibleVerse {
  final int chapter;
  final int verse;
  final String text;

  BibleVerse({required this.chapter, required this.verse, required this.text});

  factory BibleVerse.fromJson(Map<String, dynamic> json) {
    return BibleVerse(
      chapter: json['chapter'],
      verse: json['verse'],
      text: json['text'],
    );
  }
}

class BibleService {
  Future<List<BibleVerse>> getChapter(String translation, String book, int chapter) async {
    final cacheKey = 'bible_${translation}_${book}_$chapter';
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Try to get from local cache first
      final cachedData = prefs.getString(cacheKey);
      if (cachedData != null) {
        final List versesJson = json.decode(cachedData);
        return versesJson.map((v) => BibleVerse.fromJson(v)).toList();
      }

      final encodedBook = Uri.encodeComponent(book);
      final response = await http.get(
        Uri.parse('https://bible-api.com/$encodedBook+$chapter?translation=$translation'),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List versesJson = data['verses'];
        
        // Save to cache for offline availability
        await prefs.setString(cacheKey, json.encode(versesJson));
        
        return versesJson.map((v) => BibleVerse.fromJson(v)).toList();
      }
      return [];
    } catch (e) {
      print('Bible Offline Mode/Error: $e');
      return [];
    }
  }
}

final bibleServiceProvider = Provider((ref) => BibleService());

final bibleChapterProvider = FutureProvider.family<List<BibleVerse>, Map<String, dynamic>>((ref, params) async {
  return ref.watch(bibleServiceProvider).getChapter(
    params['translation'] ?? 'web',
    params['book'] ?? 'John',
    params['chapter'] ?? 1,
  );
});

