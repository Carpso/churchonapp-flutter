import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import '../data/reading_plan_service.dart';
import 'live_scripture_text.dart';
import 'package:church_on_app/core/services/coins_service.dart';

class StudyPlansScreen extends ConsumerWidget {
  const StudyPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(readingPlansProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Study Plans", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.black,
      ),
      body: plansAsync.when(
        data: (plans) {
          if (plans.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.bookOpen, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text("No study plans yet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text("Start a daily Bible reading plan\nto build your faith habit.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(25),
            itemCount: plans.length,
            itemBuilder: (context, index) => _buildPlanCard(context, ref, plans[index]),
          );
        },
        loading: () => const ListSkeleton(count: 3),
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
        boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
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
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text("${plan.totalDays} Days", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(plan.description, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("${plan.completedDays} / ${plan.totalDays} completed", style: TextStyle(color: Theme.of(context).primaryColor.withValues(alpha: 0.9), fontWeight: FontWeight.bold, fontSize: 12)),
              Text("${(progress * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: const Color(0xFFF1F5F9),
            color: Theme.of(context).primaryColor,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => _openPlanDetails(context, ref, plan),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.black,
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

  void _navigateToVerse(String verseRef) {
    final parsed = _parseVerseRef(verseRef);
    if (parsed != null) {
      final (book, chapter, verse) = parsed;
      context.push('/bible/$book/$chapter/$verse');
    }
  }

  (String, int, int)? _parseVerseRef(String ref) {
    final parts = ref.split(' ');
    if (parts.length < 2) return null;
    final bookParts = parts.sublist(0, parts.length - 1);
    final refPart = parts.last;
    final refParts = refPart.split(':');
    if (refParts.length < 2) return null;
    final chapter = int.tryParse(refParts[0]) ?? 1;
    final verseStr = refParts[1].split('-').first;
    final verse = int.tryParse(verseStr) ?? 1;
    return (bookParts.join(' '), chapter, verse);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
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
          const Text("DAILY SCRIPTURE GUIDES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 15),
          Flexible(
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _plan.totalDays,
              itemBuilder: (context, idx) {
                final isDone = idx < _plan.completedDays;
                final isNext = idx == _plan.completedDays;
                final verseRef = _plan.dailyVerses[idx];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isDone ? LucideIcons.checkCircle2 : LucideIcons.circle,
                    color: isDone ? Colors.green : (isNext ? Theme.of(context).primaryColor : Colors.grey),
                  ),
                  title: GestureDetector(
                    onTap: () => _navigateToVerse(verseRef),
                    child: Text(
                      "Day ${idx + 1}: $verseRef",
                      style: TextStyle(
                        fontWeight: isNext ? FontWeight.bold : FontWeight.normal,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone ? Colors.grey : Colors.black87,
                      ),
                    ),
                  ),
                  subtitle: isDone
                      ? null
                      : LiveScriptureText(
                          reference: verseRef,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Colors.black54,
                          ),
                        ),
                  isThreeLine: !isDone,
                  trailing: isNext
                      ? ElevatedButton(
                          onPressed: () async {
                            await widget.ref.read(readingPlanServiceProvider).completeDay(_plan.id);
                            try {
                              final coinsService = widget.ref.read(coinsServiceProvider);
                              await coinsService.addStreakBonus(1);
                            } catch (e) {
                              debugPrint('Error adding streak bonus: $e');
                            }
                            widget.ref.invalidate(readingPlansProvider);
                            setState(() => _plan.completedDays = (_plan.completedDays + 1).clamp(0, _plan.totalDays));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text("Day completed! +10 Church Coins earned."),
                                backgroundColor: Colors.green,
                              ));
                            }
                          },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(60, 30),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text("READ", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
