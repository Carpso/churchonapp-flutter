import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/finance/presentation/multi_currency_wallet_screen.dart';

void main() {
  testWidgets('Wallet screen renders without error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: MultiCurrencyWalletScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(MultiCurrencyWalletScreen), findsOneWidget);
  });

  testWidgets('Wallet screen has a Scaffold with AppBar', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: MultiCurrencyWalletScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);
  });
}
