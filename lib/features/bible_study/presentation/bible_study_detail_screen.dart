import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/bible_study/data/bible_study_service.dart';
import 'package:church_on_app/features/bible_study/data/bible_study_providers.dart';

class BibleStudyDetailScreen extends ConsumerStatefulWidget {
  final String studyId;

  const BibleStudyDetailScreen({super.key, required this.studyId});

  @override
  ConsumerState<BibleStudyDetailScreen> createState() => _BibleStudyDetailScreenState();
}

class _BibleStudyDetailScreenState extends ConsumerState<BibleStudyDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.value;
    final auth = ref.watch(authProvider);
    final isLeader = profile?.isLeadershipTeam ?? false;
    final tenant = ref.watch(currentTenantProvider);
    final tenantId = tenant?.id ?? '';

    final studiesAsync = ref.watch(studiesProvider(tenantId));
    BibleStudy? study;
    if (studiesAsync.value != null) {
      try {
        study = studiesAsync.value!.firstWhere((s) => s.id == widget.studyId);
      } catch (_) {
        study = null;
      }
    }

    final attendanceAsync = ref.watch(attendanceProvider(widget.studyId));
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy');
    final hasAttended = attendanceAsync.value?.any((a) => a.userId == auth.user?.id) ?? false;

    if (study == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.black,
        ),
        body: Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor)),
        ),
      );
    }

    final s = study;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.black,
        title: const Text('Bible Study'),
        actions: isLeader
            ? [
                IconButton(
                  icon: const Icon(LucideIcons.pencil),
                  onPressed: () => context.push(
                    '/bible-study/${widget.studyId}/edit',
                    extra: study,
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.trash2),
                  onPressed: () => _confirmDelete(s),
                ),
              ]
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(s),
            const SizedBox(height: 20),
            _buildDetailRow(LucideIcons.calendar, 'Date', dateFormat.format(s.date)),
            _buildDetailRow(LucideIcons.clock, 'Time', s.time),
            _buildDetailRow(LucideIcons.user, 'Leader', s.leader),
            _buildDetailRow(LucideIcons.mapPin, 'Location', s.location),
            if (s.maxAttendees > 0)
              _buildDetailRow(LucideIcons.users, 'Attendees', '${s.currentAttendees}/${s.maxAttendees}'),
            _buildDetailRow(LucideIcons.info, 'Status', s.status[0].toUpperCase() + s.status.substring(1)),
            if (s.materialsUrl != null && s.materialsUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildDetailRow(LucideIcons.fileText, 'Materials', s.materialsUrl!),
            ],
            const SizedBox(height: 20),
            _buildSectionTitle('Description'),
            const SizedBox(height: 8),
            Text(
              s.description.isEmpty ? 'No description provided.' : s.description,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            if (!hasAttended)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _attendStudy(s),
                  icon: const Icon(LucideIcons.checkCircle),
                  label: const Text('Mark Attendance'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.checkCircle, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Attendance Recorded',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            _buildSectionTitle('Attendance List'),
            const SizedBox(height: 8),
            attendanceAsync.when(
              data: (attendance) {
                if (attendance.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text('No attendance records yet', style: TextStyle(color: Colors.grey)),
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: attendance.length,
                  itemBuilder: (context, index) {
                    final record = attendance[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: record.attended ? Colors.green.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                            child: Text(
                              record.userName.isNotEmpty ? record.userName[0].toUpperCase() : '?',
                              style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(record.userName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (record.notes != null && record.notes!.isNotEmpty)
                                  Text(record.notes!, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                              ],
                            ),
                          ),
                          Icon(
                            record.attended ? LucideIcons.checkCircle : LucideIcons.clock,
                            color: record.attended ? Colors.green : Colors.orange,
                            size: 20,
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
              child: Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor)),
            ),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BibleStudy study) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFDA03), Color(0xFFE8A400)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            study.title,
            style: const TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              study.status[0].toUpperCase() + study.status.substring(1),
              style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).primaryColor),
          const SizedBox(width: 10),
          Text('$label: ', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(width: 4, height: 20, decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
      ],
    );
  }

  Future<void> _attendStudy(BibleStudy study) async {
    final authState = ref.read(authProvider);
    final profile = ref.read(profileProvider).value;
    if (authState.user == null || profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login to mark attendance')));
      return;
    }

    try {
      final service = ref.read(bibleStudyServiceProvider);
      await service.attendStudy(study.id, authState.user!.id, profile.name);
      ref.invalidate(attendanceProvider(study.id));
      ref.invalidate(upcomingStudiesProvider(study.tenantId));
      ref.invalidate(studiesProvider(study.tenantId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Attendance recorded!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _confirmDelete(BibleStudy study) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Study'),
        content: Text('Are you sure you want to delete "${study.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(bibleStudyServiceProvider).deleteStudy(study.id);
                ref.invalidate(studiesProvider(study.tenantId));
                ref.invalidate(upcomingStudiesProvider(study.tenantId));
                if (mounted) context.pop();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
