import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('lyrics')
          .select('title, artist, sections')
          .order('created_at', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        await prefs.setString(cacheKey, json.encode(response.first));
        return Lyric.fromJson(response.first);
      } else {
        throw Exception('No lyrics found in database');
      }
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

