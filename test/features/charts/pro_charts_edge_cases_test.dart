import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:church_on_app/core/widgets/pro_charts.dart';
import 'package:church_on_app/features/modules/bible_quiz/engine/quiz_engine.dart';
import 'package:church_on_app/features/modules/bible_quiz/engine/mock_quiz_repository.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ProBarChart — zero-data & edge inputs', () {
    testWidgets('renders honest empty state with no data', (tester) async {
      await tester.pumpWidget(_host(const ProBarChart(values: [], labels: [])));
      expect(find.text('No data yet'), findsOneWidget);
    });

    testWidgets('all-zero values render ghost stubs, not a crash', (tester) async {
      await tester.pumpWidget(_host(const ProBarChart(
        values: [0, 0, 0],
        labels: ['Jan', 'Feb', 'Mar'],
      )));
      await tester.pumpAndSettle();
      expect(find.byType(BarChart), findsOneWidget);
      // Axis labels still render so the chart is readable.
      expect(find.text('Jan'), findsOneWidget);
    });

    testWidgets('extreme outlier value does not break layout', (tester) async {
      await tester.pumpWidget(_host(const ProBarChart(
        values: [10, 12, 999999],
        labels: ['A', 'B', 'C'],
      )));
      await tester.pumpAndSettle();
      expect(find.byType(BarChart), findsOneWidget);
    });

    testWidgets('single data point renders without error', (tester) async {
      await tester.pumpWidget(_host(const ProBarChart(values: [50], labels: ['Only'])));
      await tester.pumpAndSettle();
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('Only'), findsOneWidget);
    });
  });

  group('ProLineChart — empty / single / NaN safety', () {
    testWidgets('empty spots show "Not enough trend data"', (tester) async {
      await tester.pumpWidget(_host(const ProLineChart(spots: [], bottomLabels: [])));
      expect(find.text('Not enough trend data'), findsOneWidget);
    });

    testWidgets('single spot renders labelled dot card instead of invisible line', (tester) async {
      await tester.pumpWidget(_host(const ProLineChart(
        spots: [FlSpot(0, 250)],
        bottomLabels: ['Mon'],
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('K'), findsWidgets,
          reason: 'single point renders as currency-labelled card');
      expect(find.text('Mon'), findsOneWidget);
    });

    testWidgets('NaN input is sanitized to zero without crash', (tester) async {
      await tester.pumpWidget(_host(ProLineChart(
        spots: const [FlSpot(0, 5), FlSpot(double.nan, double.nan), FlSpot(2, 8)],
        bottomLabels: const ['a', 'b', 'c'],
      )));
      await tester.pumpAndSettle();
      expect(find.byType(LineChart), findsOneWidget);
    });
  });

  group('ProPieChart — zero division & negative guards', () {
    testWidgets('all-zero total shows "No contributions to classify"', (tester) async {
      await tester.pumpWidget(_host(const ProPieChart(
        sections: [ProPieSection(label: 'Tithe', value: 0, color: Colors.green)],
        centerValue: 'K 0',
      )));
      expect(find.text('No contributions to classify'), findsOneWidget);
    });

    testWidgets('negative sections are filtered out of the sweep', (tester) async {
      await tester.pumpWidget(_host(const ProPieChart(
        sections: [
          ProPieSection(label: 'Good', value: 100, color: Colors.green),
          ProPieSection(label: 'Bad', value: -50, color: Colors.red),
        ],
      )));
      await tester.pumpAndSettle();
      expect(find.byType(PieChart), findsOneWidget);
      // Legend hides the negative section entirely.
      expect(find.textContaining('Bad'), findsNothing);
      expect(find.textContaining('Good'), findsOneWidget);
    });

    testWidgets('legend percentages sum to ~100 for positive splits', (tester) async {
      await tester.pumpWidget(_host(const ProPieChart(
        sections: [
          ProPieSection(label: 'Tithes', value: 60, color: Colors.green),
          ProPieSection(label: 'Offerings', value: 40, color: Colors.amber),
        ],
        centerLabel: 'TOTAL',
        centerValue: 'K 100',
      )));
      await tester.pumpAndSettle();
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('K 100'), findsOneWidget);
    });
  });

  group('QuizSession — competition flow integration', () {
    test('full tournament session: correct fast answers outscore slow wrong ones', () {
      final bank = MockQuizRepository.seedBank().take(4).toList();
      final s = QuizSession(
        id: 'int-1', userId: 'player', mode: QuizMode.tournament,
        questions: bank, tenantToken: 'tok',
      );

      // Q1: correct + fast → base + speed bonus
      final b1 = s.submitAnswer(questionIndex: 0, selectedIndex: bank[0].correctIndex, responseTime: const Duration(milliseconds: 900));
      expect(b1.total, basePointsFor(bank[0].difficulty) + 5);

      // Q2: correct + slow → base only
      final b2 = s.submitAnswer(questionIndex: 1, selectedIndex: bank[1].correctIndex, responseTime: const Duration(seconds: 20));
      expect(b2.speedBonus, 0);
      expect(b2.basePoints, basePointsFor(bank[1].difficulty));

      // Q3: timeout → penalty
      final b3 = s.submitAnswer(questionIndex: 2, selectedIndex: null, responseTime: const Duration(seconds: 30), timedOut: true);
      expect(b3.penalty, QuizRuleSet.tournament.timeoutPenalty);

      // Q4: wrong → penalty
      final wrongIdx = (bank[3].correctIndex + 1) % bank[3].options.length;
      final b4 = s.submitAnswer(questionIndex: 3, selectedIndex: wrongIdx, responseTime: const Duration(seconds: 3));
      expect(b4.penalty, QuizRuleSet.tournament.wrongAttemptPenalty);

      expect(s.attempts.length, 4);
      expect(s.accuracy, closeTo(0.5, 0.001));
      expect(s.isFlagged, isFalse, reason: 'legitimate session must stay clean');
      expect(s.score, s.attempts.fold<int>(0, (acc, a) => acc + a.breakdown.total));
    });
  });
}
