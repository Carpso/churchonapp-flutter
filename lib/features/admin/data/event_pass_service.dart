import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EventPass {
  final String id;
  final String? eventId;
  final String? quizEventId;
  final String userId;
  final String passType;
  final double amountPaid;
  final String? paymentReference;
  final bool isUsed;
  final DateTime createdAt;

  EventPass({
    required this.id,
    this.eventId,
    this.quizEventId,
    required this.userId,
    required this.passType,
    this.amountPaid = 0,
    this.paymentReference,
    this.isUsed = false,
    required this.createdAt,
  });

  factory EventPass.fromMap(Map<String, dynamic> map) {
    return EventPass(
      id: map['id'] as String,
      eventId: map['event_id'] as String?,
      quizEventId: map['quiz_event_id'] as String?,
      userId: map['user_id'] as String,
      passType: map['pass_type'] as String,
      amountPaid: (map['amount_paid'] as num?)?.toDouble() ?? 0,
      paymentReference: map['payment_reference'] as String?,
      isUsed: map['is_used'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class EventPassService {
  final SupabaseService _supabase;

  EventPassService(this._supabase);

  Future<List<EventPass>> getMyPasses() async {
    final result = await _supabase.client
        .from('event_passes')
        .select('*')
        .eq('user_id', _supabase.client.auth.currentUser!.id)
        .order('created_at', ascending: false);
    return (result as List).map((e) => EventPass.fromMap(e)).toList();
  }

  Future<bool> hasPassForEvent(String quizEventId) async {
    final userId = _supabase.client.auth.currentUser!.id;
    final result = await _supabase.client
        .from('event_passes')
        .select('id')
        .eq('user_id', userId)
        .eq('quiz_event_id', quizEventId)
        .maybeSingle();
    return result != null;
  }

  Future<void> purchaseQuizPass({
    required String quizEventId,
    required double amount,
    String? paymentRef,
  }) async {
    final userId = _supabase.client.auth.currentUser!.id;
    await _supabase.client.from('event_passes').insert({
      'quiz_event_id': quizEventId,
      'user_id': userId,
      'pass_type': 'quiz_pass',
      'amount_paid': amount,
      'payment_reference': paymentRef,
    });
  }

  Future<void> markPassUsed(String passId) async {
    await _supabase.client.from('event_passes').update({'is_used': true}).eq('id', passId);
  }
}

final eventPassServiceProvider = Provider<EventPassService>((ref) {
  final supabase = ref.read(supabaseServiceProvider);
  return EventPassService(supabase);
});
