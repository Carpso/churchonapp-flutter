import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/features/modules/bible_quiz/data/quiz_hosting_service.dart';

/// Read-only viewer for a question set, with per-question study-pack toggles.
class QuizSetQuestionsScreen extends ConsumerWidget {
  const QuizSetQuestionsScreen({super.key, required this.setId, this.title});
  final String setId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final qAsync = ref.watch(quizSetQuestionsProvider(setId));

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(title: Text(title ?? 'Questions')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(quizSetQuestionsProvider(setId)),
        child: qAsync.when(
          data: (questions) {
            if (questions.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Icon(LucideIcons.fileQuestion, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Center(
                      child: Text('No questions extracted yet',
                          style: TextStyle(color: Colors.grey))),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: questions.length,
              itemBuilder: (_, i) => _card(context, ref, theme, i, questions[i]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load: $e')),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, ThemeData theme, int index,
      QuizSetQuestion q) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: theme.primaryColor.withValues(alpha: 0.2),
                child: Text('${index + 1}',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 8),
              if ((q.verseReference ?? '').isNotEmpty)
                Text(q.verseReference!,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.primaryColor)),
              const Spacer(),
              Text('${q.points} pts',
                  style: TextStyle(
                      fontSize: 10,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5))),
              Switch(
                value: q.isStudyVisible,
                onChanged: (v) async {
                  await ref
                      .read(quizHostingServiceProvider)
                      .updateQuestionVisibility(q.id, v);
                  ref.invalidate(quizSetQuestionsProvider(setId));
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(q.prompt,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...q.options.map((o) {
            final correct = q.correctAnswers
                .any((c) => c.toLowerCase() == o.toLowerCase());
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    correct
                        ? LucideIcons.checkCircle2
                        : LucideIcons.circle,
                    size: 14,
                    color: correct ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(o,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                correct ? FontWeight.w700 : FontWeight.normal)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
