import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/empty_state_widget.dart';
import 'package:church_on_app/features/bible_study/data/bible_study_service.dart';
import 'package:church_on_app/features/bible_study/data/bible_study_providers.dart';
import 'package:church_on_app/features/bible/data/exegesis_data.dart';

class BibleStudyListScreen extends ConsumerStatefulWidget {
  const BibleStudyListScreen({super.key});

  @override
  ConsumerState<BibleStudyListScreen> createState() => _BibleStudyListScreenState();
}

class _BibleStudyListScreenState extends ConsumerState<BibleStudyListScreen> {
  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final tenantId = tenant?.id;
    final profileAsync = ref.watch(profileProvider);
    final isLeader = profileAsync.value?.isLeadershipTeam ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      appBar: AppBar(
        title: Text('${tenant?.name ?? 'Church'} Bible Studies'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.bookOpen),
            onPressed: () => _showExegesisPanel(),
          ),
        ],
      ),
      floatingActionButton: isLeader
          ? FloatingActionButton(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              onPressed: () => context.push('/bible-study/create'),
              child: const Icon(LucideIcons.plus),
            )
          : null,
      body: tenantId == null
          ? const EmptyStateWidget(
              icon: LucideIcons.alertCircle,
              title: 'No church selected',
              subtitle: 'Please select a church to view Bible studies',
            )
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(studiesProvider(tenantId));
                ref.invalidate(upcomingStudiesProvider(tenantId));
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildUpcomingSection(tenantId),
                    _buildAllStudiesSection(tenantId),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildUpcomingSection(String tenantId) {
    final upcomingAsync = ref.watch(upcomingStudiesProvider(tenantId));
    return upcomingAsync.when(
      data: (studies) {
        if (studies.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Row(
                children: [
                  const Icon(LucideIcons.calendarCheck, color: Colors.indigo, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Upcoming Studies',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: studies.length,
                itemBuilder: (context, index) => _buildUpcomingCard(studies[index]),
              ),
            ),
          ],
        );
      },
      loading: () => SizedBox(
        height: 200,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: List.generate(3, (i) => Container(
            width: 240,
            margin: const EdgeInsets.only(right: 12),
            child: const ShimmerLoader.rectangular(height: 160),
          )),
        ),
      ),
      error: (e, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildUpcomingCard(BibleStudy study) {
    final dateFormat = DateFormat('MMM d, yyyy');
    return GestureDetector(
      onTap: () => context.push('/bible-study/${study.id}'),
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.indigo.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _statusIcon(study.status),
                color: Colors.white.withValues(alpha: 0.8),
                size: 24,
              ),
              const Spacer(),
              Text(
                study.title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                dateFormat.format(study.date),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                '${study.time}  •  ${study.leader}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllStudiesSection(String tenantId) {
    final studiesAsync = ref.watch(studiesProvider(tenantId));
    return studiesAsync.when(
      data: (studies) {
        if (studies.isEmpty) {
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.4,
            child: const EmptyStateWidget(
              icon: LucideIcons.bookOpen,
              title: 'No Bible studies yet',
              subtitle: 'Your church hasn\'t scheduled any Bible studies yet',
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Row(
                children: [
                  const Icon(LucideIcons.list, color: Colors.indigo, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'All Studies',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: studies.length,
                itemBuilder: (context, index) => _buildStudyTile(studies[index]),
              ),
            ),
          ],
        );
      },
      loading: () => ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: ShimmerLoader.rectangular(height: 110),
        ),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildStudyTile(BibleStudy study) {
    final dateFormat = DateFormat('MMM d, yyyy');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => context.push('/bible-study/${study.id}'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: _statusColor(study.status),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      study.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${dateFormat.format(study.date)}  •  ${study.time}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${study.leader}  •  ${study.currentAttendees}/${study.maxAttendees > 0 ? study.maxAttendees : '∞'} attending',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(study.status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(
          color: _statusColor(status),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'scheduled':
        return Colors.blue;
      case 'ongoing':
        return Colors.green;
      case 'completed':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'scheduled':
        return LucideIcons.clock;
      case 'ongoing':
        return LucideIcons.playCircle;
      case 'completed':
        return LucideIcons.checkCircle;
      case 'cancelled':
        return LucideIcons.xCircle;
      default:
        return LucideIcons.helpCircle;
    }
  }

  void _showExegesisPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Greek & Hebrew Lexicon',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Original language word studies for deeper understanding',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const Divider(height: 24),
            Expanded(
              child: ListView.separated(
                itemCount: exegesisData.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (_, i) {
                  final word = exegesisData[i];
                  return ExpansionTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        word.word[0].toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ),
                    title: Text(word.word, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${word.language} · ${word.strongsNumber}', style: const TextStyle(fontSize: 11)),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(word.transliteration, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                            const SizedBox(height: 8),
                            Text(word.definition, style: const TextStyle(fontSize: 13, height: 1.5)),
                            if (word.notes.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(word.notes, style: const TextStyle(fontSize: 12, color: Colors.indigo, height: 1.4)),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              children: word.usageVerses.map((v) => Chip(
                                label: Text(v, style: const TextStyle(fontSize: 11)),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              )).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
