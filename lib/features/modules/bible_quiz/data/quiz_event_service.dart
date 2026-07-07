import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/gemini_service.dart';
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
        createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
      );

  bool get isFree => passPriceZmw <= 0 && passPriceCc <= 0;
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

  // ── Participants ──

  Future<bool> joinEvent(String eventId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      await _client.from('quiz_event_participants').insert({
        'event_id': eventId,
        'user_id': userId,
      });
      return true;
    } catch (_) {
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

  // ── AI Questions for Events ──

  Future<List<QuizQuestion>> getEventQuestions(QuizEvent event, {GeminiService? gemini, List<String>? exclude}) async {
    final dbQuestions = await _bqService.getRandomQuestions(
      event.questionCount,
      category: event.categoryFilter,
      difficulty: event.difficultyFilter,
    );

    if (dbQuestions.length >= event.questionCount) {
      return dbQuestions.take(event.questionCount).toList();
    }

    // Top up with AI-generated questions
    if (gemini != null) {
      final aiRaw = await gemini.generateBibleQuizQuestions(
        count: event.questionCount - dbQuestions.length,
        category: event.categoryFilter,
        difficulty: event.difficultyFilter,
        excludeQuestions: exclude ?? dbQuestions.map((q) => q.question).toList(),
      );

      if (aiRaw.isNotEmpty) {
        final aiQuestions = aiRaw.map((m) {
          final opts = List<String>.from(m['options'] ?? []);
          return QuizQuestion(
            id: 'ai_${DateTime.now().millisecondsSinceEpoch}_${m['question'].hashCode}',
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
