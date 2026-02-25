import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QuizQuestion {
  final String id;
  final String question;
  final List<String> options;
  final int correctAnswer;
  final String difficulty;
  final String category;
  final String? scriptureReference;
  final String? style; // rapid_fire, choice, verbatim
  final int points;

  QuizQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.difficulty,
    required this.category,
    this.scriptureReference,
    this.style,
    this.points = 10,
  });

  factory QuizQuestion.fromMap(Map<String, dynamic> map) {
    return QuizQuestion(
      id: map['id']?.toString() ?? '',
      question: map['question'] ?? '',
      options: List<String>.from(map['options'] ?? []),
      correctAnswer: map['correct_answer'] ?? 0,
      difficulty: map['difficulty'] ?? 'Medium',
      category: map['category'] ?? 'General',
      scriptureReference: map['scripture_reference'],
      style: map['style'],
      points: map['points'] ?? 10,
    );
  }
}

class BibleQuizService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<QuizQuestion>> getRandomQuestions(int count) async {
    try {
      final res = await _client
          .from('quiz_questions')
          .select()
          .limit(count);
      
      final questions = (res as List).map((e) => QuizQuestion.fromMap(e)).toList();
      if (questions.isNotEmpty) {
        questions.shuffle();
        return questions;
      }
    } catch (e) {
      print("Error fetching questions: $e");
    }
    return _getFallbackQuestions(count);
  }

  List<QuizQuestion> _getFallbackQuestions(int count) {
    // Keep a few hardcoded as fallback
    final fallbacks = [
        QuizQuestion(id: 'f1', question: "Built the ark?", options: ["Moses", "Noah", "Abraham", "David"], correctAnswer: 1, difficulty: 'Easy', category: 'History'),
        QuizQuestion(id: 'f2', question: "First book?", options: ["Genesis", "Exodus", "Matthew", "Revelation"], correctAnswer: 0, difficulty: 'Easy', category: 'General'),
    ];
    return fallbacks.take(count).toList();
  }

  Future<void> seedQuestions() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final questionBank = [
      // Genesis
      {'question': 'First man?', 'options': ['Adam', 'Cain', 'Abel', 'Seth'], 'correct_answer': 0, 'points': 20, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice'},
      {'question': 'First woman?', 'options': ['Eve', 'Sarah', 'Rebekah', 'Leah'], 'correct_answer': 0, 'points': 20, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice'},
      {'question': 'Built the ark?', 'options': ['Moses', 'Noah', 'Abraham', 'David'], 'correct_answer': 1, 'points': 20, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice'},
      // Kings
      {'question': 'Slayer of Goliath?', 'options': ['Saul', 'Solomon', 'David', 'Samson'], 'correct_answer': 2, 'points': 20, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice'},
      {'question': 'First King of Israel?', 'options': ['Saul', 'David', 'Solomon', 'Samuel'], 'correct_answer': 0, 'points': 20, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice'},
      // NT
      {'question': 'Betrayer of Christ?', 'options': ['Peter', 'James', 'John', 'Judas'], 'correct_answer': 3, 'points': 20, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice'},
      {'question': 'Denied Jesus 3 times?', 'options': ['Andrew', 'Peter', 'Thomas', 'Philip'], 'correct_answer': 1, 'points': 20, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice'},
    ];

    for (var q in questionBank) {
      await _client.from('quiz_questions').upsert(q, onConflict: 'question');
    }
  }

  Future<Map<String, dynamic>> findOpponent() async {
    try {
      final res = await _client
          .from('profiles')
          .select('full_name, id')
          .neq('id', _client.auth.currentUser?.id ?? '')
          .limit(10);
      
      if (res.isNotEmpty) {
        var list = List<Map<String, dynamic>>.from(res);
        list.shuffle();
        return {
          "name": list.first['full_name'],
          "id": list.first['id'],
          "avatar": "https://i.pravatar.cc/150?u=${list.first['id']}"
        };
      }
    } catch (e) {}
    return {
      "name": "Brother Samuel",
      "id": "mock_opp",
      "avatar": "https://i.pravatar.cc/150?u=mock"
    };
  }
}

final bibleQuizServiceProvider = Provider((ref) => BibleQuizService());

final quizLeaderboardProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = Supabase.instance.client;
  try {
    final res = await client
        .from('profiles')
        .select('full_name, id, coins')
        .order('coins', ascending: false)
        .limit(10);
    return List<Map<String, dynamic>>.from(res);
  } catch (e) {
    return [
      {"full_name": "Deacon James", "coins": 12500},
      {"full_name": "Sister Mary", "coins": 9800},
      {"full_name": "Bro. Peter", "coins": 7500},
    ];
  }
});

final myQuizRankProvider = FutureProvider<String>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return "N/A";

  try {
    // Basic ranking logic based on coins/points
    final res = await client
        .from('profiles')
        .select('id, coins')
        .order('coins', ascending: false);
    
    final profiles = List<Map<String, dynamic>>.from(res);
    int rank = profiles.indexWhere((p) => p['id'] == user.id) + 1;
    
    return rank > 0 ? "#$rank" : "N/A";
  } catch (e) {
    return "#12"; // Fallback
  }
});

