import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/finance/data/coin_purchase_service.dart';

void main() {
  group('CoinPackage', () {
    test('has correct price per coin for Starter package', () {
      const pkg = CoinPackage(coins: 100, priceKwacha: 10, label: 'Starter');
      expect(pkg.pricePerCoin, 0.1);
    });

    test('has correct price per coin for Popular package', () {
      const pkg = CoinPackage(coins: 250, priceKwacha: 22, label: 'Popular', bonus: '10% bonus');
      expect(pkg.pricePerCoin, closeTo(0.088, 0.001));
    });

    test('has correct price per coin for Champion package', () {
      const pkg = CoinPackage(coins: 2500, priceKwacha: 150, label: 'Champion', bonus: '50% bonus');
      expect(pkg.pricePerCoin, closeTo(0.06, 0.01));
    });

    test('bonus is optional', () {
      const pkg = CoinPackage(coins: 100, priceKwacha: 10, label: 'Starter');
      expect(pkg.bonus, isNull);
    });

    test('bonus is set when provided', () {
      const pkg = CoinPackage(coins: 500, priceKwacha: 40, label: 'Value', bonus: '20% bonus');
      expect(pkg.bonus, '20% bonus');
    });

    test('price per coin decreases with larger packages', () {
      final packages = CoinPurchaseService.packages;
      for (int i = 1; i < packages.length; i++) {
        expect(
          packages[i].pricePerCoin,
          lessThan(packages[i - 1].pricePerCoin),
          reason: '${packages[i].label} should be cheaper per coin than ${packages[i - 1].label}',
        );
      }
    });
  });

  group('CoinPurchaseResult', () {
    test('successful result has txId', () {
      const result = CoinPurchaseResult(success: true, txId: 'TXN-001');
      expect(result.success, true);
      expect(result.txId, 'TXN-001');
      expect(result.error, isNull);
    });

    test('failed result has error', () {
      const result = CoinPurchaseResult(success: false, error: 'Not authenticated');
      expect(result.success, false);
      expect(result.txId, isNull);
      expect(result.error, 'Not authenticated');
    });
  });

  group('CoinPurchaseService', () {
    test('has 5 packages defined', () {
      expect(CoinPurchaseService.packages.length, 5);
    });

    test('packages are ordered by price ascending', () {
      final prices = CoinPurchaseService.packages.map((p) => p.priceKwacha).toList();
      expect(prices, [10, 22, 40, 70, 150]);
    });

    test('packages have increasing coin amounts', () {
      final coins = CoinPurchaseService.packages.map((p) => p.coins).toList();
      expect(coins, [100, 250, 500, 1000, 2500]);
    });

    test('each package has a label', () {
      for (final pkg in CoinPurchaseService.packages) {
        expect(pkg.label.isNotEmpty, true);
      }
    });
  });
}
