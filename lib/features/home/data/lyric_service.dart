import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Lyric {
  final String title;
  final String artist;
  final Map<String, String> sections;

  Lyric({required this.title, required this.artist, required this.sections});

  factory Lyric.fromJson(Map<String, dynamic> json) {
    return Lyric(
      title: json['title'],
      artist: json['artist'],
      sections: Map<String, String>.from(json['sections']),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    'sections': sections,
  };
}

class LyricService {
  Future<Lyric> getCurrentSong() async {
    const cacheKey = 'current_lyric';
    final prefs = await SharedPreferences.getInstance();

    // Mock Fetch (Simulate API)
    try {
      // In a real app, this would be http.get(...)
      await Future.delayed(const Duration(milliseconds: 500));
      
      final mockData = {
        'title': 'GOODNESS OF GOD',
        'artist': 'Bethel Music',
        'sections': {
          'VERSE 1': "I love You, Lord\nFor Your mercy never fails me\nAll my days, I've been held in Your hands\nFrom the moment that I wake up\nUntil I lay my head\nI will sing of the goodness of God",
          'CHORUS': "All my life You have been faithful\nAll my life You have been so, so good\nWith every breath that I am able\nI will sing of the goodness of God",
        }
      };

      await prefs.setString(cacheKey, json.encode(mockData));
      return Lyric.fromJson(mockData);
    } catch (e) {
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        return Lyric.fromJson(json.decode(cached));
      }
      rethrow;
    }
  }
}

final lyricServiceProvider = Provider((ref) => LyricService());

final currentLyricProvider = FutureProvider<Lyric>((ref) async {
  return ref.watch(lyricServiceProvider).getCurrentSong();
});
