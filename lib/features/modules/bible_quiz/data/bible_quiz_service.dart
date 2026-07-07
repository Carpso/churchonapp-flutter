import 'package:flutter/foundation.dart';
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
  final String? style;
  final int points;
  final bool isSuperadminOnly;

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
    this.isSuperadminOnly = false,
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
      isSuperadminOnly: map['is_superadmin_only'] == true,
    );
  }

  bool get isMultipleAnswer =>
      options.where((o) => o.contains(' and ') || o.contains(',')).length > 1;
}

class QuizSessionResult {
  final List<QuizQuestion> questions;
  final List<int?> answers; // null = skipped
  final List<int> responseTimesMs;
  final int streak;
  final int powerUpsUsed;

  QuizSessionResult({
    required this.questions,
    required this.answers,
    required this.responseTimesMs,
    required this.streak,
    required this.powerUpsUsed,
  });

  int get score {
    int s = 0;
    for (int i = 0; i < questions.length; i++) {
      if (answers[i] == questions[i].correctAnswer) {
        s += questions[i].points;
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
      if (answers[i] == questions[i].correctAnswer) correct++;
    }
    return correct / questions.length;
  }

  List<QuizQuestion> get wrongQuestions {
    final list = <QuizQuestion>[];
    for (int i = 0; i < questions.length; i++) {
      if (answers[i] != questions[i].correctAnswer) list.add(questions[i]);
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
        canSeeSuperadmin = role == 'superadmin' || role == 'employee';
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
    return _getFallbackQuestions(count, category: category, difficulty: difficulty);
  }

  List<QuizQuestion> _getFallbackQuestions(
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

  Future<void> seedQuestions() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final profileRes = await _client
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    final role = profileRes?['role'] ?? 'member';
    if (role != 'superadmin' && role != 'employee') {
      throw 'Permission denied: Only Superadmins or Employees can seed questions.';
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
  }

  Future<Map<String, dynamic>> findOpponent() async {
    try {
      final res = await _client
          .from('profiles')
          .select('full_name, id')
          .neq('id', _client.auth.currentUser?.id ?? '')
          .limit(10);

      if (res.isNotEmpty) {
        final list = List<Map<String, dynamic>>.from(res);
        list.shuffle();
        return {
          "name": list.first['full_name'],
          "id": list.first['id'],
          "avatar": "https://i.pravatar.cc/150?u=${list.first['id']}",
        };
      }
    } catch (e) {
      debugPrint('Failed to fetch random opponent, using mock: $e');
    }
    return {
      "name": "Brother Samuel",
      "id": "mock_opp",
      "avatar": "https://i.pravatar.cc/150?u=mock",
    };
  }

  static const List<Map<String, dynamic>> _seedBank = [
    {'question': 'Who was the first man created by God?', 'options': ['Adam', 'Cain', 'Abel', 'Seth'], 'correct_answer': 0, 'points': 10, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 2:7', 'is_superadmin_only': false},
    {'question': 'Who was the first woman?', 'options': ['Eve', 'Sarah', 'Rebekah', 'Leah'], 'correct_answer': 0, 'points': 10, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 3:20', 'is_superadmin_only': false},
    {'question': 'Who built the ark?', 'options': ['Moses', 'Noah', 'Abraham', 'David'], 'correct_answer': 1, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 6:14', 'is_superadmin_only': false},
    {'question': 'How many days did it rain during the great flood?', 'options': ['20 days', '30 days', '40 days', '50 days'], 'correct_answer': 2, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 7:17', 'is_superadmin_only': false},
    {'question': 'What did God use to part the Red Sea?', 'options': ["His hand alone", "Moses's staff", 'A great wind', 'Both B and C'], 'correct_answer': 3, 'points': 20, 'category': 'Miracles', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Exodus 14:21', 'is_superadmin_only': false},
    {'question': 'How many commandments did God give to Moses?', 'options': ['5', '7', '10', '12'], 'correct_answer': 2, 'points': 10, 'category': 'Law', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Exodus 20', 'is_superadmin_only': false},
    {'question': 'Who was sold into slavery by his brothers?', 'options': ['Moses', 'Abraham', 'Joseph', 'David'], 'correct_answer': 2, 'points': 10, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 37:28', 'is_superadmin_only': false},
    {'question': 'What giant did David defeat with a sling?', 'options': ['Og', 'Goliath', 'Sihon', 'Samson'], 'correct_answer': 1, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': '1 Samuel 17:50', 'is_superadmin_only': false},
    {'question': 'Who was swallowed by a large fish?', 'options': ['Elijah', 'Jonah', 'Hosea', 'Daniel'], 'correct_answer': 1, 'points': 10, 'category': 'Prophecy', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Jonah 1:17', 'is_superadmin_only': false},
    {'question': 'Which king had 700 wives?', 'options': ['David', 'Solomon', 'Saul', 'Jeroboam'], 'correct_answer': 1, 'points': 20, 'category': 'History', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': '1 Kings 11:3', 'is_superadmin_only': false},
    {'question': 'What language was the original Old Testament primarily written in?', 'options': ['Aramaic', 'Greek', 'Hebrew', 'Latin'], 'correct_answer': 2, 'points': 20, 'category': 'Scripture', 'difficulty': 'Medium', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'How many chapters are in the book of Psalms?', 'options': ['100', '120', '150', '180'], 'correct_answer': 2, 'points': 20, 'category': 'Scripture', 'difficulty': 'Medium', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'Who wrote the majority of the Psalms?', 'options': ['Moses', 'Solomon', 'Asaph', 'David'], 'correct_answer': 3, 'points': 20, 'category': 'People', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Psalm 3:1', 'is_superadmin_only': false},
    {'question': 'Which tribe of Israel did Moses belong to?', 'options': ['Judah', 'Benjamin', 'Levi', 'Ephraim'], 'correct_answer': 2, 'points': 20, 'category': 'People', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Exodus 2:1', 'is_superadmin_only': false},
    {'question': 'What does the word "Hallelujah" mean?', 'options': ['Praise God', 'Thank you Lord', 'Glory forever', 'Holy Spirit'], 'correct_answer': 0, 'points': 20, 'category': 'Language', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Psalm 150:1', 'is_superadmin_only': false},
    {'question': 'How many disciples did Jesus choose?', 'options': ['10', '11', '12', '13'], 'correct_answer': 2, 'points': 10, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Matthew 10:1', 'is_superadmin_only': false},
    {'question': 'Who betrayed Jesus Christ?', 'options': ['Peter', 'James', 'John', 'Judas Iscariot'], 'correct_answer': 3, 'points': 10, 'category': 'People', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Matthew 26:48', 'is_superadmin_only': false},
    {'question': 'In which city was Jesus born?', 'options': ['Jerusalem', 'Nazareth', 'Bethlehem', 'Jericho'], 'correct_answer': 2, 'points': 10, 'category': 'NT', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Luke 2:4', 'is_superadmin_only': false},
    {'question': 'Who baptized Jesus in the Jordan River?', 'options': ['Peter', 'John the Baptist', 'James', 'Philip'], 'correct_answer': 1, 'points': 10, 'category': 'NT', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Matthew 3:13', 'is_superadmin_only': false},
    {'question': "What was Jesus's first miracle?", 'options': ['Walking on water', 'Feeding 5000', 'Turning water to wine', 'Healing a blind man'], 'correct_answer': 2, 'points': 10, 'category': 'Miracles', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'John 2:11', 'is_superadmin_only': false},
    {'question': 'Who wrote the Gospel of Luke?', 'options': ['Luke the Apostle', 'Luke the Physician', "Paul's secretary", 'An anonymous author'], 'correct_answer': 1, 'points': 20, 'category': 'Scripture', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Colossians 4:14', 'is_superadmin_only': false},
    {'question': 'On which day did Jesus rise from the dead?', 'options': ['First day', 'Second day', 'Third day', 'Fourth day'], 'correct_answer': 2, 'points': 10, 'category': 'NT', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Luke 24:7', 'is_superadmin_only': false},
    {'question': 'How many books are in the New Testament?', 'options': ['24', '25', '27', '29'], 'correct_answer': 2, 'points': 20, 'category': 'Scripture', 'difficulty': 'Medium', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'Who wrote the most books in the New Testament?', 'options': ['Peter', 'John', 'James', 'Paul'], 'correct_answer': 3, 'points': 20, 'category': 'People', 'difficulty': 'Medium', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'What does the name "Jesus" mean in Hebrew?', 'options': ['God saves', 'Son of God', 'King of kings', 'Light of the world'], 'correct_answer': 0, 'points': 20, 'category': 'Language', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Matthew 1:21', 'is_superadmin_only': false},
    {'question': 'In which language was most of the New Testament originally written?', 'options': ['Latin', 'Aramaic', 'Koine Greek', 'Hebrew'], 'correct_answer': 2, 'points': 30, 'category': 'Scripture', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'How many chapters does the book of Revelation have?', 'options': ['18', '20', '22', '24'], 'correct_answer': 2, 'points': 30, 'category': 'Prophecy', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'Which angel announced the birth of Jesus to Mary?', 'options': ['Michael', 'Raphael', 'Uriel', 'Gabriel'], 'correct_answer': 3, 'points': 30, 'category': 'Angels', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': 'Luke 1:26', 'is_superadmin_only': false},
    {'question': 'What are the four Gospels in order?', 'options': ['Matthew, Mark, Luke, Acts', 'Matthew, Mark, Luke, John', 'Mark, Luke, John, Acts', 'Matthew, Luke, John, Romans'], 'correct_answer': 1, 'points': 30, 'category': 'Scripture', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': false},
    // === Additional questions ===
    {'question': 'Who was the oldest man in the Bible?', 'options': ['Noah', 'Abraham', 'Methuselah', 'Adam'], 'correct_answer': 2, 'points': 20, 'category': 'People', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Genesis 5:27', 'is_superadmin_only': false},
    {'question': 'Which book immediately follows the book of Malachi?', 'options': ['Psalms', 'Isaiah', 'Matthew', 'Genesis'], 'correct_answer': 2, 'points': 20, 'category': 'Scripture', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': null, 'is_superadmin_only': false},
    {'question': 'How many books are in the entire Bible?', 'options': ['64', '66', '68', '70'], 'correct_answer': 1, 'points': 10, 'category': 'Scripture', 'difficulty': 'Easy', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'Who was the first king of Israel?', 'options': ['David', 'Solomon', 'Saul', 'Samuel'], 'correct_answer': 2, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': '1 Samuel 10:1', 'is_superadmin_only': false},
    {'question': 'What did God create on the first day?', 'options': ['Water', 'Light', 'Sky', 'Animals'], 'correct_answer': 1, 'points': 10, 'category': 'History', 'difficulty': 'Easy', 'style': 'choice', 'scripture_reference': 'Genesis 1:3', 'is_superadmin_only': false},
    {'question': 'Which apostle was a tax collector before following Jesus?', 'options': ['Peter', 'John', 'Matthew', 'Thomas'], 'correct_answer': 2, 'points': 20, 'category': 'People', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': 'Matthew 9:9', 'is_superadmin_only': false},
    {'question': 'What is the longest book in the Bible?', 'options': ['Isaiah', 'Jeremiah', 'Psalms', 'Genesis'], 'correct_answer': 2, 'points': 20, 'category': 'Scripture', 'difficulty': 'Medium', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'Which city was known as the City of David?', 'options': ['Jerusalem', 'Bethlehem', 'Hebron', 'Nazareth'], 'correct_answer': 0, 'points': 20, 'category': 'History', 'difficulty': 'Medium', 'style': 'choice', 'scripture_reference': '2 Samuel 5:7', 'is_superadmin_only': false},
    {'question': 'How many times did the Israelites march around Jericho?', 'options': ['7 times on one day', '13 times total', '7 times for 6 days then 7 on the 7th', 'Once'], 'correct_answer': 2, 'points': 30, 'category': 'History', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': 'Joshua 6:3-4', 'is_superadmin_only': false},
    {'question': 'Who wrote the book of Hebrews?', 'options': ['Paul', 'Luke', 'Unknown / Anonymous', 'Peter'], 'correct_answer': 2, 'points': 30, 'category': 'Scripture', 'difficulty': 'Hard', 'style': 'choice', 'is_superadmin_only': false},
    {'question': 'What did Jesus say on the cross meaning "My God, my God, why have you forsaken me"?', 'options': ['Eloi, Eloi, lema sabachthani', 'Eli, Eli, lama sabachthani', 'Eloi, Eloi, lama sabachthani', 'Eli, Eli, lema sabachthani'], 'correct_answer': 1, 'points': 30, 'category': 'NT', 'difficulty': 'Hard', 'style': 'choice', 'scripture_reference': 'Matthew 27:46', 'is_superadmin_only': false},
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
}

final bibleQuizServiceProvider = Provider((ref) => BibleQuizService());

final quizLeaderboardProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = Supabase.instance.client;
  try {
    final res = await client
        .from('profiles')
        .select('full_name, id, coins')
        .order('coins', ascending: false)
        .limit(10);
    return List<Map<String, dynamic>>.from(res);
  } catch (_) {
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
    final res = await client
        .from('profiles')
        .select('id, coins')
        .order('coins', ascending: false);

    final profiles = List<Map<String, dynamic>>.from(res);
    int rank = profiles.indexWhere((p) => p['id'] == user.id) + 1;
    return rank > 0 ? "#$rank" : "N/A";
  } catch (_) {
    return "#12";
  }
});
