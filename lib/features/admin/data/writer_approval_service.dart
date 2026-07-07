import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WriterApplication {
  final String id;
  final String userId;
  final String fullName;
  final String? email;
  final String? phone;
  final String? reason;
  final String? writingSamplesUrl;
  final String status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final DateTime createdAt;

  WriterApplication({
    required this.id,
    required this.userId,
    required this.fullName,
    this.email,
    this.phone,
    this.reason,
    this.writingSamplesUrl,
    this.status = 'pending',
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
    required this.createdAt,
  });

  factory WriterApplication.fromMap(Map<String, dynamic> map) {
    return WriterApplication(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      fullName: map['full_name'] as String,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      reason: map['reason'] as String?,
      writingSamplesUrl: map['writing_samples_url'] as String?,
      status: map['status'] as String? ?? 'pending',
      reviewedBy: map['reviewed_by'] as String?,
      reviewedAt: map['reviewed_at'] != null ? DateTime.parse(map['reviewed_at'] as String) : null,
      rejectionReason: map['rejection_reason'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class WriterApprovalService {
  final SupabaseService _supabase;

  WriterApprovalService(this._supabase);

  Future<List<WriterApplication>> getPendingApplications() async {
    final result = await _supabase.client
        .from('writer_applications')
        .select('*')
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return (result as List).map((e) => WriterApplication.fromMap(e)).toList();
  }

  Future<WriterApplication?> getMyApplication() async {
    final userId = _supabase.client.auth.currentUser!.id;
    final result = await _supabase.client
        .from('writer_applications')
        .select('*')
        .eq('user_id', userId)
        .maybeSingle();
    if (result == null) return null;
    return WriterApplication.fromMap(result);
  }

  Future<void> applyAsWriter({
    required String fullName,
    String? email,
    String? phone,
    String? reason,
    String? writingSamplesUrl,
  }) async {
    final userId = _supabase.client.auth.currentUser!.id;
    await _supabase.client.from('writer_applications').insert({
      'user_id': userId,
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'reason': reason,
      'writing_samples_url': writingSamplesUrl,
    });
  }

  Future<void> approveApplication(String applicationId) async {
    final userId = _supabase.client.auth.currentUser!.id;
    await _supabase.client.from('writer_applications').update({
      'status': 'approved',
      'reviewed_by': userId,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', applicationId);
  }

  Future<void> rejectApplication(String applicationId, {String? reason}) async {
    final userId = _supabase.client.auth.currentUser!.id;
    await _supabase.client.from('writer_applications').update({
      'status': 'rejected',
      'reviewed_by': userId,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      'rejection_reason': reason,
    }).eq('id', applicationId);
  }
}

final writerApprovalServiceProvider = Provider<WriterApprovalService>((ref) {
  final supabase = ref.read(supabaseServiceProvider);
  return WriterApprovalService(supabase);
});

final pendingWriterApplicationsProvider = FutureProvider<List<WriterApplication>>((ref) async {
  return ref.read(writerApprovalServiceProvider).getPendingApplications();
});
