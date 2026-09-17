import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import '../data/bible_verse_service.dart';
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
    // Prefer server-backed per-entry progress when this plan has real entries;
    // otherwise fall back to the legacy completed_days counter.
    var doneCount = plan.completedDays;
    var total = plan.totalDays;
    if (isUuidString(plan.id)) {
      final entries = ref.watch(readingPlanEntriesProvider(plan.id)).value;
      if (entries != null && entries.isNotEmpty) {
        final done = ref.watch(readingPlanCompletedProvider(plan.id)).value ?? <String>{};
        total = entries.length;
        doneCount = entries.where((e) => done.contains(e.id)).length;
      }
    }
    if (total <= 0) total = 1;
    if (doneCount > total) doneCount = total;

    final progress = doneCount / total;
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
              Expanded(child: Text(plan.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
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
              Text("$doneCount / $total completed", style: TextStyle(color: Theme.of(context).primaryColor.withValues(alpha: 0.9), fontWeight: FontWeight.bold, fontSize: 12)),
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
            onPressed: () => _openPlanDetails(context, plan),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 45),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: Text(doneCount > 0 ? "CONTINUE PLAN" : "START PLAN", style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openPlanDetails(BuildContext context, ReadingPlan plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PlanDetailSheet(plan: plan),
    );
  }
}

class _PlanDetailSheet extends ConsumerStatefulWidget {
  final ReadingPlan plan;
  const _PlanDetailSheet({required this.plan});

  @override
  ConsumerState<_PlanDetailSheet> createState() => _PlanDetailSheetState();
}

class _PlanDetailSheetState extends ConsumerState<_PlanDetailSheet> {
  late ReadingPlan _plan;

  /// Optimistic completion set so a tick renders instantly; reconciled with the
  /// RPC result immediately after (and reverted on failure).
  Set<String>? _optimisticDone;

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

  /// Optimistically toggles [entry], persists via the RPC, refreshes the
  /// server state and (on the first tick of a day) records the reading streak.
  /// Reverts + shows a snackbar if the RPC fails.
  Future<void> _toggleEntry(ReadingPlanEntry entry, bool done) async {
    final planId = _plan.id;
    final current = _optimisticDone ??
        ref.read(readingPlanCompletedProvider(planId)).value ??
        <String>{};
    final previous = {...current};
    final optimistic = {...current};
    if (done) {
      optimistic.add(entry.id);
    } else {
      optimistic.remove(entry.id);
    }
    setState(() => _optimisticDone = optimistic);

    try {
      await ref.read(bibleVerseServiceProvider).toggleReadingPlanEntry(
            entryId: entry.id,
            done: done,
          );

      // "Fully track user reading": reuse the existing reading-streak tracker
      // (profiles.streak_count / last_read_at) once per completed reading.
      if (done) {
        try {
          await ref.read(profileProvider.notifier).updateReadingStreak();
        } catch (e) {
          debugPrint('Reading streak update failed (non-fatal): $e');
        }
      }

      // Refetch so the tick state stays authoritative server-side.
      ref.invalidate(readingPlanCompletedProvider(planId));
      try {
        final fresh = await ref.read(readingPlanCompletedProvider(planId).future);
        if (mounted) setState(() => _optimisticDone = fresh);
      } catch (e) {
        debugPrint('Plan progress refetch failed (keeping optimistic): $e');
      }
    } catch (e) {
      debugPrint('Toggle reading plan entry failed: $e');
      if (mounted) {
        setState(() => _optimisticDone = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not save your progress: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trackable = isUuidString(_plan.id);
    final entriesAsync = trackable ? ref.watch(readingPlanEntriesProvider(_plan.id)) : null;
    final completedAsync = trackable ? ref.watch(readingPlanCompletedProvider(_plan.id)) : null;

    final entries = entriesAsync?.value ?? const <ReadingPlanEntry>[];
    final providerDone = completedAsync?.value ?? <String>{};
    final done = _optimisticDone ?? providerDone;
    final hasEntries = entries.isNotEmpty;

    final legacyDays = _plan.dailyVerses;
    final legacyTotal = legacyDays.isNotEmpty ? legacyDays.length : _plan.totalDays;

    final int total = hasEntries ? entries.length : legacyTotal;
    final int doneCount = hasEntries
        ? entries.where((e) => done.contains(e.id)).length
        : _plan.completedDays.clamp(0, legacyTotal);
    final double progress = total == 0 ? 0 : doneCount / total;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.all(25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_plan.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(_plan.description, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("$doneCount of $total done",
                  style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
              Text("${(progress * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: const Color(0xFFF1F5F9),
            color: Theme.of(context).primaryColor,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 20),
          const Text("DAILY SCRIPTURE GUIDES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 12),
          Flexible(
            child: _buildBody(
              context: context,
              entries: entries,
              done: done,
              hasEntries: hasEntries,
              entriesLoading: entriesAsync?.isLoading ?? false,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required List<ReadingPlanEntry> entries,
    required Set<String> done,
    required bool hasEntries,
    required bool entriesLoading,
  }) {
    if (hasEntries) {
      final firstOpen = entries.indexWhere((e) => !done.contains(e.id));
      return ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: entries.length,
        itemBuilder: (context, idx) {
          final entry = entries[idx];
          final isDone = done.contains(entry.id);
          final isNext = idx == firstOpen;
          return _buildEntryTile(context, entry, isDone: isDone, isNext: isNext);
        },
      );
    }

    // No server entries: fall back to the plan's static daily verses so the
    // screen never breaks on an empty/legacy plan.
    final days = _plan.dailyVerses;
    if (days.isEmpty) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Center(
            child: Text(
              entriesLoading
                  ? "Loading plan…"
                  : "This plan has no reading entries yet.",
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: days.length,
      itemBuilder: (context, idx) {
        final isDone = idx < _plan.completedDays;
        final isNext = idx == _plan.completedDays;
        final verseRef = days[idx];
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
                  onPressed: _completeLegacyDay,
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
    );
  }

  Widget _buildEntryTile(BuildContext context, ReadingPlanEntry entry,
      {required bool isDone, required bool isNext}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: GestureDetector(
        onTap: () => _toggleEntry(entry, !isDone),
        child: Icon(
          isDone ? LucideIcons.checkCircle2 : LucideIcons.circle,
          color: isDone ? Colors.green : (isNext ? Theme.of(context).primaryColor : Colors.grey),
        ),
      ),
      onTap: () => _toggleEntry(entry, !isDone),
      title: GestureDetector(
        onTap: () => _navigateToVerse(entry.reference),
        child: Text(
          "Day ${entry.dayNumber}: ${entry.reference}",
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
              reference: entry.reference,
              textAlign: TextAlign.left,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Colors.black54,
              ),
            ),
      isThreeLine: !isDone,
      trailing: Checkbox(
        value: isDone,
        onChanged: (value) => _toggleEntry(entry, value ?? !isDone),
        activeColor: Colors.green,
      ),
    );
  }

  Future<void> _completeLegacyDay() async {
    final wasFinished = _plan.completedDays >= _plan.totalDays;
    final newDays = await ref.read(readingPlanServiceProvider).completeDay(
          _plan.id,
          totalDays: _plan.totalDays,
        );
    // Coins are awarded ONCE per plan, only when the whole plan is finished.
    var coinsEarned = 0;
    if (!wasFinished && newDays >= _plan.totalDays) {
      try {
        final coinsService = ref.read(coinsServiceProvider);
        await coinsService.addStreakBonus(1);
        coinsEarned = 50;
      } catch (e) {
        debugPrint('Error adding plan bonus: $e');
      }
    }
    ref.invalidate(readingPlansProvider);
    setState(() => _plan.completedDays = newDays.clamp(0, _plan.totalDays));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(coinsEarned > 0
            ? "Plan complete! +$coinsEarned Church Coins earned."
            : "Day ${newDays.clamp(0, _plan.totalDays)} marked as read."),
        backgroundColor: Colors.green,
      ));
    }
  }
}
