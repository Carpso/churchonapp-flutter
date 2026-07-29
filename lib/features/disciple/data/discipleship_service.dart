import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final discipleshipServiceProvider = Provider<DiscipleshipService>((ref) => DiscipleshipService());

class DiscipleshipService {
  final _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getMentors() async {
    final data = await _supabase
        .from('profiles')
        .select('id, full_name, avatar_url, phone_number, bio')
        .eq('role', 'pastor')
        .limit(20);
    return data;
  }

  Future<List<Map<String, dynamic>>> getMentees(String mentorId) async {
    final data = await _supabase
        .from('discipleship_relationships')
        .select('*, mentee:profiles!mentee_id(*)')
        .eq('mentor_id', mentorId);
    return data;
  }

  Future<List<Map<String, dynamic>>> getMilestones(String discipleId) async {
    final data = await _supabase
        .from('discipleship_milestones')
        .select('id, disciple_id, title, description, completed_at')
        .eq('disciple_id', discipleId)
        .order('completed_at', ascending: false);
    return data;
  }

  Future<void> addMilestone({
    required String discipleId,
    required String title,
    String? description,
  }) async {
    await _supabase.from('discipleship_milestones').insert({
      'disciple_id': discipleId,
      'title': title,
      'description': description,
      'completed_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> requestMentorship(String mentorId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    await _supabase.from('discipleship_relationships').insert({
      'mentor_id': mentorId,
      'mentee_id': user.id,
      'status': 'pending',
      'started_at': DateTime.now().toIso8601String(),
    });
  }
}
