import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/reading_plan_service.dart';

class StudyPlansScreen extends ConsumerWidget {
  const StudyPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(readingPlansProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Study Plans", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: plansAsync.when(
        data: (plans) => ListView.builder(
          padding: const EdgeInsets.all(25),
          itemCount: plans.length,
          itemBuilder: (context, index) => _buildPlanCard(context, ref, plans[index]),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Error: $e")),
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context, WidgetRef ref, ReadingPlan plan) {
    final progress = plan.completedDays / plan.totalDays;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.indigo.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(plan.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text("${plan.totalDays} Days", style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(plan.description, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("${plan.completedDays} / ${plan.totalDays} completed", style: TextStyle(color: Colors.indigo.shade800, fontWeight: FontWeight.bold, fontSize: 12)),
              Text("${(progress * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: const Color(0xFFF1F5F9),
            color: Colors.indigo,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => _openPlanDetails(context, ref, plan),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 45),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: Text(plan.completedDays > 0 ? "CONTINUE PLAN" : "START PLAN", style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openPlanDetails(BuildContext context, WidgetRef ref, ReadingPlan plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PlanDetailSheet(plan: plan, ref: ref),
    );
  }
}

class _PlanDetailSheet extends StatefulWidget {
  final ReadingPlan plan;
  final WidgetRef ref;
  const _PlanDetailSheet({required this.plan, required this.ref});

  @override
  State<_PlanDetailSheet> createState() => _PlanDetailSheetState();
}

class _PlanDetailSheetState extends State<_PlanDetailSheet> {
  late ReadingPlan _plan;

  @override
  void initState() {
    super.initState();
    _plan = widget.plan;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFFAEB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.all(25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_plan.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(_plan.description, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 25),
          const Text("DAILY SCRIPTURE GUIDES", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 15),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _plan.totalDays,
              itemBuilder: (context, idx) {
                final isDone = idx < _plan.completedDays;
                final isNext = idx == _plan.completedDays;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isDone ? LucideIcons.checkCircle2 : LucideIcons.circle,
                    color: isDone ? Colors.green : (isNext ? Colors.indigo : Colors.grey),
                  ),
                  title: Text(
                    "Day ${idx + 1}: ${_plan.dailyVerses[idx]}",
                    style: TextStyle(
                      fontWeight: isNext ? FontWeight.bold : FontWeight.normal,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      color: isDone ? Colors.grey : Colors.black87,
                    ),
                  ),
                  trailing: isNext
                      ? ElevatedButton(
                          onPressed: () async {
                            await widget.ref.read(readingPlanServiceProvider).completeDay(_plan.id);
                            widget.ref.invalidate(readingPlansProvider);
                            setState(() => _plan.completedDays++);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text("Day completed! +10 Loyalty Coins earned."),
                                backgroundColor: Colors.green,
                              ));
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(60, 30),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text("READ", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      : null,
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
