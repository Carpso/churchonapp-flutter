import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import '../data/jobs_service.dart';
import '../data/job_model.dart';
import 'post_job_screen.dart';
import 'job_promotion_sheet.dart';

class MyJobsScreen extends ConsumerWidget {
  const MyJobsScreen({super.key});

  Future<void> _deleteJob(BuildContext context, WidgetRef ref, Job job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Delete Job"),
        content: Text("Delete \"${job.title}\"? This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("DELETE", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await Supabase.instance.client.from('jobs').delete().eq('id', job.id);
        ref.invalidate(myJobPostingsProvider);
        if (context.mounted) PremiumToast.showSuccess(context, "Job deleted");
      } catch (e) {
        if (context.mounted) PremiumToast.showError(context, "Failed to delete job");
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(myJobPostingsProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("My Job Postings", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: jobsAsync.when(
        data: (jobs) {
          if (jobs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.briefcase, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 20),
                  const Text("You haven't posted any jobs yet", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text("Post a job to find talent in your community.", style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/jobs/post'),
                    icon: const Icon(LucideIcons.plus),
                    label: const Text("Post a Job"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 15),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(job.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 4),
                              Text(job.company, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                            ],
                          ),
                        ),
                        if (job.isPromoted)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.zap, color: Colors.amber, size: 12),
                                SizedBox(width: 3),
                                Text("PROMOTED", style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(LucideIcons.mapPin, size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Expanded(child: Text(job.location, style: TextStyle(color: Colors.grey.shade500, fontSize: 11))),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => context.push('/jobs/manage', extra: job),
                            icon: const Icon(LucideIcons.users, size: 14),
                            label: const Text("APPLICATIONS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            style: OutlinedButton.styleFrom(
foregroundColor: Theme.of(context).primaryColor,
                side: BorderSide(color: Theme.of(context).primaryColor),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => showModalBottomSheet(
                              context: context,
                              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
                              builder: (_) => JobPromotionSheet(jobId: job.id),
                            ),
                            icon: const Icon(LucideIcons.zap, size: 14),
                            label: const Text("PROMOTE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.amber.shade700,
                              side: BorderSide(color: Colors.amber.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => PostJobScreen(editJob: job),
                            )),
                            icon: const Icon(LucideIcons.pencil, size: 14),
                            label: const Text("EDIT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey.shade600,
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _deleteJob(context, ref, job),
                            icon: const Icon(LucideIcons.trash2, size: 14),
                            label: const Text("DELETE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: const Center(child: CircularProgressIndicator()),
          ),
        error: (e, _) => Center(child: Text("Error: $e")),
      ),
    );
  }
}
