import 'quiz_engine.dart';
import 'quiz_models.dart';

/// Deterministic international-standard question bank with full
/// book/chapter/verse metadata. Seeded (never random) so widget tests and
/// CI runs are reproducible. Production swaps in [SupabaseQuizRepository].
class MockQuizRepository implements QuizRepository {
  final List<QuizQuestion> bank;

  MockQuizRepository({List<QuizQuestion>? bank}) : bank = bank ?? seedBank();

  static QuizQuestion q(
    String id,
    String prompt,
    List<String> options,
    int correct, {
    required String book,
    required int chapter,
    required int verseStart,
    int? verseEnd,
    QuizCategory category = QuizCategory.multipleChoice,
    QuizDifficulty difficulty = QuizDifficulty.medium,
    String translation = 'kjv',
  }) =>
      QuizQuestion(
        id: id,
        prompt: prompt,
        options: options,
        correctIndex: correct,
        category: category,
        difficulty: difficulty,
        book: book,
        chapter: chapter,
        verseStart: verseStart,
        verseEnd: verseEnd,
        translation: translation,
      );

  /// 12 canonical questions across all categories/difficulties.
  static List<QuizQuestion> seedBank() => [
        q('Q001', 'For God so loved the world, that he gave his only begotten Son — complete this quote.',
            ['That whosoever believeth in him should not perish', 'That the world may be saved', 'That all flesh shall see it', 'That light shineth in darkness'],
            0,
            book: 'John', chapter: 3, verseStart: 16,
            category: QuizCategory.directQuote, difficulty: QuizDifficulty.easy),
        q('Q002', 'In the beginning God created the heaven and the earth.',
            ['Genesis 1:1', 'Exodus 1:1', 'John 1:1', 'Psalm 1:1'],
            0,
            book: 'Genesis', chapter: 1, verseStart: 1,
            category: QuizCategory.speedRound, difficulty: QuizDifficulty.easy),
        q('Q003', 'Which plague was the seventh sent upon Egypt?',
            ['Hail', 'Locusts', 'Darkness', 'Frogs'],
            0,
            book: 'Exodus', chapter: 9, verseStart: 13, verseEnd: 35,
            category: QuizCategory.chapterAnalysis, difficulty: QuizDifficulty.hard),
        q('Q004', 'Who said: "Am I my brother\'s keeper?"',
            ['Cain', 'Abel', 'Seth', 'Enoch'],
            0,
            book: 'Genesis', chapter: 4, verseStart: 9,
            category: QuizCategory.directQuote, difficulty: QuizDifficulty.easy),
        q('Q005', 'How many books are in the New Testament?',
            ['27', '39', '24', '66'],
            0,
            book: 'Revelation', chapter: 22, verseStart: 21,
            category: QuizCategory.multipleChoice, difficulty: QuizDifficulty.easy),
        q('Q006', 'The fruit of the Spirit is love, joy, peace, longsuffering, gentleness, goodness, faith, meekness and…',
            ['Temperance', 'Patience', 'Mercy', 'Hope'],
            0,
            book: 'Galatians', chapter: 5, verseStart: 22, verseEnd: 23,
            category: QuizCategory.chapterAnalysis, difficulty: QuizDifficulty.medium),
        q('Q007', 'Who was the oldest man recorded in Scripture?',
            ['Methuselah', 'Noah', 'Adam', 'Enoch'],
            0,
            book: 'Genesis', chapter: 5, verseStart: 27,
            category: QuizCategory.multipleChoice, difficulty: QuizDifficulty.medium),
        q('Q008', '"The LORD is my shepherd; I shall not want." Identify the psalm.',
            ['Psalm 23', 'Psalm 91', 'Psalm 121', 'Psalm 100'],
            0,
            book: 'Psalms', chapter: 23, verseStart: 1,
            category: QuizCategory.speedRound, difficulty: QuizDifficulty.medium),
        q('Q009', 'Order the events of Creation week: which came immediately after "Let there be a firmament"?',
            ['Gathering of waters / dry land', 'Lights in the firmament', 'Great whales', 'Herb yielding seed'],
            0,
            book: 'Genesis', chapter: 1, verseStart: 9, verseEnd: 10,
            category: QuizCategory.chapterAnalysis, difficulty: QuizDifficulty.hard),
        q('Q010', 'Jesus wept.',
            ['John 11:35', 'Luke 19:41', 'Matthew 26:38', 'Mark 14:34'],
            0,
            book: 'John', chapter: 11, verseStart: 35,
            category: QuizCategory.speedRound, difficulty: QuizDifficulty.easy),
        q('Q011', 'To whom did Jesus say, "Thou art Peter, and upon this rock I will build my church"?',
            ['Simon Peter', 'Andrew', 'John', 'James'],
            0,
            book: 'Matthew', chapter: 16, verseStart: 18,
            category: QuizCategory.directQuote, difficulty: QuizDifficulty.medium),
        q('Q012', 'Which prophet was taken up by a whirlwind without dying?',
            ['Elijah', 'Elisha', 'Isaiah', 'Jeremiah'],
            0,
            book: '2 Kings', chapter: 2, verseStart: 11,
            category: QuizCategory.multipleChoice, difficulty: QuizDifficulty.medium),
      ];

  @override
  Future<List<QuizQuestion>> loadQuestions({
    required QuizMode mode,
    int count = 10,
    QuizCategory? category,
    QuizDifficulty? difficulty,
    String? tenantToken,
  }) async {
    if (mode == QuizMode.tournament && tenantToken == null) {
      throw ArgumentError('tournament mode requires tenantToken');
    }
    var list = [...bank];
    if (category != null) list = list.where((x) => x.category == category).toList();
    if (difficulty != null) list = list.where((x) => x.difficulty == difficulty).toList();
    return list.take(count).toList(); // deterministic order — no shuffle
  }

  @override
  Future<List<TenantTournament>> activeTournamentsForTenant(String tenantId) async => [
        TenantTournament(
          id: 't-001',
          name: '$tenantId Monthly Finals',
          tenantId: tenantId,
          startsAt: DateTime.now().subtract(const Duration(days: 1)),
          endsAt: DateTime.now().add(const Duration(days: 6)),
          questionPackIds: const ['pack-genesis', 'pack-john'],
        ),
      ];

  @override
  Future<QuizLeaderboard> monthlyLeaderboard({
    required String region,
    required QuizMode mode,
  }) async => MockLeaderboards.forRegion(region);

  @override
  Future<String> submitSession(QuizSession session, String scoreHash) async {
    if (session.isFlagged) {
      throw StateError('session flagged: ${session.antiCheatViolation}');
    }
    return scoreHash;
  }
}

/// Fixed ranking fixture exercising every tie-breaker tier.
class MockLeaderboards {
  static QuizLeaderboard forRegion(String region) {
    final base = DateTime(2026, 8, 1);
    QuizLeaderboardEntry e(
      String uid,
      String name,
      String reg,
      int score,
      int correct,
      int wrong,
      int avgMs,
      DateTime at,
    ) =>
        QuizLeaderboardEntry(
          userId: uid,
          displayName: name,
          region: reg,
          score: score,
          correctCount: correct,
          wrongCount: wrong,
          averageResponseTime: Duration(milliseconds: avgMs),
          completedAt: at,
        );
    final entries = [
      e('u-1', 'Chanda M.', 'ZM-LUSAKA', 120, 8, 1, 2100, base),
      // u-2 vs u-3: identical score/wrong/avg -> earlier completion wins.
      e('u-2', 'Naledi P.', 'ZM-LUSAKA', 120, 8, 1, 1900, base),
      e('u-3', 'Tapiwa Z.', 'ZM-LUSAKA', 120, 8, 1, 1900,
          base.subtract(const Duration(minutes: 5))),
      e('u-4', 'Mutale K.', 'GLOBAL', 150, 10, 0, 2500, base),
      e('u-5', 'Bwalya S.', 'ZW-HARARE', 90, 6, 2, 4000, base),
      // Tie-breaker tier 4: identical everything -> earlier completion wins.
      e('u-6', 'Kabwe J.', 'ZM-LUSAKA', 90, 6, 2, 4000,
          base.add(const Duration(hours: 2))),
    ];
    return QuizLeaderboard.of(title: 'Monthly Rankings', entries: entries)
        .forRegion(region);
  }
}
