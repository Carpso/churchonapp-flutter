import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/features/bible/data/bible_verse_service.dart';
import 'package:church_on_app/features/bible/data/bible_service.dart';
import 'package:church_on_app/features/bible/data/bible_translations.dart';
import 'package:church_on_app/features/bible/data/study_settings_provider.dart';
import 'package:church_on_app/features/bible/presentation/scripture_audio_button.dart';

class HomeDailyVerse extends ConsumerWidget {
  const HomeDailyVerse({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verseAsync = ref.watch(dailyBibleVerseProvider);
    final translation = ref.watch(studySettingsProvider).preferredTranslation;

    return verseAsync.when(
      data: (verse) {
        final liveText = ref
            .watch(bibleReferenceTextProvider(verse.reference))
            .value;
        // Avoid double marking: if preferred translation yields same text as the auto KJV verse,
        // don't add a redundant translation label (was showing "KJV (KJV)" + "NKJV" duplicate).
        final hasLive = liveText != null &&
            liveText.isNotEmpty &&
            liveText.trim() != verse.text.trim() &&
            !liveText.toLowerCase().contains('kjv');
        final String displayText;
        if (hasLive) {
          displayText = liveText;
        } else {
          displayText = verse.text;
        }
        final displayLabel = hasLive ? getTranslationFullName(translation) : null;
        return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF2A2F45),
              Color(0xFF151A2E),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: const Color(0xFF151A2E).withValues(alpha: 0.35), blurRadius: 15, offset: const Offset(0, 6)),
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
                      decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                      child: Icon(LucideIcons.bookOpen, color: Theme.of(context).primaryColor, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Text(
            "VERSE OF THE DAY",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).primaryColor,
              letterSpacing: 1.2,
            ),
          ),
                  ],
                ),
                IconButton(
                  icon: const Icon(LucideIcons.share2, color: Colors.white70, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '"$displayText" — ${verse.reference}'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: const Text("Daily verse copied to clipboard!"), backgroundColor: Theme.of(context).primaryColor, behavior: SnackBarBehavior.floating),
                    );
                  },
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: EdgeInsets.zero,
                ),
                ScriptureAudioButton(reference: verse.reference, iconColor: Theme.of(context).primaryColor, iconSize: 18),
              ],
            ),
            const SizedBox(height: 16),
            Text('"$displayText"', style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.5, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500)),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.bottomRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("— ${verse.reference}", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade200)),
                  if (displayLabel != null)
                    Text(displayLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1)),
                ],
              ),
            ),
          ],
        ),
      );
      },
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
