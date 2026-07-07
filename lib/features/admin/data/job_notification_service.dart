import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class JobNotification {
  final String id;
  final String userId;
  final String? jobId;
  final String type;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  JobNotification({
    required this.id,
    required this.userId,
    this.jobId,
    required this.type,
    required this.message,
    this.isRead = false,
    required this.createdAt,
  });

  factory JobNotification.fromMap(Map<String, dynamic> map) {
    return JobNotification(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      jobId: map['job_id'] as String?,
      type: map['type'] as String,
      message: map['message'] as String,
      isRead: map['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class JobNotificationService {
  final SupabaseService _supabase;

  JobNotificationService(this._supabase);

  Future<List<JobNotification>> getNotifications() async {
    final result = await _supabase.client
        .from('job_notifications')
        .select('*')
        .order('created_at', ascending: false);
    return (result as List).map((e) => JobNotification.fromMap(e)).toList();
  }

  Future<void> markAsRead(String id) async {
    await _supabase.client.from('job_notifications').update({'is_read': true}).eq('id', id);
  }

  Future<void> markAllAsRead() async {
    await _supabase.client.from('job_notifications').update({'is_read': true}).eq('user_id', _supabase.client.auth.currentUser!.id);
  }

  Future<int> getUnreadCount() async {
    final result = await _supabase.client
        .from('job_notifications')
        .select('id')
        .eq('user_id', _supabase.client.auth.currentUser!.id)
        .eq('is_read', false);
    return (result as List).length;
  }
}

final jobNotificationServiceProvider = Provider<JobNotificationService>((ref) {
  final supabase = ref.read(supabaseServiceProvider);
  return JobNotificationService(supabase);
});
