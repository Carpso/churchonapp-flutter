import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/services/r2_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

/// A church's Quiz Engine lease (season / year). Hosting requires an active
/// lease (Kwacha via `coa_payments`, or Church Coins via the CC store).
class QuizEngineLease {
  final String id;
  final String tenantId;
  final String status; // pending | active | expired | revoked
  final String? seasonLabel;
  final DateTime startsAt;
  final DateTime endsAt;
  final double feeKwacha;

  const QuizEngineLease({
    required this.id,
    required this.tenantId,
    required this.status,
    this.seasonLabel,
    required this.startsAt,
    required this.endsAt,
    this.feeKwacha = 0,
  });

  bool get isActive => status == 'active' && endsAt.isAfter(DateTime.now());

  factory QuizEngineLease.fromMap(Map<String, dynamic> m) => QuizEngineLease(
        id: m['id'].toString(),
        tenantId: m['tenant_id'].toString(),
        status: (m['status'] ?? 'pending').toString(),
        seasonLabel: m['season_label']?.toString(),
        startsAt: DateTime.tryParse(m['starts_at']?.toString() ?? '') ??
            DateTime.now(),
        endsAt: DateTime.tryParse(m['ends_at']?.toString() ?? '') ??
            DateTime.now(),
        feeKwacha: (m['fee_kwacha'] as num?)?.toDouble() ?? 0,
      );
}

class QuizQuestionSet {
  final String id;
  final String title;
  final String? description;
  final String? sourceFileUrl;
  final String? sourceFileName;
  final String? sourceFileType;
  final String extractStatus; // pending|processing|ready|failed
  final String? extractError;
  final int extractedCount;
  final bool studyPackOpen;
  final DateTime createdAt;

  const QuizQuestionSet({
    required this.id,
    required this.title,
    this.description,
    this.sourceFileUrl,
    this.sourceFileName,
    this.sourceFileType,
    this.extractStatus = 'pending',
    this.extractError,
    this.extractedCount = 0,
    this.studyPackOpen = true,
    required this.createdAt,
  });

  factory QuizQuestionSet.fromMap(Map<String, dynamic> m) => QuizQuestionSet(
        id: m['id'].toString(),
        title: (m['title'] ?? 'Question set').toString(),
        description: m['description']?.toString(),
        sourceFileUrl: m['source_file_url']?.toString(),
        sourceFileName: m['source_file_name']?.toString(),
        sourceFileType: m['source_file_type']?.toString(),
        extractStatus: (m['extract_status'] ?? 'pending').toString(),
        extractError: m['extract_error']?.toString(),
        extractedCount: (m['extracted_count'] as num?)?.toInt() ?? 0,
        studyPackOpen: m['study_pack_open'] != false,
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class QuizSetQuestion {
  final String id;
  final String prompt;
  final List<String> options;
  final List<String> correctAnswers;
  final String? verseReference;
  final String? category;
  final String? difficulty;
  final int points;
  final bool isStudyVisible;

  const QuizSetQuestion({
    required this.id,
    required this.prompt,
    required this.options,
    required this.correctAnswers,
    this.verseReference,
    this.category,
    this.difficulty,
    this.points = 10,
    this.isStudyVisible = true,
  });

  factory QuizSetQuestion.fromMap(Map<String, dynamic> m) => QuizSetQuestion(
        id: m['id'].toString(),
        prompt: (m['prompt'] ?? '').toString(),
        options: ((m['options'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        correctAnswers: ((m['correct_answers'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        verseReference: m['verse_reference']?.toString(),
        category: m['category']?.toString(),
        difficulty: m['difficulty']?.toString(),
        points: (m['points'] as num?)?.toInt() ?? 10,
        isStudyVisible: m['is_study_visible'] != false,
      );
}

class QuizTournament {
  final String id;
  final String hostTenantId;
  final String? questionSetId;
  final String title;
  final String? description;
  final String format;
  final String visibility; // tenant | invited | public
  final String status; // draft|scheduled|live|completed|cancelled
  final int questionCount;
  final int timePerQuestion;
  final int maxParticipants;
  final DateTime? startsAt;
  final DateTime createdAt;

  const QuizTournament({
    required this.id,
    required this.hostTenantId,
    this.questionSetId,
    required this.title,
    this.description,
    this.format = 'knockout',
    this.visibility = 'tenant',
    this.status = 'draft',
    this.questionCount = 10,
    this.timePerQuestion = 15,
    this.maxParticipants = 32,
    this.startsAt,
    required this.createdAt,
  });

  bool get isHostedByMe => false; // compared in UI against profile tenant

  factory QuizTournament.fromMap(Map<String, dynamic> m) => QuizTournament(
        id: m['id'].toString(),
        hostTenantId: m['host_tenant_id'].toString(),
        questionSetId: m['question_set_id']?.toString(),
        title: (m['title'] ?? 'Tournament').toString(),
        description: m['description']?.toString(),
        format: (m['format'] ?? 'knockout').toString(),
        visibility: (m['visibility'] ?? 'tenant').toString(),
        status: (m['status'] ?? 'draft').toString(),
        questionCount: (m['question_count'] as num?)?.toInt() ?? 10,
        timePerQuestion: (m['time_per_question'] as num?)?.toInt() ?? 15,
        maxParticipants: (m['max_participants'] as num?)?.toInt() ?? 32,
        startsAt: m['starts_at'] != null
            ? DateTime.tryParse(m['starts_at'].toString())
            : null,
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class QuizTournamentMatch {
  final String id;
  final int round;
  final int slot;
  final String? homeUserId;
  final String? awayUserId;
  final int? homeScore;
  final int? awayScore;
  final String? winnerUserId;
  final String status;

  const QuizTournamentMatch({
    required this.id,
    required this.round,
    required this.slot,
    this.homeUserId,
    this.awayUserId,
    this.homeScore,
    this.awayScore,
    this.winnerUserId,
    this.status = 'pending',
  });

  factory QuizTournamentMatch.fromMap(Map<String, dynamic> m) =>
      QuizTournamentMatch(
        id: m['id'].toString(),
        round: (m['round'] as num?)?.toInt() ?? 1,
        slot: (m['slot'] as num?)?.toInt() ?? 1,
        homeUserId: m['home_user_id']?.toString(),
        awayUserId: m['away_user_id']?.toString(),
        homeScore: (m['home_score'] as num?)?.toInt(),
        awayScore: (m['away_score'] as num?)?.toInt(),
        winnerUserId: m['winner_user_id']?.toString(),
        status: (m['status'] ?? 'pending').toString(),
      );
}

class QuizTournamentInvite {
  final String id;
  final String tournamentId;
  final String tenantId;
  final String status;
  final String? tournamentTitle;

  const QuizTournamentInvite({
    required this.id,
    required this.tournamentId,
    required this.tenantId,
    required this.status,
    this.tournamentTitle,
  });

  factory QuizTournamentInvite.fromMap(Map<String, dynamic> m) =>
      QuizTournamentInvite(
        id: m['id'].toString(),
        tournamentId: m['tournament_id'].toString(),
        tenantId: m['tenant_id'].toString(),
        status: (m['status'] ?? 'invited').toString(),
        tournamentTitle: m['quiz_tournaments'] is Map
            ? (m['quiz_tournaments'] as Map)['title']?.toString()
            : null,
      );
}

class QuizHostingService {
  final SupabaseClient _client;
  final Ref _ref;
  QuizHostingService(this._client, this._ref);

  String? get _tenantId =>
      _ref.read(profileProvider).value?.tenantId ??
      _ref.read(currentTenantProvider)?.id;

  // ── Lease ─────────────────────────────────────────────────────────────────
  Future<QuizEngineLease?> fetchLease() async {
    final tid = _tenantId;
    if (tid == null) return null;
    final rows = await _client
        .from('quiz_engine_leases')
        .select()
        .eq('tenant_id', tid)
        .order('ends_at', ascending: false)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return QuizEngineLease.fromMap(Map<String, dynamic>.from(list.first as Map));
  }

  Future<bool> canHost() async {
    final tid = _tenantId;
    if (tid == null) return false;
    final res = await _client.rpc('tenant_can_host_quiz', params: {
      'p_tenant_id': tid,
    });
    return res == true;
  }

  /// Confirm a Kwacha payment already recorded in `coa_payments` and record the
  /// lease. Returns the RPC map (`leased`, `reason`, `fee_kwacha`…).
  Future<Map<String, dynamic>> leaseWithKwacha({
    String? seasonLabel,
    String? paymentRef,
  }) async {
    final res = await _client.rpc('lease_quiz_engine', params: {
      'p_season_label': seasonLabel,
      'p_payment_ref': paymentRef,
    });
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  // ── Question sets ─────────────────────────────────────────────────────────
  Future<List<QuizQuestionSet>> fetchSets() async {
    final tid = _tenantId;
    if (tid == null) return [];
    final rows = await _client
        .from('quiz_question_sets')
        .select()
        .eq('tenant_id', tid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => QuizQuestionSet.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<String?> createSet(String title, {String? description}) async {
    final res = await _client.rpc('create_quiz_set', params: {
      'p_title': title,
      'p_description': description,
    });
    final map = res is Map ? Map<String, dynamic>.from(res) : null;
    return map?['set_id']?.toString();
  }

  Future<List<QuizSetQuestion>> fetchQuestions(String setId) async {
    final rows = await _client
        .from('quiz_set_questions')
        .select()
        .eq('set_id', setId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((e) => QuizSetQuestion.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> updateStudyPack(String setId, bool open) async {
    await _client
        .from('quiz_question_sets')
        .update({'study_pack_open': open}).eq('id', setId);
  }

  Future<void> updateQuestionVisibility(String questionId, bool visible) async {
    await _client
        .from('quiz_set_questions')
        .update({'is_study_visible': visible}).eq('id', questionId);
  }

  Future<void> deleteSet(String setId) async {
    await _client.from('quiz_question_sets').delete().eq('id', setId);
  }

  /// Upload a paper to R2 then run extraction through `quiz-import`.
  /// Returns the import result map.
  Future<Map<String, dynamic>> uploadAndExtract({
    required String setId,
    Uint8List? bytes,
    String? fileName,
    String? pastedText,
  }) async {
    String? fileUrl;
    if (bytes != null && fileName != null) {
      final ext = fileName.split('.').last.toLowerCase();
      fileUrl = await R2Service(_client).uploadBytes(
        bytes,
        'quiz-questions/${setId}_${DateTime.now().millisecondsSinceEpoch}.$ext',
        contentType: _contentTypeFor(ext),
      );
    }

    final body = <String, dynamic>{'setId': setId};
    if (pastedText != null && pastedText.trim().isNotEmpty) {
      body['text'] = pastedText;
    } else if (bytes != null && fileName != null) {
      body['fileName'] = fileName;
      body['dataBase64'] = base64Encode(bytes);
    } else {
      throw Exception('Provide a file or pasted text');
    }
    if (fileUrl != null) body['sourceFileUrl'] = fileUrl;
    if (fileName != null) body['sourceFileName'] = fileName;
    if (fileUrl != null) body['sourceFileType'] = fileName?.split('.').last;

    final res = await _client.functions.invoke('quiz-import', body: body);
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  String _contentTypeFor(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'csv':
        return 'text/csv';
      case 'md':
        return 'text/markdown';
      default:
        return 'text/plain';
    }
  }

  // ── Tournaments ───────────────────────────────────────────────────────────
  Future<List<QuizTournament>> fetchTournaments() async {
    final rows = await _client
        .from('quiz_tournaments')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((e) => QuizTournament.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> createTournament({
    required String title,
    String? description,
    String? questionSetId,
    String visibility = 'tenant',
    String format = 'knockout',
    int questionCount = 10,
    int timePerQuestion = 15,
    int maxParticipants = 32,
    DateTime? startsAt,
    List<String>? invitedTenants,
  }) async {
    final res = await _client.rpc('create_quiz_tournament', params: {
      'p_title': title,
      'p_description': description,
      'p_question_set_id': questionSetId,
      'p_visibility': visibility,
      'p_format': format,
      'p_question_count': questionCount,
      'p_time_per_question': timePerQuestion,
      'p_starts_at': startsAt?.toIso8601String(),
      'p_max_participants': maxParticipants,
      'p_invited_tenants': invitedTenants,
    });
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  Future<void> startTournament(String id) async {
    await _client.rpc('start_quiz_tournament', params: {'p_tournament_id': id});
  }

  Future<int> generateBracket(String id) async {
    final res = await _client
        .rpc('generate_quiz_bracket', params: {'p_tournament_id': id});
    final map = res is Map ? Map<String, dynamic>.from(res) : null;
    return (map?['round1_matches'] as num?)?.toInt() ?? 0;
  }

  Future<List<QuizTournamentMatch>> fetchBracket(String tournamentId) async {
    final rows = await _client
        .from('quiz_tournament_matches')
        .select()
        .eq('tournament_id', tournamentId)
        .order('round', ascending: true)
        .order('slot', ascending: true);
    return (rows as List)
        .map((e) =>
            QuizTournamentMatch.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> recordResult(String matchId, int homeScore, int awayScore) async {
    await _client.rpc('record_quiz_match_result', params: {
      'p_match_id': matchId,
      'p_home_score': homeScore,
      'p_away_score': awayScore,
    });
  }

  Future<bool> joinTournament(String id) async {
    final res = await _client.rpc('join_quiz_tournament', params: {
      'p_tournament_id': id,
    });
    final map = res is Map ? Map<String, dynamic>.from(res) : null;
    return map?['joined'] == true;
  }

  Future<void> respondInvite(String tournamentId, bool accept) async {
    await _client.rpc('respond_quiz_tournament_invite', params: {
      'p_tournament_id': tournamentId,
      'p_accept': accept,
    });
  }

  Future<List<QuizTournamentInvite>> fetchInvites() async {
    final tid = _tenantId;
    if (tid == null) return [];
    final rows = await _client
        .from('quiz_tournament_invites')
        .select('*, quiz_tournaments(title)')
        .eq('tenant_id', tid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) =>
            QuizTournamentInvite.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Record presence as a spectator and return the live viewer count.
  Future<int> watch(String tournamentId) async {
    final res = await _client.rpc('quiz_tournament_watch', params: {
      'p_tournament_id': tournamentId,
    });
    return (res as num?)?.toInt() ?? 0;
  }

  /// Names of tenants available to invite (other churches).
  Future<List<Map<String, dynamic>>> fetchInvitableTenants() async {
    try {
      final rows = await _client
          .from('tenants')
          .select('id, name')
          .eq('type', 'church')
          .order('name')
          .limit(100);
      final myTid = _tenantId;
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((t) => t['id']?.toString() != myTid)
          .toList();
    } catch (e) {
      debugPrint('fetchInvitableTenants failed: $e');
      return [];
    }
  }
}

final quizHostingServiceProvider = Provider<QuizHostingService>((ref) {
  return QuizHostingService(Supabase.instance.client, ref);
});

final quizLeaseProvider = FutureProvider<QuizEngineLease?>((ref) async {
  return ref.watch(quizHostingServiceProvider).fetchLease();
});

final quizCanHostProvider = FutureProvider<bool>((ref) async {
  return ref.watch(quizHostingServiceProvider).canHost();
});

final quizSetsProvider = FutureProvider<List<QuizQuestionSet>>((ref) async {
  return ref.watch(quizHostingServiceProvider).fetchSets();
});

final quizSetQuestionsProvider =
    FutureProvider.family<List<QuizSetQuestion>, String>((ref, setId) async {
  return ref.watch(quizHostingServiceProvider).fetchQuestions(setId);
});

final quizTournamentsProvider =
    FutureProvider<List<QuizTournament>>((ref) async {
  return ref.watch(quizHostingServiceProvider).fetchTournaments();
});

final quizTournamentInvitesProvider =
    FutureProvider<List<QuizTournamentInvite>>((ref) async {
  return ref.watch(quizHostingServiceProvider).fetchInvites();
});

final quizBracketProvider =
    FutureProvider.family<List<QuizTournamentMatch>, String>(
        (ref, tournamentId) async {
  return ref.watch(quizHostingServiceProvider).fetchBracket(tournamentId);
});
