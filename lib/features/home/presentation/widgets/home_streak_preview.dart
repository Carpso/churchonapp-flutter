import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/bible/presentation/deep_study_suite_screen.dart';

class HomeStreakPreview extends ConsumerWidget {
  const HomeStreakPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final streak = profile?.streakCount ?? 0;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeepStudySuiteScreen())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: streak >= 30 ? Colors.amber.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: streak >= 7 ? Colors.amber.withValues(alpha: 0.3) : Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: streak > 0 ? Colors.orange.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(streak > 0 ? LucideIcons.flame : LucideIcons.bookOpen, color: streak > 0 ? Colors.orange : Colors.grey, size: 22),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Study Streak", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14, color: Theme.of(context).colorScheme.secondary)),
                  Text(streak > 0 ? "You're on a $streak-day streak! 🔥" : "Start your study streak today", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: Colors.grey.shade400, size: 18),
          ],
        ),
      ),
    );
  }
}
