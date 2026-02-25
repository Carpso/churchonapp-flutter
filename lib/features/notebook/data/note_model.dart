import 'package:supabase_flutter/supabase_flutter.dart';

class Note {
  final String id;
  final String userId;
  final String title;
  final String? topic;
  final String content;
  final bool isFavorite;
  final String category;
  final DateTime createdAt;
  final DateTime updatedAt;

  Note({
    required this.id,
    required this.userId,
    required this.title,
    this.topic,
    required this.content,
    this.isFavorite = false,
    this.category = 'general',
    required this.createdAt,
    required this.updatedAt,
  });

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'],
      userId: map['user_id'],
      title: map['title'] ?? 'Untitled',
      topic: map['topic'],
      content: map['content'] ?? '',
      isFavorite: map['is_favorite'] ?? false,
      category: map['category'] ?? 'general',
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'topic': topic,
      'content': content,
      'is_favorite': isFavorite,
      'category': category,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

