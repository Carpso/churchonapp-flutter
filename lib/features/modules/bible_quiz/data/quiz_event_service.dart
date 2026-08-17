import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import 'bible_quiz_service.dart';

class QuizEvent {
  final String id;
  final String title;
  final String? description;
  final String? hostChurchId;
  final String? createdBy;
  final double passPriceZmw;
  final double passPriceCc;
  final int questionCount;
  final int timePerQuestionSec;
  final DateTime startTime;
  final DateTime? endTime;
  final String status;
  final int? maxParticipants;
  final String? categoryFilter;
  final String? difficultyFilter;
  final bool isFeatured;
  final String? bannerUrl;
  final int wagerCoins;
  final DateTime? settledAt;
  final DateTime createdAt;

  QuizEvent({
    required this.id,
    required this.title,
    this.description,
    this.hostChurchId,
    this.createdBy,
    this.passPriceZmw = 0,
    this.passPriceCc = 0,
    this.questionCount = 10,
    this.timePerQuestionSec = 15,
    required this.startTime,
    this.endTime,
    this.status = 'upcoming',
    this.maxParticipants,
    this.categoryFilter,
    this.difficultyFilter,
    this.isFeatured = false,
    this.bannerUrl,
    this.wagerCoins = 0,
    this.settledAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory QuizEvent.fromMap(Map<String, dynamic> m) => QuizEvent(
        id: m['id']?.toString() ?? '',
        title: m['title'] ?? '',
        description: m['description'],
        hostChurchId: m['host_church_id']?.toString(),
        createdBy: m['created_by']?.toString(),
        passPriceZmw: (m['pass_price_zmw'] ?? 0).toDouble(),
        passPriceCc: (m['pass_price_cc'] ?? 0).toDouble(),
        questionCount: m['question_count'] ?? 10,
        timePerQuestionSec: m['time_per_question_sec'] ?? 15,
        startTime: DateTime.tryParse(m['start_time']?.toString() ?? '') ?? DateTime.now(),
        endTime: m['end_time'] != null ? DateTime.tryParse(m['end_time'].toString()) : null,
        status: m['status'] ?? 'upcoming',
        maxParticipants: m['max_participants'],
        categoryFilter: m['category_filter'],
        difficultyFilter: m['difficulty_filter'],
        isFeatured: m['is_featured'] == true,
        bannerUrl: m['banner_url'],
        wagerCoins: m['wager_coins'] ?? 0,
        settledAt: m['settled_at'] != null ? DateTime.tryParse(m['settled_at'].toString()) : null,
        createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
      );

  bool get isFree => passPriceZmw <= 0 && passPriceCc <= 0;
  bool get hasWager => wagerCoins > 0;
  bool get isActive => status == 'active';
  bool get isUpcoming => status == 'upcoming';
  bool get isCompleted => status == 'completed';

  String get statusLabel {
    switch (status) {
      case 'active':
        return 'LIVE';
      case 'upcoming':
        return 'Upcoming';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }
}

class QuizEventParticipant {
  final String id;
  final String eventId;
  final String userId;
  int score;
  int correctCount;
  int totalQuestions;
  final DateTime passedAt;
  DateTime? completedAt;

  QuizEventParticipant({
    required this.id,
    required this.eventId,
    required this.userId,
    this.score = 0,
    this.correctCount = 0,
    this.totalQuestions = 0,
    DateTime? passedAt,
    this.completedAt,
  }) : passedAt = passedAt ?? DateTime.now();

  factory QuizEventParticipant.fromMap(Map<String, dynamic> m) =>
      QuizEventParticipant(
        id: m['id']?.toString() ?? '',
        eventId: m['event_id']?.toString() ?? '',
        userId: m['user_id']?.toString() ?? '',
        score: m['score'] ?? 0,
        correctCount: m['correct_count'] ?? 0,
        totalQuestions: m['total_questions'] ?? 0,
        passedAt: m['passed_at'] != null
            ? DateTime.tryParse(m['passed_at'].toString())
            : null,
        completedAt: m['completed_at'] != null
            ? DateTime.tryParse(m['completed_at'].toString())
            : null,
      );
}

class QuizPass {
  final String id;
  final String eventId;
  final String userId;
  final String? churchId;
  final String? paymentMethod;
  final String? paymentRef;
  final double amountZmw;
  final double amountCc;
  final String status;
  final DateTime purchasedAt;

  QuizPass({
    required this.id,
    required this.eventId,
    required this.userId,
    this.churchId,
    this.paymentMethod,
    this.paymentRef,
    this.amountZmw = 0,
    this.amountCc = 0,
    this.status = 'pending',
    DateTime? purchasedAt,
  }) : purchasedAt = purchasedAt ?? DateTime.now();

  factory QuizPass.fromMap(Map<String, dynamic> m) => QuizPass(
        id: m['id']?.toString() ?? '',
        eventId: m['event_id']?.toString() ?? '',
        userId: m['user_id']?.toString() ?? '',
        churchId: m['church_id']?.toString(),
        paymentMethod: m['payment_method'],
        paymentRef: m['payment_ref'],
        amountZmw: (m['amount_zmw'] ?? 0).toDouble(),
        amountCc: (m['amount_cc'] ?? 0).toDouble(),
        status: m['status'] ?? 'pending',
        purchasedAt: m['purchased_at'] != null
            ? DateTime.tryParse(m['purchased_at'].toString())
            : null,
      );

  bool get isPaid => status == 'paid';
}

/// Outcome of joining an event: joined, blocked because the wallet has
/// too few Church Coins (for wager stakes / CC pass), or failed.
enum JoinOutcome { joined, insufficientCoins, failed }

class QuizEventService {
  final SupabaseClient _client = Supabase.instance.client;
  final BibleQuizService _bqService = BibleQuizService();

  // ── Events ──

  Future<List<QuizEvent>> getUpcomingEvents({int limit = 20}) async {
    try {
      final res = await _client
          .from('quiz_events')
          .select()
          .or('status.eq.upcoming,status.eq.active')
          .order('start_time', ascending: true)
          .limit(limit);
      return (res as List).map((e) => QuizEvent.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<QuizEvent>> getAllEvents() async {
    try {
      final res = await _client
          .from('quiz_events')
          .select()
          .order('start_time', ascending: false)
          .limit(50);
      return (res as List).map((e) => QuizEvent.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<QuizEvent?> getEventById(String id) async {
    try {
      final res = await _client
          .from('quiz_events')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (res == null) return null;
      return QuizEvent.fromMap(res);
    } catch (_) {
      return null;
    }
  }

  Future<String?> createEvent({
    required String title,
    String? description,
    double passPriceZmw = 0,
    double passPriceCc = 0,
    int questionCount = 10,
    int timePerQuestionSec = 15,
    required DateTime startTime,
    DateTime? endTime,
    int? maxParticipants,
    String? categoryFilter,
    String? difficultyFilter,
    bool isFeatured = false,
    String? bannerUrl,
    int wagerCoins = 0,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 'Not authenticated';

    try {
      final res = await _client.from('quiz_events').insert({
        'title': title,
        'description': description,
        'created_by': userId,
        'pass_price_zmw': passPriceZmw,
        'pass_price_cc': passPriceCc,
        'question_count': questionCount,
        'time_per_question_sec': timePerQuestionSec,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime?.toIso8601String(),
        'max_participants': maxParticipants,
        'category_filter': categoryFilter,
        'difficulty_filter': difficultyFilter,
        'is_featured': isFeatured,
        'banner_url': bannerUrl,
        'wager_coins': wagerCoins,
      }).select('id').maybeSingle();

      return res?['id']?.toString();
    } catch (e) {
      return 'Database error: $e';
    }
  }

  Future<String?> updateEventStatus(String eventId, String status) async {
    try {
      await _client
          .from('quiz_events')
          .update({'status': status})
          .eq('id', eventId);
      return null;
    } catch (e) {
      return 'Update failed: $e';
    }
  }

  /// Host finishes the event: ranks players, pays 1st/2nd/3rd (wager events),
  /// marks the event completed. Returns null on success or an error string.
  Future<String?> completeEvent(String eventId) async {
    try {
      final res = await _client.rpc('complete_quiz_event', params: {
        'p_event_id': eventId,
      });
      final data = res as Map<String, dynamic>?;
      if (data?['success'] == true) return null;
      return data?['error']?.toString() ?? 'Failed to finish event';
    } catch (e) {
      return 'Finish failed: $e';
    }
  }

  /// Host cancels the event: refunds every staked wager, marks cancelled.
  Future<String?> cancelEvent(String eventId) async {
    try {
      final res = await _client.rpc('cancel_quiz_event', params: {
        'p_event_id': eventId,
      });
      final data = res as Map<String, dynamic>?;
      if (data?['success'] == true) return null;
      return data?['error']?.toString() ?? 'Failed to cancel event';
    } catch (e) {
      return 'Cancel failed: $e';
    }
  }

  /// Emits a tick whenever a participant row changes → live tournament
  /// scoreboards without polling.
  Stream<int> eventLeaderboardTicks(String eventId) {
    final channel = _client.channel('quiz_event_lb_$eventId');
    final controller = StreamController<int>.broadcast();
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'quiz_event_participants',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'event_id', value: eventId),
          callback: (payload) {
            if (!controller.isClosed) {
              controller.add(DateTime.now().millisecondsSinceEpoch);
            }
          },
        )
        .subscribe();
    return controller.stream;
  }

  // ── Participants ──

  Future<JoinOutcome> joinEvent(String eventId, {bool payCc = false}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return JoinOutcome.failed;

    try {
      final res = await _client.rpc('join_quiz_event', params: {
        'p_event_id': eventId,
        'p_pay_cc': payCc,
      });
      final result = res is Map<String, dynamic> ? res : <String, dynamic>{};
      if (result['success'] == true) return JoinOutcome.joined;
      if (result['error'] is String) {
        debugPrint('joinQuizEvent rejected: ${result['error']}');
        if (result['error'].toString().contains('Insufficient coins')) {
          return JoinOutcome.insufficientCoins;
        }
      }
      return JoinOutcome.failed;
    } catch (e) {
      debugPrint('joinQuizEvent error: $e');
      return JoinOutcome.failed;
    }
  }

  /// Lease the Quiz Engine by spending Church Coins (server-enforced amount).
  /// Returns true on success, false otherwise.
  Future<bool> leaseQuizEngineCc() async {
    try {
      final res = await _client.rpc('lease_quiz_engine_cc');
      final result = res is Map<String, dynamic> ? res : <String, dynamic>{};
      if (result['success'] == true) return true;
      if (result['error'] is String) {
        debugPrint('leaseQuizEngineCc rejected: ${result['error']}');
      }
      return false;
    } catch (e) {
      debugPrint('leaseQuizEngineCc error: $e');
      return false;
    }
  }

  Future<bool> isUserInEvent(String eventId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final res = await _client
          .from('quiz_event_participants')
          .select('id')
          .eq('event_id', eventId)
          .eq('user_id', userId)
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasUserPaidPass(String eventId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final res = await _client
          .from('quiz_passes')
          .select('id')
          .eq('event_id', eventId)
          .eq('user_id', userId)
          .eq('status', 'paid')
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> submitEventScore({
    required String eventId,
    required int score,
    required int correctCount,
    required int totalQuestions,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _client.from('quiz_event_participants').update({
        'score': score,
        'correct_count': correctCount,
        'total_questions': totalQuestions,
        'completed_at': DateTime.now().toIso8601String(),
      }).eq('event_id', eventId).eq('user_id', userId);
    } catch (e) {
      debugPrint('Failed to submit event score: $e');
    }
  }

  Future<int> getParticipantCount(String eventId) async {
    try {
      final res = await _client
          .from('quiz_event_participants')
          .select('id')
          .eq('event_id', eventId);
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getLeaderboard(String eventId) async {
    try {
      final res = await _client
          .from('quiz_event_participants')
          .select('score, correct_count, total_questions, user_id, profiles(full_name, avatar_url)')
          .eq('event_id', eventId)
          .order('score', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
  }

  // ── Passes ──

  Future<String?> purchasePass(String eventId, {String? paymentRef, double amountZmw = 0}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 'Not authenticated';

    try {
      await _client.from('quiz_passes').insert({
        'event_id': eventId,
        'user_id': userId,
        'payment_ref': paymentRef,
        'amount_zmw': amountZmw,
        'status': 'paid',
      });
      return null;
    } catch (e) {
      return 'Pass purchase failed: $e';
    }
  }

  // ── Batch Tournament Submission ──

  /// Submits all tournament answers in a single atomic RPC call.
  /// Returns {score, correct, total, accuracy}.
  Future<Map<String, dynamic>?> submitTournamentAnswersBatch({
    required String eventId,
    required List<String> questionIds,
    required List<int> answers,
    required List<int> responseTimesMs,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final res = await _client.rpc('submit_tournament_answers_batch', params: {
        'p_user_id': userId,
        'p_event_id': eventId,
        'p_question_ids': questionIds,
        'p_answers': answers,
        'p_response_times_ms': responseTimesMs,
      });

      if (res is Map<String, dynamic>) {
        return res;
      }
      return null;
    } catch (e) {
      debugPrint('Failed to submit tournament batch: $e');
      return null;
    }
  }

  /// Records answered questions for per-user deduplication.
  Future<void> recordAnsweredQuestions({
    required List<String> questionIds,
    String? matchId,
    String? eventId,
    List<bool>? isCorrect,
    List<int>? responseTimesMs,
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
      });
    } catch (e) {
      debugPrint('Failed to record answered questions: $e');
    }
  }

  /// Returns the number of unseen questions for the current user.
  Future<int> getUnseenQuestionCount({
    String? category,
    String? difficulty,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;

    try {
      final res = await _client.rpc('count_unseen_questions', params: {
        'p_user_id': userId,
        'p_category': category,
        'p_difficulty': difficulty,
      });
      return (res as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('Failed to count unseen questions: $e');
      return 0;
    }
  }

  /// Auto-generates questions if the unseen pool is low.
  /// Returns the number of newly inserted questions, or 0 if no generation was needed.
  Future<int> autoGenerateIfNeeded({
    int threshold = 50,
    int generateCount = 100,
    String? category,
    String? difficulty,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;

    try {
      final unseenCount = await getUnseenQuestionCount(
        category: category,
        difficulty: difficulty,
      );

      if (unseenCount >= threshold) return 0;

      // Fetch existing questions to exclude
      final existingRes = await _client
          .from('quiz_questions')
          .select('question')
          .limit(200);
      final excludeQuestions = (existingRes as List)
          .map((q) => q['question'] as String)
          .toList();

      // Call generate-quiz-batch Edge Function
      final session = _client.auth.currentSession;
      if (session == null) return 0;

      final response = await http.post(
        Uri.parse('${Env.supabaseUrl}/functions/v1/generate-quiz-batch'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': Env.supabaseAnonKey,
        },
        body: jsonEncode({
          'count': generateCount,
          'category': category,
          'difficulty': difficulty,
          'excludeQuestions': excludeQuestions,
          'auto': true,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final inserted = data['inserted'] as int? ?? 0;
        debugPrint('[QuizEvent] Auto-generated $inserted questions');
        return inserted;
      } else if (response.statusCode == 429) {
        debugPrint('[QuizEvent] Auto-generate throttled: ${response.body}');
        return 0;
      } else {
        debugPrint('[QuizEvent] Auto-generate failed: ${response.statusCode}');
        return 0;
      }
    } catch (e) {
      debugPrint('[QuizEvent] Auto-generate error: $e');
      return 0;
    }
  }

  // ── AI Questions for Events ──

  Future<List<QuizQuestion>> getEventQuestions(QuizEvent event, {List<String>? exclude}) async {
    // Try unseen questions first
    final dbQuestions = await _bqService.getUnseenQuestions(
      event.questionCount,
      category: event.categoryFilter,
      difficulty: event.difficultyFilter,
    );

    if (dbQuestions.length >= event.questionCount) {
      return dbQuestions.take(event.questionCount).toList();
    }

    // If insufficient unseen, auto-generate and retry
    if (dbQuestions.length < event.questionCount) {
      await autoGenerateIfNeeded(
        threshold: 0,
        generateCount: event.questionCount * 2,
        category: event.categoryFilter,
        difficulty: event.difficultyFilter,
      );

      // Retry with unseen after generation
      final retryQuestions = await _bqService.getUnseenQuestions(
        event.questionCount,
        category: event.categoryFilter,
        difficulty: event.difficultyFilter,
      );

      if (retryQuestions.isNotEmpty) {
        return retryQuestions.take(event.questionCount).toList();
      }
    }

    // Fallback: call generate-quiz-batch Edge Function (HuggingFace, no Gemini)
    if (dbQuestions.length < event.questionCount) {
      try {
        final need = event.questionCount - dbQuestions.length;
        final res = await _client.functions.invoke('generate-quiz-batch', body: {
          'count': need,
          'category': event.categoryFilter,
          'difficulty': event.difficultyFilter,
          'excludeQuestions': exclude ?? dbQuestions.map((q) => q.question).toList(),
        });
        final data = res.data as Map<String, dynamic>?;
        final generated = (data?['questions'] as List?) ?? [];
        if (generated.isNotEmpty) {
          final aiQuestions = generated.map((m) {
            final opts = List<String>.from((m as Map)['options'] ?? []);
            return QuizQuestion(
              id: 'ef_${DateTime.now().millisecondsSinceEpoch}_${opts.hashCode}',
              question: m['question'] ?? '',
              options: opts,
              correctAnswer: m['correct_answer'] ?? 0,
              difficulty: m['difficulty'] ?? 'Medium',
              category: m['category'] ?? 'General',
              scriptureReference: m['scripture_reference'],
              points: m['difficulty'] == 'Hard' ? 20 : m['difficulty'] == 'Medium' ? 15 : 10,
            );
          }).toList();
          return [...dbQuestions, ...aiQuestions].take(event.questionCount).toList();
        }
      } catch (e) {
        debugPrint('Quiz event AI fallback failed: $e');
      }
    }

    return dbQuestions;
  }
}

final quizEventServiceProvider = Provider((ref) => QuizEventService());
final upcomingEventsProvider = FutureProvider.autoDispose<List<QuizEvent>>((ref) {
  return ref.read(quizEventServiceProvider).getUpcomingEvents();
});
final allEventsProvider = FutureProvider.autoDispose<List<QuizEvent>>((ref) {
  return ref.read(quizEventServiceProvider).getAllEvents();
});
