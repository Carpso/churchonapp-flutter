import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/fasting_service.dart';

class TechFastBlocker extends ConsumerStatefulWidget {
  final Widget child;
  final List<String> categories;

  const TechFastBlocker({
    super.key,
    required this.child,
    required this.categories,
  });

  @override
  ConsumerState<TechFastBlocker> createState() => _TechFastBlockerState();
}

class _TechFastBlockerState extends ConsumerState<TechFastBlocker> {
  Timer? _timer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return "0:00:00";
    final hours = d.inHours;
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$hours:$mins:$secs";
  }

  @override
  Widget build(BuildContext context) {
    final activeFastAsync = ref.watch(activeTechFastProvider);

    return activeFastAsync.when(
      data: (schedule) {
        if (schedule == null || !schedule.isCurrentlyActive) {
          return widget.child;
        }

        // Check if any of the target categories are blocked in this schedule
        final isBlocked = widget.categories.any((cat) => schedule.blockedApps.contains(cat));
        if (!isBlocked) {
          return widget.child;
        }

        // Compute time remaining
        final now = DateTime.now();
        _timeLeft = schedule.endTime.difference(now);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.smartphone,
                      size: 64,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Focus Mode Active",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "You are currently on a technology fast. This section has been disabled to help you stay focused on prayer and contemplation.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: schedule.blockedApps.map((cat) {
                      final label = FastingService.appCategoryLabels[cat] ?? cat;
                      return Chip(
                        label: Text(
                          label,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                        backgroundColor: Theme.of(context).primaryColor,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          "TIME REMAINING",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatDuration(_timeLeft),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: () async {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) => Center(
                          child: CircularProgressIndicator(color: Theme.of(context).primaryColor),
                        ),
                      );
                      try {
                        await ref.read(fastingServiceProvider).endTechFast(schedule.id);
                        ref.invalidate(activeTechFastProvider);
                        if (context.mounted) {
                          Navigator.pop(context); // Dismiss loading
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Focus mode turned off. Access restored! Rest edified."),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Error: $e"),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(LucideIcons.unlock),
                    label: const Text("END FAST & UNLOCK"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(200, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, s) => widget.child,
    );
  }
}
