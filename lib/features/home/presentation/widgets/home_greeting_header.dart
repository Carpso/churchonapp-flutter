import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';

class HomeGreetingHeader extends ConsumerWidget {
  const HomeGreetingHeader({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good Morning,";
    if (hour < 17) return "Good Afternoon,";
    return "Good Evening,";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      data: (profile) {
        final fullName = profile?.name ?? "Believer";
        var firstName = fullName.trim().split(' ').first;
        if (firstName.length > 12) {
          firstName = "${firstName.substring(0, 10)}...";
        }
        final streak = profile?.streakCount ?? 0;
        final greeting = _getGreeting();

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greeting, style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.w600)),
                  Text(
                    firstName,
                    style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: streak > 0 ? Colors.orange.withValues(alpha: 0.4) : Theme.of(context).primaryColor.withValues(alpha: 0.2)),
                boxShadow: [BoxShadow(color: Theme.of(context).shadowColor.withValues(alpha: 0.05), blurRadius: 10)],
              ),
              child: Row(
                children: [
                  Icon(streak > 0 ? LucideIcons.flame : LucideIcons.coins, size: 18, color: streak > 0 ? Colors.orange : Theme.of(context).colorScheme.secondary),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        streak > 0 ? "STREAK" : "REWARDS",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      Text(streak > 0 ? "$streak days 🔥" : "Open Rewards", style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ShimmerLoader.rectangular(width: 100, height: 14),
                const SizedBox(height: 6),
                const ShimmerLoader.rectangular(width: 140, height: 24),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const ShimmerLoader.rectangular(width: 100, height: 48),
        ],
      ),
      error: (e, s) => Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_getGreeting(), style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.w600)),
              const Text("Welcome!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
