import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'job_model.dart';

class JobsService {
  final SupabaseClient _client;

  JobsService(this._client);

  Future<List<Job>> getJobs() async {
    final response = await _client
        .from('jobs')
        .select()
        .order('created_at', ascending: false);
    
    return (response as List).map((e) => Job.fromMap(e)).toList();
  }

  Future<void> postJob(Job job) async {
    final user = _client.auth.currentUser;
    final map = job.toMap();
    if (user != null) map['user_id'] = user.id;
    await _client.from('jobs').insert(map);
  }

  Stream<List<Job>> streamJobs() {
    return _client
        .from('jobs')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => data.map((e) => Job.fromMap(e)).toList());
  }

  Future<void> applyForJob(JobApplication application) async {
    await _client.from('job_applications').insert(application.toMap());
  }

  Stream<List<JobApplication>> streamApplicationsForJob(String jobId) {
    return _client
        .from('job_applications')
        .stream(primaryKey: ['id'])
        .eq('job_id', jobId)
        .order('created_at', ascending: false)
        .map((data) => data.map((e) => JobApplication.fromMap(e)).toList());
  }

  Future<void> updateApplicationStatus(String id, String status) async {
    await _client.from('job_applications').update({'status': status}).eq('id', id);
  }

  Future<void> promoteJobWithMobileMoney({
    required String jobId,
    required double amount,
    required String phone,
  }) async {
    await _client.from('jobs').update({'is_featured': true}).eq('id', jobId);
  }

  Future<void> editJob(Job job) async {
    await _client.from('jobs').update(job.toMap()).eq('id', job.id);
  }

  Stream<List<Job>> streamMyJobPostings() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return Stream.value([]);
    return _client
        .from('jobs')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map((data) => data.map((e) => Job.fromMap(e)).toList());
  }
}

final jobsServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return JobsService(client);
});

final jobsPortalProvider = StreamProvider<List<Job>>((ref) {
  return ref.watch(jobsServiceProvider).streamJobs();
});

final myJobPostingsProvider = StreamProvider<List<Job>>((ref) {
  return ref.watch(jobsServiceProvider).streamMyJobPostings();
});

final jobApplicationsProvider = StreamProvider.family<List<JobApplication>, String>((ref, jobId) {
  return ref.watch(jobsServiceProvider).streamApplicationsForJob(jobId);
});
