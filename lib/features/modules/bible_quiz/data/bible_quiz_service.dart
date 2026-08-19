import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';

class QuizQuestion {
  final String id;
  final String question;
  final List<String> options;
  final int correctAnswer;
  final List<int> correctAnswers;
  final String difficulty;
  final String category;
  final String? scriptureReference;
  final String? style;
  final int points;
  final bool isSuperadminOnly;
  final String type;

  QuizQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctAnswer,
    this.correctAnswers = const [],
    required this.difficulty,
    required this.category,
    this.scriptureReference,
    this.style,
    this.points = 10,
    this.isSuperadminOnly = false,
    this.type = 'choice',
  });

  factory QuizQuestion.fromMap(Map<String, dynamic> map) {
    final type = map['type'] as String? ?? 'choice';
    final ca = map['correct_answer'];
    final cas = map['correct_answers'];
    List<int> parsedCorrectAnswers = [];
    if (cas != null) {
      if (cas is List) {
        parsedCorrectAnswers = cas.map((e) => (e as num).toInt()).toList();
      } else if (cas is Map && cas['answers'] is List) {
        parsedCorrectAnswers = (cas['answers'] as List).map((e) => (e as num).toInt()).toList();
      }
    }
    final int singleCorrect = ca != null ? (ca as num).toInt() : (parsedCorrectAnswers.isNotEmpty ? parsedCorrectAnswers.first : 0);
    return QuizQuestion(
      id: map['id']?.toString() ?? '',
      question: map['question'] ?? '',
      options: List<String>.from(map['options'] ?? []),
      correctAnswer: singleCorrect,
      correctAnswers: parsedCorrectAnswers,
      difficulty: map['difficulty'] ?? 'Medium',
      category: map['category'] ?? 'General',
      scriptureReference: map['scripture_reference'],
      style: map['style'],
      points: map['points'] ?? 10,
      isSuperadminOnly: map['is_superadmin_only'] == true,
      type: type,
    );
  }

  bool get isMultipleAnswer =>
      type == 'multiple' || type == 'all_that_apply' || correctAnswers.length > 1;
}

class QuizSessionResult {
  final List<QuizQuestion> questions;
  final List<int?> answers; // null = skipped
  final List<int> responseTimesMs;
  final int streak;
  final int powerUpsUsed;
  final int? opponentScore;
  final String? opponentName;
  final String? opponentAvatar;
  final String? opponentChurch;

  QuizSessionResult({
    required this.questions,
    required this.answers,
    required this.responseTimesMs,
    required this.streak,
    required this.powerUpsUsed,
    this.opponentScore,
    this.opponentName,
    this.opponentAvatar,
    this.opponentChurch,
  });

  int get score {
    int s = 0;
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      final a = answers[i];
      if (q.isMultipleAnswer) {
        if (a != null && a >= 0 && q.correctAnswers.contains(a)) {
          s += q.points;
        }
      } else {
        if (a == q.correctAnswer) {
          s += q.points;
        }
      }
    }
    return s;
  }

  int get maxScore =>
      questions.fold(0, (sum, q) => sum + q.points);

  double get accuracy => questions.isEmpty
      ? 0
      : answers.where((a) => a != null).length / questions.length;

  double get correctRate {
    if (questions.isEmpty) return 0;
    int correct = 0;
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      final a = answers[i];
      if (q.isMultipleAnswer) {
        if (a != null && a >= 0 && q.correctAnswers.contains(a)) correct++;
      } else {
        if (a == q.correctAnswer) correct++;
      }
    }
    return correct / questions.length;
  }

  List<QuizQuestion> get wrongQuestions {
    final list = <QuizQuestion>[];
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      final a = answers[i];
      bool isWrong;
      if (q.isMultipleAnswer) {
        isWrong = a == null || a < 0 || !q.correctAnswers.contains(a);
      } else {
        isWrong = a != q.correctAnswer;
      }
      if (isWrong) list.add(q);
    }
    return list;
  }

  Duration get averageResponseTime {
    if (responseTimesMs.isEmpty) return Duration.zero;
    return Duration(
      milliseconds: responseTimesMs.reduce((a, b) => a + b) ~/
          responseTimesMs.length,
    );
  }
}

class BibleQuizService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Fetches unseen questions for the current user via RPC.
  /// Falls back to random questions if the RPC fails or returns insufficient results.
  Future<List<QuizQuestion>> getUnseenQuestions(
    int count, {
    String? category,
    String? difficulty,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return getRandomQuestions(count, category: category, difficulty: difficulty);
    }

    try {
      final res = await _client.rpc('get_unseen_questions', params: {
        'p_user_id': userId,
        'p_count': count,
        'p_category': category,
        'p_difficulty': difficulty,
        'p_exclude_superadmin': true,
      });

      if (res is List && res.isNotEmpty) {
        final questions = res.map((e) => QuizQuestion.fromMap(e as Map<String, dynamic>)).toList();
        if (questions.length >= count) return questions.take(count).toList();
        _triggerAutoGenerateIfNeeded(category: category, difficulty: difficulty);
        // Pad to the requested count with seed-bank questions (dedup by id)
        // so competitive styles (Marathon 40, Blitz 30, ...) never run short.
        final seen = questions.map((q) => q.id).toSet();
        final padding = getFallbackQuestions(
          count,
          category: category,
          difficulty: difficulty,
        ).where((q) => !seen.contains(q.id)).take(count - questions.length).toList();
        return [...questions, ...padding];
      }
    } catch (e) {
      debugPrint("Error fetching unseen questions: $e");
    }

    // If unseen pool exhausted, try random (still fresh for this context)
    final randomResult = await getRandomQuestions(count, category: category, difficulty: difficulty);
    if (randomResult.length >= count) return randomResult.take(count).toList();

    // If random returns too few, trigger auto-generation in background
    if (randomResult.length < count) {
      _triggerAutoGenerateIfNeeded(category: category, difficulty: difficulty);
    }

    // Immediate fallback to seed bank — never leave user stranded
    return getFallbackQuestions(count, category: category, difficulty: difficulty);
  }

  /// Triggers question auto-generation in the background (fire-and-forget).
  void _triggerAutoGenerateIfNeeded({String? category, String? difficulty}) async {
    try {
      final session = _client.auth.currentSession;
      if (session == null) return;

      final totalRes = await _client.rpc('get_question_bank_stats');
      final total = (totalRes is Map<String, dynamic>) ? (totalRes['total'] as int? ?? 0) : 0;

      // Only auto-generate if total pool is under 200 questions
      if (total >= 200) return;

      debugPrint('[BibleQuiz] Auto-generating questions (pool: $total)');
      // Fire and forget — don't await
      http.post(
        Uri.parse('${Env.supabaseUrl}/functions/v1/generate-quiz-batch'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': Env.supabaseAnonKey,
        },
        body: jsonEncode({
          'count': 100,
          'category': category,
          'difficulty': difficulty,
          'auto': true,
        }),
      ).then((res) {
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          debugPrint('[BibleQuiz] Auto-generated ${data['inserted'] ?? 0} questions');
        }
      }).catchError((e) {
        debugPrint('[BibleQuiz] Auto-generate failed: $e');
      });
    } catch (_) {
      // Ignore — auto-generation is best-effort
    }
  }

  Future<List<QuizQuestion>> getRandomQuestions(
    int count, {
    String? category,
    String? difficulty,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      bool canSeeSuperadmin = false;
      if (userId != null) {
        final profileRes = await _client
            .from('profiles')
            .select('role')
            .eq('id', userId)
            .maybeSingle();
        final role = profileRes?['role'] ?? 'member';
        canSeeSuperadmin = role == 'superadmin' || role == 'coa_employee';
      }

      var query = _client.from('quiz_questions').select();

      if (!canSeeSuperadmin) {
        query = query.eq('is_superadmin_only', false);
      }
      if (category != null) {
        query = query.eq('category', category);
      }
      if (difficulty != null) {
        query = query.eq('difficulty', difficulty);
      }

      final res = await query.limit(count * 3);

      final questions =
          (res as List).map((e) => QuizQuestion.fromMap(e)).toList();
      if (questions.isNotEmpty) {
        questions.shuffle();
        return questions.take(count).toList();
      }
    } catch (e) {
      debugPrint("Error fetching questions: $e");
    }
    return getFallbackQuestions(count, category: category, difficulty: difficulty);
  }

  /// Returns the total number of questions in the bank.
  Future<int> getQuestionBankTotal() async {
    try {
      final res = await _client
          .from('quiz_questions')
          .select('id')
          .eq('is_superadmin_only', false);
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// Records answered questions for per-user deduplication.
  Future<void> recordAnsweredQuestions({
    required List<String> questionIds,
    String? matchId,
    String? eventId,
    List<bool>? isCorrect,
    List<int>? responseTimesMs,
    List<int>? answers,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _client.rpc('record_answered_questions', params: {
        'p_user_id': userId,
        'p_question_ids': questionIds,
        'p_match_id': matchId,
        'p_event_id': eventId,
        'p_is_correct': isCorrect,
        'p_response_times_ms': responseTimesMs,
        'p_answers': answers,
      });
    } catch (e) {
      debugPrint('Failed to record answered questions: $e');
    }
  }

  List<QuizQuestion> getFallbackQuestions(
    int count, {
    String? category,
    String? difficulty,
  }) {
    final all = _fallbackBank;
    var filtered = all;
    if (category != null) {
      filtered = filtered.where((q) => q.category == category).toList();
    }
    if (difficulty != null) {
      filtered = filtered.where((q) => q.difficulty == difficulty).toList();
    }
    if (filtered.length < count) filtered = all;
    filtered.shuffle();
    return filtered.take(count).toList();
  }

  Future<int> seedQuestions() async {
    final user = _client.auth.currentUser;
    if (user == null) return 0;

    final profileRes = await _client
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    final role = profileRes?['role'] ?? 'member';
    if (role != 'superadmin' && role != 'coa_employee') {
      throw 'Permission denied: Only Superadmins or COA Employees can seed questions.';
    }

    int seeded = 0;
    for (final q in _seedBank) {
      try {
        await _client.from('quiz_questions').upsert(q, onConflict: 'question');
        seeded++;
      } catch (e) {
        debugPrint('Could not seed question "${q['question']}": $e');
      }
    }
    debugPrint('Seeded $seeded questions successfully.');
    return seeded;
  }

  Future<Map<String, dynamic>> findOpponent() async {
    try {
      final res = await _client
          .from('profiles')
          .select('full_name, avatar_url, id')
          .neq('id', _client.auth.currentUser?.id ?? '')
          .limit(10);

      if (res.isNotEmpty) {
        final list = List<Map<String, dynamic>>.from(res);
        list.shuffle();
        return {
          "name": list.first['full_name'],
          "id": list.first['id'],
          "avatar": list.first['avatar_url']?.toString() ?? '',
        };
      }
    } catch (e) {
      debugPrint('Failed to fetch random opponent, using mock: $e');
    }
    return {
      "name": "Brother Samuel",
      "id": "mock_opp",
      "avatar": '',
    };
  }

  static const List<Map<String, dynamic>> _seedBank = [
    // ========== EASY QUESTIONS (Level 1-3) ==========
    {'question': 'Who was the first man created by God?', 'options': ['Adam', 'Cain', 'Abel', 'Seth'], 'correct_answer': 0, 'points': 10, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 2:7', 'is_superadmin_only': false},
    {'question': 'Who was the first woman?', 'options': ['Eve', 'Sarah', 'Rebekah', 'Leah'], 'correct_answer': 0, 'points': 10, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 3:20', 'is_superadmin_only': false},
    {'question': 'Who built the ark?', 'options': ['Moses', 'Noah', 'Abraham', 'David'], 'correct_answer': 1, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 6:14', 'is_superadmin_only': false},
    {'question': 'How many days did it rain during the great flood?', 'options': ['20 days', '30 days', '40 days', '50 days'], 'correct_answer': 2, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 7:17', 'is_superadmin_only': false},
    {'question': 'How many commandments did God give to Moses?', 'options': ['5', '7', '10', '12'], 'correct_answer': 2, 'points': 10, 'category': 'Law', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Exodus 20', 'is_superadmin_only': false},
    {'question': 'Who was sold into slavery by his brothers?', 'options': ['Moses', 'Abraham', 'Joseph', 'David'], 'correct_answer': 2, 'points': 10, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 37:28', 'is_superadmin_only': false},
    {'question': 'What giant did David defeat with a sling?', 'options': ['Og', 'Goliath', 'Sihon', 'Samson'], 'correct_answer': 1, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': '1 Samuel 17:50', 'is_superadmin_only': false},
    {'question': 'Who was swallowed by a large fish?', 'options': ['Elijah', 'Jonah', 'Hosea', 'Daniel'], 'correct_answer': 1, 'points': 10, 'category': 'Prophecy', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Jonah 1:17', 'is_superadmin_only': false},
    {'question': 'How many disciples did Jesus choose?', 'options': ['10', '11', '12', '13'], 'correct_answer': 2, 'points': 10, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Matthew 10:1', 'is_superadmin_only': false},
    {'question': 'Who betrayed Jesus Christ?', 'options': ['Peter', 'James', 'John', 'Judas Iscariot'], 'correct_answer': 3, 'points': 10, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Matthew 26:48', 'is_superadmin_only': false},
    {'question': 'In which city was Jesus born?', 'options': ['Jerusalem', 'Nazareth', 'Bethlehem', 'Jericho'], 'correct_answer': 2, 'points': 10, 'category': 'NT', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Luke 2:4', 'is_superadmin_only': false},
    {'question': 'Who baptized Jesus in the Jordan River?', 'options': ['Peter', 'John the Baptist', 'James', 'Philip'], 'correct_answer': 1, 'points': 10, 'category': 'NT', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Matthew 3:13', 'is_superadmin_only': false},
    {'question': "What was Jesus's first miracle?", 'options': ['Walking on water', 'Feeding 5000', 'Turning water to wine', 'Healing a blind man'], 'correct_answer': 2, 'points': 10, 'category': 'Miracles', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'John 2:11', 'is_superadmin_only': false},
    {'question': 'On which day did Jesus rise from the dead?', 'options': ['First day', 'Second day', 'Third day', 'Fourth day'], 'correct_answer': 2, 'points': 10, 'category': 'NT', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Luke 24:7', 'is_superadmin_only': false},
    {'question': 'How many books are in the entire Bible?', 'options': ['64', '66', '68', '70'], 'correct_answer': 1, 'points': 10, 'category': 'Scripture', 'difficulty': 'Easy', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'Who was the first king of Israel?', 'options': ['David', 'Solomon', 'Saul', 'Samuel'], 'correct_answer': 2, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': '1 Samuel 10:1', 'is_superadmin_only': false},
    {'question': 'What did God create on the first day?', 'options': ['Water', 'Light', 'Sky', 'Animals'], 'correct_answer': 1, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 1:3', 'is_superadmin_only': false},
    {'question': 'Who was the mother of Jesus?', 'options': ['Martha', 'Mary', 'Elizabeth', 'Anna'], 'correct_answer': 1, 'points': 10, 'category': 'NT', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Luke 1:31', 'is_superadmin_only': false},
    {'question': 'What did God create on the second day?', 'options': ['Light', 'Sky / Firmament', 'Land', 'Stars'], 'correct_answer': 1, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 1:6', 'is_superadmin_only': false},
    {'question': 'What kind of tree did Adam and Eve eat from?', 'options': ['Tree of Life', 'Tree of Knowledge', 'Olive Tree', 'Fig Tree'], 'correct_answer': 1, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 2:17', 'is_superadmin_only': false},
    {'question': 'Who was Abraham\'s wife?', 'options': ['Hagar', 'Sarah', 'Rebekah', 'Rachel'], 'correct_answer': 1, 'points': 10, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 17:15', 'is_superadmin_only': false},
    {'question': 'Which sea did the Israelites cross on dry ground?', 'options': ['Mediterranean Sea', 'Red Sea', 'Sea of Galilee', 'Dead Sea'], 'correct_answer': 1, 'points': 10, 'category': 'Miracles', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Exodus 14:22', 'is_superadmin_only': false},
    {'question': 'What did God provide from heaven for the Israelites in the wilderness?', 'options': ['Bread', 'Quail', 'Manna', 'Fish'], 'correct_answer': 2, 'points': 10, 'category': 'Miracles', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Exodus 16:15', 'is_superadmin_only': false},
    {'question': 'Where did Jesus grow up?', 'options': ['Jerusalem', 'Bethlehem', 'Nazareth', 'Capernaum'], 'correct_answer': 2, 'points': 10, 'category': 'NT', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Matthew 2:23', 'is_superadmin_only': false},
    {'question': 'What did Jesus feed 5000 people with?', 'options': ['5 loaves and 2 fish', '7 loaves and 3 fish', '10 loaves and 5 fish', '3 loaves and 4 fish'], 'correct_answer': 0, 'points': 10, 'category': 'Miracles', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Matthew 14:17', 'is_superadmin_only': false},
    {'question': 'Who was the first apostle to be martyred?', 'options': ['Peter', 'James', 'John', 'Stephen'], 'correct_answer': 1, 'points': 10, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Acts 12:2', 'is_superadmin_only': false},
    {'question': 'What did God send to destroy Sodom and Gomorrah?', 'options': ['Earthquake', 'Flood', 'Fire and brimstone', 'Plague'], 'correct_answer': 2, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 19:24', 'is_superadmin_only': false},
    {'question': 'Who was Moses\' brother?', 'options': ['Aaron', 'Joshua', 'Caleb', 'Miriam'], 'correct_answer': 0, 'points': 10, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Exodus 4:14', 'is_superadmin_only': false},
    {'question': 'What did Samson use to kill 1000 Philistines?', 'options': ['Sword', 'Spear', 'Donkey jawbone', 'Sling'], 'correct_answer': 2, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Judges 15:15', 'is_superadmin_only': false},
    {'question': 'On what mountain did Moses receive the Ten Commandments?', 'options': ['Mount Carmel', 'Mount Sinai', 'Mount Zion', 'Mount Horeb'], 'correct_answer': 1, 'points': 10, 'category': 'Law', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Exodus 19:20', 'is_superadmin_only': false},
    {'question': 'What was the first plague of Egypt?', 'options': ['Frogs', 'Darkness', 'Water turned to blood', 'Locusts'], 'correct_answer': 2, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Exodus 7:20', 'is_superadmin_only': false},
    {'question': 'Who was Ruth\'s mother-in-law?', 'options': ['Orpah', 'Naomi', 'Esther', 'Leah'], 'correct_answer': 1, 'points': 10, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Ruth 1:4', 'is_superadmin_only': false},
    {'question': 'Which book is known as "The Song of Solomon"?', 'options': ['Psalms', 'Song of Solomon', 'Ecclesiastes', 'Proverbs'], 'correct_answer': 1, 'points': 10, 'category': 'Scripture', 'difficulty': 'Easy', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'How many days was Jesus in the wilderness?', 'options': ['20 days', '30 days', '40 days', '50 days'], 'correct_answer': 2, 'points': 10, 'category': 'NT', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Matthew 4:2', 'is_superadmin_only': false},
    {'question': 'Who wrote the first five books of the Bible?', 'options': ['Abraham', 'Moses', 'Joshua', 'Samuel'], 'correct_answer': 1, 'points': 10, 'category': 'Scripture', 'difficulty': 'Easy', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'What did Joseph\'s brothers do to him out of jealousy?', 'options': ['Killed him', 'Sold him as a slave', 'Left him in a pit', 'Both B and C'], 'correct_answer': 3, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 37:24-28', 'is_superadmin_only': false},

    // ========== MEDIUM QUESTIONS (Level 4-6) ==========
    {'question': 'What did God use to part the Red Sea?', 'options': ["His hand alone", "Moses's staff", 'A great wind', 'Both B and C'], 'correct_answer': 3, 'points': 20, 'category': 'Miracles', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Exodus 14:21', 'is_superadmin_only': false},
    {'question': 'Which king had 700 wives?', 'options': ['David', 'Solomon', 'Saul', 'Jeroboam'], 'correct_answer': 1, 'points': 20, 'category': 'History', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': '1 Kings 11:3', 'is_superadmin_only': false},
    {'question': 'What language was the original Old Testament primarily written in?', 'options': ['Aramaic', 'Greek', 'Hebrew', 'Latin'], 'correct_answer': 2, 'points': 20, 'category': 'Scripture', 'difficulty': 'Medium', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'How many chapters are in the book of Psalms?', 'options': ['100', '120', '150', '180'], 'correct_answer': 2, 'points': 20, 'category': 'Scripture', 'difficulty': 'Medium', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'Who wrote the majority of the Psalms?', 'options': ['Moses', 'Solomon', 'Asaph', 'David'], 'correct_answer': 3, 'points': 20, 'category': 'People', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Psalm 3:1', 'is_superadmin_only': false},
    {'question': 'Which tribe of Israel did Moses belong to?', 'options': ['Judah', 'Benjamin', 'Levi', 'Ephraim'], 'correct_answer': 2, 'points': 20, 'category': 'People', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Exodus 2:1', 'is_superadmin_only': false},
    {'question': 'What does the word "Hallelujah" mean?', 'options': ['Praise God', 'Thank you Lord', 'Glory forever', 'Holy Spirit'], 'correct_answer': 0, 'points': 20, 'category': 'Language', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Psalm 150:1', 'is_superadmin_only': false},
    {'question': 'Who wrote the Gospel of Luke?', 'options': ['Luke the Apostle', 'Luke the Physician', "Paul's secretary", 'An anonymous author'], 'correct_answer': 1, 'points': 20, 'category': 'Scripture', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Colossians 4:14', 'is_superadmin_only': false},
    {'question': 'How many books are in the New Testament?', 'options': ['24', '25', '27', '29'], 'correct_answer': 2, 'points': 20, 'category': 'Scripture', 'difficulty': 'Medium', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'Who wrote the most books in the New Testament?', 'options': ['Peter', 'John', 'James', 'Paul'], 'correct_answer': 3, 'points': 20, 'category': 'People', 'difficulty': 'Medium', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'What does the name "Jesus" mean in Hebrew?', 'options': ['God saves', 'Son of God', 'King of kings', 'Light of the world'], 'correct_answer': 0, 'points': 20, 'category': 'Language', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Matthew 1:21', 'is_superadmin_only': false},
    {'question': 'Who was the oldest man in the Bible?', 'options': ['Noah', 'Abraham', 'Methuselah', 'Adam'], 'correct_answer': 2, 'points': 20, 'category': 'People', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Genesis 5:27', 'is_superadmin_only': false},
    {'question': 'Which book immediately follows the book of Malachi?', 'options': ['Psalms', 'Isaiah', 'Matthew', 'Genesis'], 'correct_answer': 2, 'points': 20, 'category': 'Scripture', 'difficulty': 'Medium', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'Which apostle was a tax collector before following Jesus?', 'options': ['Peter', 'John', 'Matthew', 'Thomas'], 'correct_answer': 2, 'points': 20, 'category': 'People', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Matthew 9:9', 'is_superadmin_only': false},
    {'question': 'What is the longest book in the Bible?', 'options': ['Isaiah', 'Jeremiah', 'Psalms', 'Genesis'], 'correct_answer': 2, 'points': 20, 'category': 'Scripture', 'difficulty': 'Medium', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'Which city was known as the City of David?', 'options': ['Jerusalem', 'Bethlehem', 'Hebron', 'Nazareth'], 'correct_answer': 0, 'points': 20, 'category': 'History', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': '2 Samuel 5:7', 'is_superadmin_only': false},
    {'question': 'Who anointed David as king?', 'options': ['Samuel', 'Nathan', 'Gad', 'Saul'], 'correct_answer': 0, 'points': 20, 'category': 'History', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': '1 Samuel 16:13', 'is_superadmin_only': false},
    {'question': 'Which prophet was taken to heaven in a whirlwind?', 'options': ['Elisha', 'Elijah', 'Isaiah', 'Ezekiel'], 'correct_answer': 1, 'points': 20, 'category': 'Prophecy', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': '2 Kings 2:11', 'is_superadmin_only': false},
    {'question': 'How many of each clean animal did Noah take on the ark?', 'options': ['2', '7', '5', '12'], 'correct_answer': 1, 'points': 20, 'category': 'History', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Genesis 7:2', 'is_superadmin_only': false},
    {'question': 'Who interpreted Pharaoh\'s dream?', 'options': ['Daniel', 'Joseph', 'Moses', 'Samuel'], 'correct_answer': 1, 'points': 20, 'category': 'People', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Genesis 41:16', 'is_superadmin_only': false},
    {'question': 'What was the name of David\'s close friend (Jonathan\'s son)?', 'options': ['Mephibosheth', 'Absalom', 'Amnon', 'Adonijah'], 'correct_answer': 0, 'points': 20, 'category': 'People', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': '2 Samuel 9:6', 'is_superadmin_only': false},
    {'question': 'How many plagues struck Egypt?', 'options': ['7', '10', '12', '9'], 'correct_answer': 1, 'points': 20, 'category': 'History', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Exodus 7-12', 'is_superadmin_only': false},
    {'question': 'What did Jacob dream about at Bethel?', 'options': ['A burning bush', 'A ladder to heaven', 'A valley of bones', 'A great flood'], 'correct_answer': 1, 'points': 20, 'category': 'History', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Genesis 28:12', 'is_superadmin_only': false},
    {'question': 'Which book contains the "Valley of Dry Bones" vision?', 'options': ['Isaiah', 'Jeremiah', 'Ezekiel', 'Daniel'], 'correct_answer': 2, 'points': 20, 'category': 'Prophecy', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Ezekiel 37:1', 'is_superadmin_only': false},
    {'question': 'What did the wise men from the East bring to Jesus?', 'options': ['Gold, silver, pearls', 'Gold, frankincense, myrrh', 'Gold, oil, spices', 'Gold, gems, perfume'], 'correct_answer': 1, 'points': 20, 'category': 'NT', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Matthew 2:11', 'is_superadmin_only': false},
    {'question': 'Who said "I am the way, the truth, and the life"?', 'options': ['Peter', 'Paul', 'Jesus', 'John'], 'correct_answer': 2, 'points': 20, 'category': 'NT', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'John 14:6', 'is_superadmin_only': false},
    {'question': 'Who was the Ethiopian eunuch baptized by?', 'options': ['Peter', 'John', 'Philip', 'Stephen'], 'correct_answer': 2, 'points': 20, 'category': 'NT', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Acts 8:38', 'is_superadmin_only': false},
    {'question': 'How many days was Jonah inside the fish?', 'options': ['2 days', '3 days', '5 days', '7 days'], 'correct_answer': 1, 'points': 20, 'category': 'Prophecy', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Jonah 1:17', 'is_superadmin_only': false},
    {'question': 'Which disciple doubted Jesus\' resurrection?', 'options': ['Peter', 'James', 'John', 'Thomas'], 'correct_answer': 3, 'points': 20, 'category': 'NT', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'John 20:25', 'is_superadmin_only': false},
    {'question': 'Who was called "the disciple whom Jesus loved"?', 'options': ['Peter', 'John', 'James', 'Matthew'], 'correct_answer': 1, 'points': 20, 'category': 'NT', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'John 21:20', 'is_superadmin_only': false},
    {'question': 'What is the shortest verse in the Bible?', 'options': ['"Jesus wept"', '"He arose"', '"Fear not"', '"Go and sin no more"'], 'correct_answer': 0, 'points': 20, 'category': 'Scripture', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'John 11:35', 'is_superadmin_only': false},
    {'question': 'What day of the week is the Sabbath?', 'options': ['Friday', 'Saturday', 'Sunday', 'Monday'], 'correct_answer': 1, 'points': 20, 'category': 'Law', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Exodus 20:8', 'is_superadmin_only': false},
    {'question': 'Which tribe did Jesus descend from?', 'options': ['Levi', 'Benjamin', 'Judah', 'Ephraim'], 'correct_answer': 2, 'points': 20, 'category': 'NT', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Matthew 1:3', 'is_superadmin_only': false},
    {'question': 'Where did Paul write the letter to the Romans?', 'options': ['Athens', 'Rome', 'Corinth', 'Ephesus'], 'correct_answer': 2, 'points': 20, 'category': 'Scripture', 'difficulty': 'Medium', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'What sign did God give Cain to protect him?', 'options': ['A mark on his forehead', 'A scar on his hand', 'A ring on his finger', 'A mark on his chest'], 'correct_answer': 0, 'points': 20, 'category': 'History', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Genesis 4:15', 'is_superadmin_only': false},

    // ========== HARD QUESTIONS (Level 7-9) ==========
    {'question': 'In which language was most of the New Testament originally written?', 'options': ['Latin', 'Aramaic', 'Koine Greek', 'Hebrew'], 'correct_answer': 2, 'points': 30, 'category': 'Scripture', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'How many chapters does the book of Revelation have?', 'options': ['18', '20', '22', '24'], 'correct_answer': 2, 'points': 30, 'category': 'Prophecy', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'Which angel announced the birth of Jesus to Mary?', 'options': ['Michael', 'Raphael', 'Uriel', 'Gabriel'], 'correct_answer': 3, 'points': 30, 'category': 'Angels', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': 'Luke 1:26', 'is_superadmin_only': false},
    {'question': 'What are the four Gospels in order?', 'options': ['Matthew, Mark, Luke, Acts', 'Matthew, Mark, Luke, John', 'Mark, Luke, John, Acts', 'Matthew, Luke, John, Romans'], 'correct_answer': 1, 'points': 30, 'category': 'Scripture', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'How many times did the Israelites march around Jericho?', 'options': ['7 times on one day', '13 times total', '7 times for 6 days then 7 on the 7th', 'Once'], 'correct_answer': 2, 'points': 30, 'category': 'History', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': 'Joshua 6:3-4', 'is_superadmin_only': false},
    {'question': 'Who wrote the book of Hebrews?', 'options': ['Paul', 'Luke', 'Unknown / Anonymous', 'Peter'], 'correct_answer': 2, 'points': 30, 'category': 'Scripture', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'What did Jesus say on the cross meaning "My God, my God, why have you forsaken me"?', 'options': ['Eloi, Eloi, lema sabachthani', 'Eli, Eli, lama sabachthani', 'Eloi, Eloi, lama sabachthani', 'Eli, Eli, lema sabachthani'], 'correct_answer': 1, 'points': 30, 'category': 'NT', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': 'Matthew 27:46', 'is_superadmin_only': false},
    {'question': 'How many books are in the Apocrypha (Catholic canon)?', 'options': ['7', '10', '12', '15'], 'correct_answer': 0, 'points': 30, 'category': 'Scripture', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'Which king of Israel reigned for only 7 days?', 'options': ['Zimri', 'Shallum', 'Omri', 'Tibni'], 'correct_answer': 0, 'points': 30, 'category': 'History', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': '1 Kings 16:15', 'is_superadmin_only': false},
    {'question': 'What was the name of the angel who fought with Jacob?', 'options': ['Michael', 'Gabriel', 'The Angel of the Lord', 'Unknown / Unnamed'], 'correct_answer': 2, 'points': 30, 'category': 'Angels', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': 'Genesis 32:24', 'is_superadmin_only': false},
    {'question': 'Who wrote the largest portion of Proverbs?', 'options': ['David', 'Solomon', 'Agur', 'Lemuel'], 'correct_answer': 1, 'points': 30, 'category': 'People', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'How many years did the Israelites wander in the wilderness?', 'options': ['20', '30', '40', '50'], 'correct_answer': 2, 'points': 30, 'category': 'History', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': 'Numbers 14:33', 'is_superadmin_only': false},
    {'question': 'What does the Greek word "Ekklesia" mean?', 'options': ['Church / Assembly', 'Congregation', 'Temple', 'Synagogue'], 'correct_answer': 0, 'points': 30, 'category': 'Language', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'Who was the Roman centurion who said "Truly this man was the Son of God"?', 'options': ['Cornelius', 'Longinus', 'Julius', 'Claudius'], 'correct_answer': 0, 'points': 30, 'category': 'NT', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': 'Mark 15:39', 'is_superadmin_only': false},
    {'question': 'In what year did the destruction of Jerusalem occur (AD)?', 'options': ['66 AD', '70 AD', '73 AD', '80 AD'], 'correct_answer': 1, 'points': 30, 'category': 'History', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'Which Old Testament character is mentioned most in the New Testament?', 'options': ['Abraham', 'Moses', 'David', 'Elijah'], 'correct_answer': 2, 'points': 30, 'category': 'Scripture', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': true},
    {'question': 'What is the Tetragrammaton?', 'options': ['YHWH / Yahweh', 'Jesus Christ', 'Holy Spirit', 'Adonai'], 'correct_answer': 0, 'points': 30, 'category': 'Language', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'How many times is the word "faith" mentioned in the Bible?', 'options': ['200+', '300+', '400+', '500+'], 'correct_answer': 1, 'points': 30, 'category': 'Scripture', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': true},
    {'question': 'Who was known as the weeping prophet?', 'options': ['Isaiah', 'Jeremiah', 'Ezekiel', 'Hosea'], 'correct_answer': 1, 'points': 30, 'category': 'Prophecy', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': 'Jeremiah 9:1', 'is_superadmin_only': false},
    {'question': 'Which chapter in the Bible contains the Ten Commandments?', 'options': ['Exodus 19', 'Exodus 20', 'Deuteronomy 4', 'Exodus 24'], 'correct_answer': 1, 'points': 30, 'category': 'Law', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': 'Exodus 20:1-17', 'is_superadmin_only': false},

    // ========== MASTER QUESTIONS (Level 10+, superadmin only) ==========
    {'question': 'What Greek word is translated as "repentance" in the New Testament?', 'options': ['Metanoia', 'Soteria', 'Doxa', 'Agape'], 'correct_answer': 0, 'points': 50, 'category': 'Language', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': true},
    {'question': 'How many times does the word "Trinity" appear in the Bible?', 'options': ['0', '1', '3', '7'], 'correct_answer': 0, 'points': 50, 'category': 'Scripture', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': true},
    {'question': 'Which book of the Bible never mentions God?', 'options': ['Ruth', 'Esther', 'Song of Solomon', 'Ecclesiastes'], 'correct_answer': 1, 'points': 50, 'category': 'Scripture', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': true},
    {'question': 'What does the name "Ichabod" mean in Hebrew?', 'options': ['The glory has departed', 'God remembers', 'My father is God', 'The Lord will provide'], 'correct_answer': 0, 'points': 50, 'category': 'Language', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': '1 Samuel 4:21', 'is_superadmin_only': true},
    {'question': 'Who is the Silas mentioned in the New Testament?', 'options': ['A Roman soldier', 'Paul\'s companion', 'A church elder', 'Peter\'s scribe'], 'correct_answer': 1, 'points': 50, 'category': 'People', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': 'Acts 15:40', 'is_superadmin_only': true},
    {'question': 'How many generations are between Abraham and David in Matthew\'s genealogy?', 'options': ['12', '14', '16', '10'], 'correct_answer': 1, 'points': 50, 'category': 'Scripture', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': 'Matthew 1:17', 'is_superadmin_only': true},
    {'question': 'Which early church father was a pupil of the Apostle John?', 'options': ['Clement of Rome', 'Ignatius of Antioch', 'Polycarp of Smyrna', 'Irenaeus of Lyons'], 'correct_answer': 2, 'points': 50, 'category': 'People', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': true},
    {'question': 'What is the longest verse in the Bible?', 'options': ['Psalm 119:1', 'Esther 8:9', 'John 11:35', 'Revelation 20:10'], 'correct_answer': 1, 'points': 50, 'category': 'Scripture', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': true},
    {'question': 'How many times was Jerusalem destroyed?', 'options': ['Once', 'Twice', 'Three times', 'Five times'], 'correct_answer': 3, 'points': 50, 'category': 'History', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': true},
    {'question': 'What is the "Hapax Legomenon" in biblical studies?', 'options': ['A word appearing only once', 'A repeated phrase', 'A scribal error', 'A lost book'], 'correct_answer': 0, 'points': 50, 'category': 'Language', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': true},
  ];

  static final List<QuizQuestion> _fallbackBank = _seedBank
      .map((q) => QuizQuestion(
            id: q['question'].toString().hashCode.toString(),
            question: q['question'] as String,
            options: List<String>.from(q['options'] as List),
            correctAnswer: q['correct_answer'] as int,
            difficulty: q['difficulty'] as String,
            category: q['category'] as String,
            scriptureReference: q['scripture_reference'] as String?,
            style: q['style'] as String?,
            points: q['points'] as int,
            isSuperadminOnly: q['is_superadmin_only'] == true,
          ))
      .toList();

  Future<ChurchQuizCompetition?> getCompetitionById(String id) async {
    try {
      final res = await _client.from('church_competitions').select().eq('id', id).maybeSingle();
      if (res == null) return null;
      return ChurchQuizCompetition.fromMap(res);
    } catch (e) {
      debugPrint("Error fetching competition by id: $e");
      return null;
    }
  }

  Future<String?> verifyCompetitionPin(String pin) async {
    try {
      final res = await _client.from('church_competitions').select('id').eq('pin_code', pin).maybeSingle();
      return res?['id']?.toString();
    } catch (e) {
      debugPrint("Error verifying competition PIN: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>?> createChurchCompetition({
    String? tenantId,
    String? organizationId,
    required String title,
    required DateTime date,
    required int questionCount,
    String? difficulty,
    required double entryFee,
  }) async {
    try {
      final pinCode = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
      final data = await _client.from('church_competitions').insert({
        'tenant_id': tenantId,
        'organization_id': organizationId,
        'title': title,
        'scheduled_for': date.toIso8601String(),
        'question_count': questionCount,
        'difficulty': difficulty,
        'entry_fee': entryFee,
        'pin_code': pinCode,
        'status': 'scheduled',
      }).select().single();
      return data;
    } catch (e) {
      debugPrint("Error creating church competition: $e");
      return null;
    }
  }
}

class ChurchQuizCompetition {
  final String id;
  final String title;
  final String pinCode;
  final DateTime scheduledFor;
  final int questionCount;
  final String? difficulty;
  final double entryFee;
  final String? tenantId;
  final String? organizationId;
  final String status;

  ChurchQuizCompetition({
    required this.id,
    required this.title,
    required this.pinCode,
    required this.scheduledFor,
    required this.questionCount,
    this.difficulty,
    this.entryFee = 0.0,
    this.tenantId,
    this.organizationId,
    this.status = 'scheduled',
  });

  bool get isFree => entryFee == 0;
  DateTime get date => scheduledFor;

  factory ChurchQuizCompetition.fromMap(Map<String, dynamic> map) {
    return ChurchQuizCompetition(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      pinCode: map['pin_code']?.toString() ?? '',
      scheduledFor: map['scheduled_for'] != null
          ? DateTime.parse(map['scheduled_for'].toString())
          : DateTime.now(),
      questionCount: map['question_count'] ?? 10,
      difficulty: map['difficulty'],
      entryFee: (map['entry_fee'] as num?)?.toDouble() ?? 0.0,
      tenantId: map['tenant_id']?.toString(),
      organizationId: map['organization_id']?.toString(),
      status: map['status']?.toString() ?? 'scheduled',
    );
  }
}

final bibleQuizServiceProvider = Provider((ref) => BibleQuizService());

/// Global Church Coin leaderboard: ALL tenants, ranked by CC balance.
/// "Public" players = registered church members who haven't opted out
/// (profiles.hide_from_leaderboard).
final quizLeaderboardProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = Supabase.instance.client;
  try {
    final res = await client.rpc('get_quiz_cc_leaderboard', params: {
      'p_limit': 50,
      'p_min_coins': 0,
    });
    return List<Map<String, dynamic>>.from(res as List);
  } catch (_) {
    return [];
  }
});

final myQuizRankProvider = FutureProvider<String>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return "N/A";

  try {
    final res = await client.rpc('get_quiz_cc_leaderboard', params: {
      'p_limit': 1000,
      'p_min_coins': 0,
    });
    final list = List<Map<String, dynamic>>.from(res as List);
    int rank = list.indexWhere((p) => p['user_id'] == user.id) + 1;
    return rank > 0 ? "#$rank" : "N/A";
  } catch (_) {
    return "N/A";
  }
});

/// Whether the current user may manage quiz content (superadmin / coa_employee
/// / employee / any member of a Quiz Engine leasing church).
final canManageQuizContentProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final client = Supabase.instance.client;
  try {
    final res = await client.rpc('can_manage_quiz_content');
    final data = res is Map<String, dynamic> ? res : <String, dynamic>{};
    return data['allowed'] == true;
  } catch (_) {
    return false;
  }
});
