import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    try {
      final response = await http.get(
        Uri.parse('https://bible-api.com/$book+$chapter?translation=$translation'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List versesJson = data['verses'];
        return versesJson.map((v) => BibleVerse.fromJson(v)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching Bible chapter: $e');
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
