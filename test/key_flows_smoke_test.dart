import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:church_on_app/features/give/data/lipila_fx_service.dart';
import 'package:church_on_app/core/config/fee_config.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_section_title.dart';
import 'package:church_on_app/features/finance/presentation/widgets/giving_category_selector.dart';
import 'package:church_on_app/features/connect/data/chat_service.dart';

void main() {
  group('Key flow: Home widgets', () {
    testWidgets('HomeSectionTitle renders', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: Scaffold(body: HomeSectionTitle(title: 'Quick Actions')))),
      );
      await tester.pump();
      expect(find.text('Quick Actions'), findsOneWidget);
    });
  });

  group('Key flow: Giving', () {
    testWidgets('GivingCategorySelector renders categories and selects', (tester) async {
      String? selected;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: GivingCategorySelector(
                categories: ['Tithe', 'Offering', 'Mission'],
                selectedCategory: 'Tithe',
                onCategoryChanged: (c) => selected = c,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Tithe'), findsOneWidget);
      await tester.tap(find.text('Mission'));
      await tester.pump();
      expect(selected, 'Mission');
    });

    test('FeeConfig platformFee is finite and respects min fee', () {
      final fees = FeeConfig.defaults;
      final fee = fees.platformFee(100);
      expect(fee.isFinite, isTrue);
      expect(fee, greaterThanOrEqualTo(fees.minFeeKwacha));
    });
  });

  group('Key flow: Payments / FX', () {
    test('LipilaFxService converts base currency using a rate', () {
      final svc = LipilaFxService();
      svc.setFallbackRate(18.0);
      // convert(amountInBase, rate) => amountInBase / rate
      final usd = svc.convert(180.0, 18.0);
      expect(usd, closeTo(10.0, 0.001));
    });
  });

  group('Key flow: Chat models', () {
    test('ChatMessage parses a map', () {
      final msg = ChatMessage.fromMap({
        'id': 'm1',
        'sender_id': 'u1',
        'receiver_id': 'u2',
        'content': 'hello',
        'created_at': DateTime.now().toIso8601String(),
      }, 'u1');
      expect(msg.id, 'm1');
      expect(msg.text, 'hello');
    });
  });
}
