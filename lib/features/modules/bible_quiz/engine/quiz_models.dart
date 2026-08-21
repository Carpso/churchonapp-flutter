import 'package:flutter/foundation.dart';

import 'quiz_engine.dart';

/// Monthly regional/global ranking entry. Tie-breakers (WBQA style):
/// 1. higher score, 2. fewer wrong attempts, 3. faster average response,
/// 4. earlier completion timestamp.
@immutable
class QuizLeaderboardEntry implements Comparable<QuizLeaderboardEntry> {
  final String userId;
  final String displayName;
  final String? tenantId;
  final String? churchName;

  /// Region scope e.g. "ZM-LUSAKA", "GLOBAL".
  final String region;
  final int score;
  final int correctCount;
  final int wrongCount;
  final Duration averageResponseTime;
  final DateTime completedAt;

  const QuizLeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.region,
    required this.score,
    required this.correctCount,
    required this.wrongCount,
    required this.averageResponseTime,
    required this.completedAt,
    this.tenantId,
    this.churchName,
  });

  @override
  int compareTo(QuizLeaderboardEntry other) {
    if (score != other.score) return other.score.compareTo(score);
    if (wrongCount != other.wrongCount) return wrongCount.compareTo(other.wrongCount);
    final avgCmp = averageResponseTime.compareTo(other.averageResponseTime);
    if (avgCmp != 0) return avgCmp;
    return completedAt.compareTo(other.completedAt);
  }
}

/// Ranked board with deterministic tie-breaking applied via the factory
/// (static methods can't run in const initializers, so sorting happens in
/// [QuizLeaderboard.of]).
@immutable
class QuizLeaderboard {
  final String title;
  final List<QuizLeaderboardEntry> entries;

  const QuizLeaderboard._({required this.title, required this.entries});

  factory QuizLeaderboard.of({
    required String title,
    required List<QuizLeaderboardEntry> entries,
  }) {
    final list = [...entries]..sort();
    return QuizLeaderboard._(title: title, entries: List.unmodifiable(list));
  }

  /// Alias kept for readability at call sites.
  static QuizLeaderboard build({
    required String title,
    required List<QuizLeaderboardEntry> entries,
  }) =>
      QuizLeaderboard.of(title: title, entries: entries);

  int rankOf(String userId) {
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].userId == userId) return i + 1;
    }
    return -1;
  }

  /// Filters to a region scope ("ZM-LUSAKA" or "GLOBAL").
  QuizLeaderboard forRegion(String region) => QuizLeaderboard.of(
        title: '$title - $region',
        entries: entries.where((e) => e.region == region).toList(),
      );
}

/// A church/bookshop-sponsored tournament. Access requires an active tenant
/// membership; the token is minted server-side per tournament.
@immutable
class TenantTournament {
  final String id;
  final String name;
  final String tenantId;
  final String? brandingLogoUrl;
  final DateTime startsAt;
  final DateTime endsAt;
  final QuizRuleSet rules;
  final int maxParticipants;
  final List<String> questionPackIds;

  /// Rewards
  final String trophyLabel;
  final int voucherDiscountPercent;
  final int prizeCoinsFirst;

  const TenantTournament({
    required this.id,
    required this.name,
    required this.tenantId,
    required this.startsAt,
    required this.endsAt,
    this.rules = QuizRuleSet.tournament,
    this.maxParticipants = 100,
    this.questionPackIds = const [],
    this.brandingLogoUrl,
    this.trophyLabel = 'Champion Trophy',
    this.voucherDiscountPercent = 10,
    this.prizeCoinsFirst = 500,
  });

  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(startsAt) && now.isBefore(endsAt);
  }

  bool get isUpcoming => DateTime.now().isBefore(startsAt);
}

/// Abstract repository so presentation/tests never touch Supabase directly.
/// Production impl wraps the existing BibleQuizService RPCs; tests use
/// [MockQuizRepository] with the deterministic seed bank.
abstract class QuizRepository {
  Future<List<QuizQuestion>> loadQuestions({
    required QuizMode mode,
    int count = 10,
    QuizCategory? category,
    QuizDifficulty? difficulty,
    String? tenantToken,
  });

  Future<List<TenantTournament>> activeTournamentsForTenant(String tenantId);

  Future<QuizLeaderboard> monthlyLeaderboard({
    required String region,
    required QuizMode mode,
  });

  /// Persists a finished session; returns the server-validated score hash
  /// used for leaderboard anti-tamper verification.
  Future<String> submitSession(QuizSession session, String scoreHash);
}

/// Deterministic SHA-style hash over session facts. NOT cryptographic —
/// production replaces this via `submitSession` with a server HMAC. Kept in
/// the engine so client and tests agree on the canonical payload ordering.
String scoreHashPreview(QuizSession s) {
  final facts = [
    s.id,
    s.userId,
    s.mode.name,
    s.score.toString(),
    s.attempts.length.toString(),
    s.questions.fold(0, (acc, q) => acc ^ q.id.hashCode).toSigned(32).toString(),
  ];
  var h = 0x811c9dc5;
  for (final part in facts.join('|').codeUnits) {
    h ^= part;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}
