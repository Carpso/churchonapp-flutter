import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/features/bible/data/bible_verse_service.dart';

class HomeDailyVerse extends ConsumerWidget {
  const HomeDailyVerse({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verseAsync = ref.watch(dailyBibleVerseProvider);

    return verseAsync.when(
      data: (verse) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.deepPurple.shade900.withValues(alpha: 0.85),
              Colors.indigo.shade800.withValues(alpha: 0.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.deepPurple.shade900.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 6)),
          ],
          border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(LucideIcons.bookOpen, color: Colors.amber, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Text(
            "VERSE OF THE DAY",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Colors.amber.shade300,
              letterSpacing: 1.2,
            ),
          ),
                  ],
                ),
                IconButton(
                  icon: const Icon(LucideIcons.share2, color: Colors.white70, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '"${verse.text}" — ${verse.reference}'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: const Text("Daily verse copied to clipboard!"), backgroundColor: Colors.indigo.shade700, behavior: SnackBarBehavior.floating),
                    );
                  },
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('"${verse.text}"', style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.5, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500)),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.bottomRight,
              child: Text("— ${verse.reference}", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade200)),
            ),
          ],
        ),
      ),
      loading: () => Container(
        height: 140,
        width: double.infinity,
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(24)),
        child: const Center(child: ShimmerLoader.rectangular(width: double.infinity, height: 140)),
      ),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }
}
