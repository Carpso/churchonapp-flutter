import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/job_model.dart';
import 'job_details_screen.dart';

/// Deep-link entry point for a shared job: `https://churchonapp.com/jobs/<id>`.
///
/// In-app navigation pushes `JobDetailsScreen` directly with a `Job` in
/// `extra`, which a link from WhatsApp/push cannot supply — so this resolves the
/// job by id first, then shows the normal details screen.
class JobByIdScreen extends StatefulWidget {
  final String jobId;
  const JobByIdScreen({super.key, required this.jobId});

  @override
  State<JobByIdScreen> createState() => _JobByIdScreenState();
}

class _JobByIdScreenState extends State<JobByIdScreen> {
  Job? _job;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client
          .from('jobs')
          .select()
          .eq('id', widget.jobId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (row == null) {
          _error = 'This job is no longer available.';
        } else {
          _job = Job.fromMap(Map<String, dynamic>.from(row));
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this job.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_job == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Job')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.briefcase, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(_error ?? 'Job not found',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _load();
                  },
                  child: const Text('RETRY'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return JobDetailsScreen(job: _job!);
  }
}
