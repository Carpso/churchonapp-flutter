import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../data/bible_quiz_service.dart';
import '../../../bible/presentation/live_scripture_text.dart';

class BibleQuizResultsScreen extends ConsumerWidget {
  final QuizSessionResult result;

  const BibleQuizResultsScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
  // Correct answer count for hero section
  int correctCount = 0;
  for (int i = 0; i < result.answers.length; i++) {
    final a = result.answers[i];
    final q = result.questions[i];
    if (q.isMultipleAnswer) {
      // For multi-select, correctness was determined per-question in the arena;
      // we count the first selected answer as correct if it's in correctAnswers
      if (a != null && a >= 0 && q.correctAnswers.contains(a)) correctCount++;
    } else {
      if (a != null && a >= 0 && a == q.correctAnswer) correctCount++;
    }
  }
    final wrongCount = result.questions.length - correctCount;
    final accuracy = result.correctRate;

    // Per-category stats
    final categoryStats = _computeCategoryStats(result);
    final grade = _grade(result.score, result.maxScore);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.x, color: Colors.white54),
          onPressed: () => context.pop(),
        ),
        title: const Text('Quiz Results', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Hero section
              _buildHero(theme, grade, accuracy, correctCount, wrongCount),
              if (result.opponentScore != null) ...[
                const SizedBox(height: 16),
                _buildMatchResult(theme),
              ],
              const SizedBox(height: 24),
              // Score breakdown
              _buildScoreBreakdown(theme),
              const SizedBox(height: 20),
              // Category breakdown
              if (categoryStats.isNotEmpty)
                _buildCategoryBreakdown(theme, categoryStats),
              const SizedBox(height: 20),
              // Response time chart
              _buildResponseTimeSection(theme),
              const SizedBox(height: 20),
              // Wrong questions review
              if (result.wrongQuestions.isNotEmpty)
                _buildWrongQuestionsReview(theme),
              const SizedBox(height: 24),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.pop(),
                      icon: const Icon(LucideIcons.rotateCcw, size: 18),
                      label: const Text('Try Again'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        context.pop();
                      },
                      icon: const Icon(LucideIcons.home, size: 18),
                      label: const Text('Hub'),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero(
    ThemeData theme,
    _Grade grade,
    double accuracy,
    int correctCount,
    int wrongCount,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            grade.color.withAlpha(30),
            grade.color.withAlpha(8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: grade.color.withAlpha(50)),
      ),
      child: Column(
        children: [
          // Emoji / icon
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: grade.color.withAlpha(30),
            ),
            child: Icon(
              _gradeIcon(grade),
              size: 36,
              color: grade.color,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            grade.label,
            style: TextStyle(
              color: grade.color,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${result.score} / ${result.maxScore} pts',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _heroStat(
                '${(accuracy * 100).toInt()}%',
                'Accuracy',
                theme.primaryColor,
              ),
              Container(width: 1, height: 30, color: Colors.white12),
              _heroStat(
                '$correctCount',
                'Correct',
                Colors.greenAccent,
              ),
              Container(width: 1, height: 30, color: Colors.white12),
              _heroStat(
                '$wrongCount',
                'Wrong',
                Colors.redAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String value, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Head-to-head match summary: YOU vs OPPONENT with avatars and the
  /// verified (server-settled) opponent score.
  Widget _buildMatchResult(ThemeData theme) {
    final myScore = result.score;
    final oppScore = result.opponentScore ?? 0;
    final won = myScore > oppScore;
    final draw = myScore == oppScore;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: won
            ? Colors.greenAccent.withAlpha(14)
            : draw
                ? Colors.white.withAlpha(8)
                : Colors.redAccent.withAlpha(14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: won
              ? Colors.greenAccent.withAlpha(70)
              : draw
                  ? Colors.white24
                  : Colors.redAccent.withAlpha(70),
        ),
      ),
      child: Column(
        children: [
          Text(
            won
                ? 'YOU WIN!'
                : draw
                    ? "IT'S A DRAW"
                    : 'OPPONENT WINS',
            style: TextStyle(
              color: won
                  ? Colors.greenAccent
                  : draw
                      ? Colors.white70
                      : Colors.redAccent,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _matchPlayer(theme, 'YOU', null, myScore)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'VS',
                  style: TextStyle(
                    color: theme.primaryColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(
                child: _matchPlayer(
                  theme,
                  result.opponentName ?? 'Opponent',
                  result.opponentAvatar,
                  oppScore,
                ),
              ),
            ],
          ),
          if (result.opponentChurch != null) ...[
            const SizedBox(height: 10),
            Text(
              result.opponentChurch!,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _matchPlayer(
    ThemeData theme,
    String name,
    String? avatar,
    int score,
  ) {
    return Column(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: theme.primaryColor, width: 2),
            image: avatar != null && avatar.isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(avatar),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: avatar == null || avatar.isEmpty
              ? Icon(LucideIcons.user, color: Colors.white38, size: 26)
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '$score pts',
          style: TextStyle(
            color: theme.primaryColor,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildScoreBreakdown(ThemeData theme) {
    // Mirror the arena's exact rule: +5 per correct answer once the current
    // streak reaches 3 (see _submitAnswer in the arena screen).
    var bonus = 0;
    var streak = 0;
    final answers = result.answers;
    final questions = result.questions;
    for (var i = 0; i < answers.length && i < questions.length; i++) {
      final a = answers[i];
      final q = questions[i];
      final bool isCorrect;
      if (q.isMultipleAnswer) {
        isCorrect = a != null && a >= 0 && q.correctAnswers.contains(a);
      } else {
        isCorrect = a != null && a >= 0 && a == q.correctAnswer;
      }
      if (isCorrect) {
        streak++;
        if (streak >= 3) bonus += 5;
      } else {
        streak = 0;
      }
    }
    final baseScore = result.score - bonus;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Score Breakdown',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _breakdownRow('Base Score', '$baseScore', theme.primaryColor),
          if (bonus > 0)
            _breakdownRow(
              'Streak Bonus (${result.streak}x)',
              '+$bonus',
              theme.primaryColor,
            ),
          if (result.powerUpsUsed > 0)
            _breakdownRow(
              'Power-ups Used',
              '${result.powerUpsUsed}',
              theme.primaryColor,
            ),
          const Divider(color: Colors.white12, height: 20),
          _breakdownRow('Total', '${result.score}', Colors.greenAccent),
        ],
      ),
    );
  }

  Widget _breakdownRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  List<_CategoryStat> _computeCategoryStats(QuizSessionResult result) {
    final map = <String, List<bool>>{};
    for (int i = 0; i < result.questions.length; i++) {
      final cat = result.questions[i].category;
      map.putIfAbsent(cat, () => []);
      final answer = result.answers[i];
      final q = result.questions[i];
      final bool isCorrect;
      if (q.isMultipleAnswer) {
        isCorrect = answer != null && answer >= 0 && q.correctAnswers.contains(answer);
      } else {
        isCorrect = answer == q.correctAnswer;
      }
      map[cat]!.add(isCorrect);
    }
    return map.entries
        .map((e) => _CategoryStat(
              category: e.key,
              correct: e.value.where((b) => b).length,
              total: e.value.length,
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  Widget _buildCategoryBreakdown(ThemeData theme, List<_CategoryStat> stats) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'By Category',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...stats.map((s) {
            final rate = s.total > 0 ? s.correct / s.total : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        s.category,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      const Spacer(),
                      Text(
                        '${s.correct}/${s.total}',
                        style: TextStyle(
                          color: rate >= 0.7
                              ? Colors.greenAccent
                              : rate >= 0.4
                                  ? Colors.orangeAccent
                                  : Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: rate,
                      backgroundColor: Colors.white.withAlpha(12),
                      valueColor: AlwaysStoppedAnimation(
                        rate >= 0.7
                            ? Colors.greenAccent
                            : rate >= 0.4
                                ? Colors.orangeAccent
                                : Colors.redAccent,
                      ),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildResponseTimeSection(ThemeData theme) {
    final avg = result.averageResponseTime.inMilliseconds;
    final fastest = result.responseTimesMs.isEmpty
        ? 0
        : result.responseTimesMs.reduce(min);
    final slowest = result.responseTimesMs.isEmpty
        ? 0
        : result.responseTimesMs.reduce(max);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Response Time',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _timeStat('Fastest', '${(fastest / 1000).toStringAsFixed(1)}s', Colors.greenAccent),
              _timeStat('Average', '${(avg / 1000).toStringAsFixed(1)}s', theme.primaryColor),
              _timeStat('Slowest', '${(slowest / 1000).toStringAsFixed(1)}s', Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildWrongQuestionsReview(ThemeData theme) {
    final wrong = result.wrongQuestions;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.bookOpen, size: 16, color: Colors.white54),
              const SizedBox(width: 6),
              Text(
                'Review (${wrong.length} incorrect)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...wrong.take(5).map((q) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withAlpha(12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent.withAlpha(40)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      q.question,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Answer: ${q.isMultipleAnswer ? q.correctAnswers.map((a) => q.options[a]).join(', ') : q.options[q.correctAnswer]}',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 13,
                      ),
                    ),
                    if (q.scriptureReference != null) ...[
                      Text(
                        q.scriptureReference!,
                        style: TextStyle(
                          color: theme.primaryColor.withAlpha(150),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LiveScriptureText(
                        reference: q.scriptureReference!,
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          if (wrong.length > 5)
            TextButton(
              onPressed: () {
                // Could push a full review screen
              },
              child: Text(
                'See all ${wrong.length} questions',
                style: TextStyle(color: theme.primaryColor),
              ),
            ),
        ],
      ),
    );
  }

  IconData _gradeIcon(_Grade grade) {
    switch (grade.level) {
      case 'S':
        return LucideIcons.crown;
      case 'A':
        return LucideIcons.trophy;
      case 'B':
        return LucideIcons.award;
      case 'C':
        return LucideIcons.thumbsUp;
      default:
        return LucideIcons.target;
    }
  }

  _Grade _grade(int score, int max) {
    if (max == 0) return _Grade('F', 'Keep Learning!', Colors.white54, 'F');
    final pct = score / max;
    if (pct >= 0.95) return _Grade('S', 'Divine Wisdom!', Colors.amberAccent, 'S');
    if (pct >= 0.8) return _Grade('A', 'Excellent!', Colors.greenAccent, 'A');
    if (pct >= 0.65) return _Grade('B', 'Good Job!', Colors.amber, 'B');
    if (pct >= 0.5) return _Grade('C', 'Not Bad!', Colors.orangeAccent, 'C');
    return _Grade('D', 'Keep Studying!', Colors.redAccent, 'D');
  }
}

class _Grade {
  final String level;
  final String label;
  final Color color;
  final String emoji;
  _Grade(this.level, this.label, this.color, this.emoji);
}

class _CategoryStat {
  final String category;
  final int correct;
  final int total;
  _CategoryStat({
    required this.category,
    required this.correct,
    required this.total,
  });
}
