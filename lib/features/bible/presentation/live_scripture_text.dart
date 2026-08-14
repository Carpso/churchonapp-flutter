import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/features/bible/data/bible_service.dart';
import 'package:church_on_app/features/bible/data/bible_translations.dart';
import 'package:church_on_app/features/bible/data/study_settings_provider.dart';

/// Fetches the text of a scripture reference in the user's preferred
/// translation and renders it inline. Renders nothing while loading or
/// when the reference can't be resolved, so it can be dropped anywhere
/// without breaking layout.
class LiveScriptureText extends ConsumerWidget {
  final String reference;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final bool showTranslationLabel;

  const LiveScriptureText({
    super.key,
    required this.reference,
    this.style,
    this.textAlign = TextAlign.center,
    this.maxLines,
    this.showTranslationLabel = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textAsync = ref.watch(bibleReferenceTextProvider(reference));
    return textAsync.when(
      data: (text) {
        if (text.isEmpty) return const SizedBox.shrink();
        final label = ref
            .watch(studySettingsProvider)
            .preferredTranslation;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: style ??
                  TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                    fontSize: 13,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                  ),
              textAlign: textAlign,
              maxLines: maxLines,
              overflow: maxLines != null
                  ? TextOverflow.ellipsis
                  : TextOverflow.clip,
            ),
            if (showTranslationLabel) ...[
              const SizedBox(height: 4),
              Text(
                getTranslationFullName(label),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}
