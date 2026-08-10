import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/fasting_service.dart';

class FastingHistoryScreen extends ConsumerWidget {
  const FastingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final spiritualHistory = ref.watch(fastHistoryProvider);
    final techHistory = ref.watch(techFastHistoryProvider);

    final spiritualList = spiritualHistory.value ?? [];
    final techList = techHistory.value ?? [];

    final now = DateTime.now();
    final yearStart = DateTime(now.year, 1, 1);
    final yearSpiritual = spiritualList.where((f) => f.startedAt.isAfter(yearStart)).toList();
    final yearTech = techList.where((f) => f.startTime.isAfter(yearStart)).toList();
    final completedSpiritual = spiritualList.where((f) => f.status == 'completed').toList();
    final completedTech = techList.where((f) => !f.isCurrentlyActive).toList();
    final totalDaysSpiritual = completedSpiritual.fold<int>(0, (sum, f) => sum + f.durationDays);
    final totalHoursTech = completedTech.fold<int>(0, (sum, f) {
      final hours = f.endTime.difference(f.startTime).inHours;
      return sum + hours;
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Fasting History", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildYearStatsCard(
              year: now.year,
              spiritualCount: yearSpiritual.length,
              techCount: yearTech.length,
              totalDaysFasted: totalDaysSpiritual,
              totalHoursDisconnected: totalHoursTech,
            ),
            const SizedBox(height: 20),
            if (spiritualList.isNotEmpty) ...[
              _buildSectionHeader("Spiritual Fasts", LucideIcons.heart, Colors.brown, spiritualList.length),
              const SizedBox(height: 10),
              ...spiritualList.map((fast) => _buildSpiritualFastCard(fast)),
              const SizedBox(height: 20),
            ],
            if (techList.isNotEmpty) ...[
              _buildSectionHeader("Tech Fasts", LucideIcons.smartphone, Colors.indigo, techList.length),
              const SizedBox(height: 10),
              ...techList.map((schedule) => _buildTechFastCard(schedule)),
              const SizedBox(height: 20),
            ],
            if (spiritualList.isEmpty && techList.isEmpty)
              _buildEmptyState(),
          ],
        ),
      ),
    );
  }

  Widget _buildYearStatsCard({
    required int year,
    required int spiritualCount,
    required int techCount,
    required int totalDaysFasted,
    required int totalHoursDisconnected,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B4513), Color(0xFFA0522D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.brown.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.barChart3, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text("$year FASTING JOURNEY", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildStatItem("$spiritualCount", "Spiritual\nFasts"),
              _buildStatItem("$techCount", "Tech\nFasts"),
              _buildStatItem("$totalDaysFasted", "Days\nFasted"),
              _buildStatItem("$totalHoursDisconnected", "Hours\nDisconnected"),
            ],
          ),
          const SizedBox(height: 15),
          if (spiritualCount + techCount > 0)
            Text(
              "You've completed ${spiritualCount + techCount} fasts this year. Keep growing!",
              style: const TextStyle(color: Colors.white60, fontSize: 12, fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color, int count) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Text("$count", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildSpiritualFastCard(UserFast fast) {
    final isCompleted = fast.status == 'completed';
    final isActive = fast.isActive;
    final daysAgo = DateTime.now().difference(fast.startedAt).inDays;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isCompleted ? Colors.green.withValues(alpha: 0.2) : Colors.brown.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isCompleted ? Colors.green.withValues(alpha: 0.1) : (isActive ? Colors.orange.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isCompleted ? LucideIcons.checkCircle2 : (isActive ? LucideIcons.flame : LucideIcons.xCircle),
              color: isCompleted ? Colors.green : (isActive ? Colors.orange : Colors.grey),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fast.fastType, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 3),
                Text(
                  "${fast.durationDays} days • Started ${daysAgo == 0 ? 'today' : '$daysAgo days ago'}",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatDateRange(fast.startedAt, fast.completedAt),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isCompleted ? Colors.green.withValues(alpha: 0.1) : (isActive ? Colors.orange.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              isCompleted ? "COMPLETED" : (isActive ? "ACTIVE" : "ENDED"),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isCompleted ? Colors.green : (isActive ? Colors.orange : Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechFastCard(FastSchedule schedule) {
    final isActive = schedule.isCurrentlyActive;
    final isCompleted = !isActive;
    final durationHours = schedule.endTime.difference(schedule.startTime).inHours;
    final label = FastingService.techFastLabels[schedule.fastType] ?? schedule.fastType;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isCompleted ? Colors.green.withValues(alpha: 0.2) : Colors.indigo.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isCompleted ? Colors.green.withValues(alpha: 0.1) : (isActive ? Colors.indigo.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isCompleted ? LucideIcons.checkCircle2 : (isActive ? LucideIcons.smartphone : LucideIcons.xCircle),
              color: isCompleted ? Colors.green : (isActive ? Colors.indigo : Colors.grey),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 3),
                Text(
                  "$durationHours hours • ${schedule.blockedApps.length} categories blocked",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatDateRange(schedule.startTime, schedule.endTime),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isCompleted ? Colors.green.withValues(alpha: 0.1) : Colors.indigo.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              isCompleted ? "COMPLETED" : "ACTIVE",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isCompleted ? Colors.green : Colors.indigo,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(LucideIcons.flame, size: 60, color: Colors.brown.withValues(alpha: 0.3)),
            const SizedBox(height: 20),
            const Text("No Fasts Yet", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.brown)),
            const SizedBox(height: 8),
            const Text(
              "Start your first fast to see your history here. Every journey begins with a single step.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateRange(DateTime start, DateTime? end) {
    final s = '${start.day}/${start.month}/${start.year}';
    if (end == null) return '$s — Present';
    final e = '${end.day}/${end.month}/${end.year}';
    return '$s — $e';
  }
}
