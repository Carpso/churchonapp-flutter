import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/job_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/jobs_service.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class JobDetailsScreen extends ConsumerWidget {
  final Job job;
  const JobDetailsScreen({super.key, required this.job});

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authProvider).user;
    final profile = ref.read(profileProvider).value;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please login to apply")));
      return;
    }

    final application = JobApplication(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      jobId: job.id,
      applicantId: user.id,
      applicantName: profile?.name ?? "Citizen",
      status: 'pending',
      createdAt: DateTime.now(),
    );

    try {
      await ref.read(jobsServiceProvider).applyForJob(application);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Application submitted successfully!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Job Opportunity", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Theme.of(context).primaryColor,
                    child: const Icon(LucideIcons.briefcase, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(job.title, style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.bold)),
                        Text(job.company, style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            _buildInfoRow(context, LucideIcons.mapPin, "Location", job.location),
            _buildInfoRow(context, LucideIcons.clock, "Job Type", job.type),
            if (job.salary != null) _buildInfoRow(context, LucideIcons.banknote, "Salary / Stipend", job.salary!),
            _buildInfoRow(context, LucideIcons.mail, "Contact", job.contact, onTap: () async {
              final uri = Uri.tryParse(job.contact);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.inAppWebView);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Could not open: ${job.contact}")),
                  );
                }
              }
            }),
            const Divider(height: 40),
            const Text("Job Description", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(job.description, style: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87)),
            const SizedBox(height: 40),
            if (ref.watch(authProvider).user?.id == job.employerId)
              ElevatedButton(
                onPressed: () => context.push('/jobs/manage', extra: job),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text("MANAGE APPLICATIONS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              )
            else
              ElevatedButton(
                onPressed: () => _apply(context, ref),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text("APPLY FOR THIS ROLE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String value, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: Row(
          children: [
            Icon(icon, size: 20, color: onTap != null ? Theme.of(context).primaryColor : Colors.grey),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1)),
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: onTap != null ? Theme.of(context).primaryColor : null, decoration: onTap != null ? TextDecoration.underline : null)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

