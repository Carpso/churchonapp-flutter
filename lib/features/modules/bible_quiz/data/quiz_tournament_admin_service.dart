import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A tournament row as seen by platform staff (superadmin / COA).
///
/// Backed by `quiz_tournaments` extended by migration
/// `20261205_quiz_tournament_admin_rewards.sql` — full scheduling, entry fees,
/// prize configuration, feature/promote flags and an awards ledger.
class TournamentAdmin {
  final String id;
  final String hostTenantId;
  final String? hostUserId;
  final String? questionSetId;
  final String title;
  final String? description;
  final String format;
  final String visibility; // tenant | invited | public
  final String status; // draft|scheduled|published|live|completed|cancelled
  final bool isPromo;
  final bool isFeatured;
  final bool platformHosted;
  final DateTime? publishedAt;
  final int questionCount;
  final int timePerQuestion;
  final int maxParticipants;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? registrationOpensAt;
  final DateTime? registrationClosesAt;
  final int? durationWeeks;
  final int? durationMonths;
  final String? seasonLabel;
  final String recurrence; // none|daily|weekly|monthly|yearly
  final int recurrenceInterval;
  final DateTime? recurrenceUntil;
  final int entryFeeCc;
  final double entryFeeKwacha;
  final int prize1stCc;
  final int prize2ndCc;
  final int prize3rdCc;
  final int participationRewardCc;
  final int streakRewardCc;
  final String? entryPromoCode;
  final String? bannerUrl;
  final Map<String, dynamic> prizeConfig;
  final DateTime createdAt;

  const TournamentAdmin({
    required this.id,
    required this.hostTenantId,
    this.hostUserId,
    this.questionSetId,
    required this.title,
    this.description,
    this.format = 'knockout',
    this.visibility = 'public',
    this.status = 'draft',
    this.isPromo = false,
    this.isFeatured = false,
    this.platformHosted = false,
    this.publishedAt,
    this.questionCount = 10,
    this.timePerQuestion = 15,
    this.maxParticipants = 32,
    this.startsAt,
    this.endsAt,
    this.registrationOpensAt,
    this.registrationClosesAt,
    this.durationWeeks,
    this.durationMonths,
    this.seasonLabel,
    this.recurrence = 'none',
    this.recurrenceInterval = 1,
    this.recurrenceUntil,
    this.entryFeeCc = 0,
    this.entryFeeKwacha = 0,
    this.prize1stCc = 0,
    this.prize2ndCc = 0,
    this.prize3rdCc = 0,
    this.participationRewardCc = 0,
    this.streakRewardCc = 0,
    this.entryPromoCode,
    this.bannerUrl,
    this.prizeConfig = const {},
    required this.createdAt,
  });

  bool get isFree => entryFeeCc <= 0 && entryFeeKwacha <= 0;
  bool get isOpen =>
      status == 'draft' || status == 'scheduled' || status == 'published' || status == 'live';

  static DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory TournamentAdmin.fromMap(Map<String, dynamic> m) => TournamentAdmin(
        id: m['id'].toString(),
        hostTenantId: m['host_tenant_id']?.toString() ?? '',
        hostUserId: m['host_user_id']?.toString(),
        questionSetId: m['question_set_id']?.toString(),
        title: (m['title'] ?? 'Tournament').toString(),
        description: m['description']?.toString(),
        format: (m['format'] ?? 'knockout').toString(),
        visibility: (m['visibility'] ?? 'public').toString(),
        status: (m['status'] ?? 'draft').toString(),
        isPromo: m['is_promo'] == true,
        isFeatured: m['is_featured'] == true,
        platformHosted: m['platform_hosted'] == true,
        publishedAt: _dt(m['published_at']),
        questionCount: (m['question_count'] as num?)?.toInt() ?? 10,
        timePerQuestion: (m['time_per_question'] as num?)?.toInt() ?? 15,
        maxParticipants: (m['max_participants'] as num?)?.toInt() ?? 32,
        startsAt: _dt(m['starts_at']),
        endsAt: _dt(m['ends_at']),
        registrationOpensAt: _dt(m['registration_opens_at']),
        registrationClosesAt: _dt(m['registration_closes_at']),
        durationWeeks: (m['duration_weeks'] as num?)?.toInt(),
        durationMonths: (m['duration_months'] as num?)?.toInt(),
        seasonLabel: m['season_label']?.toString(),
        recurrence: (m['recurrence'] ?? 'none').toString(),
        recurrenceInterval: (m['recurrence_interval'] as num?)?.toInt() ?? 1,
        recurrenceUntil: _dt(m['recurrence_until']),
        entryFeeCc: (m['entry_fee_cc'] as num?)?.toInt() ?? 0,
        entryFeeKwacha: (m['entry_fee_kwacha'] as num?)?.toDouble() ?? 0,
        prize1stCc: (m['prize_1st_cc'] as num?)?.toInt() ?? 0,
        prize2ndCc: (m['prize_2nd_cc'] as num?)?.toInt() ?? 0,
        prize3rdCc: (m['prize_3rd_cc'] as num?)?.toInt() ?? 0,
        participationRewardCc:
            (m['participation_reward_cc'] as num?)?.toInt() ?? 0,
        streakRewardCc: (m['streak_reward_cc'] as num?)?.toInt() ?? 0,
        entryPromoCode: m['entry_promo_code']?.toString(),
        bannerUrl: m['banner_url']?.toString(),
        prizeConfig: m['prize_config'] is Map
            ? Map<String, dynamic>.from(m['prize_config'] as Map)
            : const {},
        createdAt: _dt(m['created_at']) ?? DateTime.now(),
      );
}

/// One reward row from `quiz_tournament_awards`.
class TournamentAward {
  final String id;
  final String tournamentId;
  final String userId;
  final int? rank;
  final String awardType; // prize | participation | streak | manual
  final int ccAmount;
  final String? promoCode;
  final String? label;
  final String status; // awarded | revoked
  final DateTime? awardedAt;
  final String? fullName;
  final String? avatarUrl;

  const TournamentAward({
    required this.id,
    required this.tournamentId,
    required this.userId,
    this.rank,
    this.awardType = 'prize',
    this.ccAmount = 0,
    this.promoCode,
    this.label,
    this.status = 'awarded',
    this.awardedAt,
    this.fullName,
    this.avatarUrl,
  });

  factory TournamentAward.fromMap(Map<String, dynamic> m) => TournamentAward(
        id: m['id'].toString(),
        tournamentId: m['tournament_id'].toString(),
        userId: m['user_id'].toString(),
        rank: (m['rank'] as num?)?.toInt(),
        awardType: (m['award_type'] ?? 'prize').toString(),
        ccAmount: (m['cc_amount'] as num?)?.toInt() ?? 0,
        promoCode: m['promo_code']?.toString(),
        label: m['label']?.toString(),
        status: (m['status'] ?? 'awarded').toString(),
        awardedAt: m['awarded_at'] != null
            ? DateTime.tryParse(m['awarded_at'].toString())
            : null,
        fullName: m['full_name']?.toString(),
        avatarUrl: m['avatar_url']?.toString(),
      );
}

class QuizTournamentAdminService {
  final SupabaseClient _client;
  QuizTournamentAdminService(this._client);

  List<Map<String, dynamic>> _asList(dynamic res) {
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<List<TournamentAdmin>> listTournaments() async {
    final rows = await _client
        .from('quiz_tournaments')
        .select()
        .order('is_featured', ascending: false)
        .order('created_at', ascending: false)
        .limit(200);
    return _asList(rows).map(TournamentAdmin.fromMap).toList();
  }

  /// Tournaments promoted onto the hub for everyone.
  Future<List<TournamentAdmin>> listFeatured() async {
    final rows = await _client
        .from('quiz_tournaments')
        .select()
        .eq('is_featured', true)
        .inFilter('status', ['scheduled', 'published', 'live'])
        .order('starts_at', ascending: true)
        .limit(10);
    return _asList(rows).map(TournamentAdmin.fromMap).toList();
  }

  Future<String?> createTournament(Map<String, dynamic> payload) async {
    final res = await _client
        .rpc('create_quiz_tournament_admin', params: {'p_payload': payload});
    final map = res is Map ? Map<String, dynamic>.from(res) : null;
    return map?['tournament_id']?.toString();
  }

  Future<void> updateTournament(
      String id, Map<String, dynamic> payload) async {
    await _client.rpc('update_quiz_tournament_admin', params: {
      'p_tournament_id': id,
      'p_payload': payload,
    });
  }

  Future<void> publish(String id, bool publish) async {
    await _client.rpc('publish_quiz_tournament', params: {
      'p_tournament_id': id,
      'p_publish': publish,
    });
  }

  Future<void> setFeatured(String id, bool featured) async {
    await _client.rpc('set_quiz_tournament_featured', params: {
      'p_tournament_id': id,
      'p_featured': featured,
    });
  }

  Future<void> cancel(String id, {String? reason}) async {
    await _client.rpc('cancel_quiz_tournament_admin', params: {
      'p_tournament_id': id,
      'p_reason': reason,
    });
  }

  Future<String?> duplicate(String id) async {
    final res =
        await _client.rpc('duplicate_quiz_tournament', params: {'p_tournament_id': id});
    final map = res is Map ? Map<String, dynamic>.from(res) : null;
    return map?['tournament_id']?.toString();
  }

  Future<int> spawnOccurrences(String id, int count) async {
    final res = await _client.rpc('spawn_quiz_tournament_occurrences', params: {
      'p_tournament_id': id,
      'p_count': count,
    });
    final map = res is Map ? Map<String, dynamic>.from(res) : null;
    return (map?['spawned'] as List?)?.length ?? 0;
  }

  Future<Map<String, dynamic>> awardPrizes(String id) async {
    final res = await _client
        .rpc('award_quiz_tournament_prizes', params: {'p_tournament_id': id});
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> awardManual({
    required String tournamentId,
    required String userId,
    int cc = 0,
    String? promoCode,
    String label = 'Manual reward',
    int? rank,
  }) async {
    final res = await _client.rpc('award_tournament_reward_manual', params: {
      'p_tournament_id': tournamentId,
      'p_user_id': userId,
      'p_cc': cc,
      'p_promo_code': promoCode,
      'p_label': label,
      'p_rank': rank,
    });
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  Future<void> revokeAward(String awardId) async {
    await _client.rpc('revoke_tournament_award', params: {'p_award_id': awardId});
  }

  Future<List<TournamentAward>> listAwards(String tournamentId) async {
    final res = await _client.rpc('list_quiz_tournament_awards',
        params: {'p_tournament_id': tournamentId});
    if (res is List) {
      return res
          .map((e) => TournamentAward.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return const [];
  }

  /// Join a promoted tournament (used by the hub banner for any member).
  Future<bool> joinTournament(String id) async {
    try {
      final res = await _client
          .rpc('join_quiz_tournament', params: {'p_tournament_id': id});
      final map = res is Map ? Map<String, dynamic>.from(res) : null;
      return map?['joined'] == true;
    } catch (e) {
      debugPrint('joinTournament failed: $e');
      return false;
    }
  }
}

final quizTournamentAdminServiceProvider =
    Provider<QuizTournamentAdminService>((ref) {
  return QuizTournamentAdminService(Supabase.instance.client);
});

final adminTournamentsProvider =
    FutureProvider<List<TournamentAdmin>>((ref) async {
  return ref.watch(quizTournamentAdminServiceProvider).listTournaments();
});

final featuredTournamentsProvider =
    FutureProvider.autoDispose<List<TournamentAdmin>>((ref) async {
  return ref.watch(quizTournamentAdminServiceProvider).listFeatured();
});

final tournamentAwardsProvider =
    FutureProvider.family<List<TournamentAward>, String>((ref, id) async {
  return ref.watch(quizTournamentAdminServiceProvider).listAwards(id);
});
