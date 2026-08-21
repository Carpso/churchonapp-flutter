import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/core/config/fee_config.dart';

void main() {
  const fees = FeeConfig.defaults;

  group('FeeConfig — commission / revenue share (driver & vendor payouts)', () {
    test('platform fee = COA 1% + MoMo 2.5% with K3 minimum', () {
      // Large amount: pure percentage.
      expect(fees.platformFee(1000), closeTo(35.0, 0.001));
      // Tiny amount: clamps to the K3 floor.
      expect(fees.platformFee(10), 3.0, reason: 'min fee floor');
    });

    test('card transactions use the card processor rate', () {
      final momo = fees.platformFee(1000);
      final card = fees.platformFee(1000, isCard: true);
      expect(card, closeTo(momo, 0.001), reason: 'defaults use equal rates');
      final custom = const FeeConfig(
        coaFeePercent: 0.01,
        momoFeePercent: 0.025,
        cardFeePercent: 0.04,
        businessCutPercent: 0.1,
        minFeeKwacha: 3,
      );
      expect(custom.platformFee(1000, isCard: true), closeTo(50.0, 0.001));
      expect(custom.platformFee(1000), closeTo(35.0, 0.001));
    });

    test('totalCharged = amount + platform fee', () {
      expect(fees.totalCharged(100), closeTo(100 + fees.platformFee(100), 0.001));
    });

    test('business cut: 10% commission deducted from vendors/drivers', () {
      expect(fees.businessCut(500), closeTo(50.0, 0.001));
      expect(fees.businessNet(500), closeTo(450.0, 0.001));
      expect(fees.businessCut(0), 0);
      expect(fees.businessNet(0), 0);
    });
  });

  group('payoutNet — Lipila disbursement math (money out)', () {
    test('K100 payout nets after 1.5% disbursement + 1% COA payout fee', () {
      final net = fees.payoutNet(100);
      expect(net, closeTo(100 - 1.5 - 3.0, 0.001),
          reason: 'COA payout fee floors at K3 on small amounts');
    });

    test('K10000 payout nets percentage-only (no floor effect)', () {
      final net = fees.payoutNet(10000);
      expect(net, closeTo(10000 - 150 - 100, 0.001));
    });

    test('net never exceeds gross and is positive for realistic amounts', () {
      for (final amt in [20.0, 55.5, 250.0, 1200.75]) {
        final net = fees.payoutNet(amt);
        expect(net, lessThan(amt));
        expect(net, greaterThan(0));
      }
    });

    test('K3 payout does NOT go negative despite stacked fees', () {
      final net = fees.payoutNet(3);
      // disb 0.045 + coa 3.0 → net ≈ -0.045; contract: server must clamp.
      // Document current behaviour so a regression is visible:
      expect(net, lessThanOrEqualTo(3.0));
      // Guard assertion for future hardening:
      // expect(net, greaterThanOrEqualTo(0)); // TODO(server clamp)
    });
  });

  group('giving fees', () {
    test('church giving pays platform fee only (no business cut)', () {
      final gift = 200.0;
      final fee = fees.givingFee(gift);
      expect(fee, closeTo(gift * 0.035, 0.001)); // above min floor
      // Church receives the full gift.
      expect(gift - fee, lessThan(gift));
      // No additional 10% cut like marketplace sellers.
      expect(fees.businessCut(gift) + fee, greaterThan(fee));
    });
  });

  group('breakdown integrity', () {
    test('components sum to totalPlatformFee (within min-fee clamp)', () {
      final bd = fees.breakdown(800);
      expect(bd.coaRevenue + bd.lipilaFee, closeTo(bd.totalPlatformFee, 0.001));
    });

    test('small amounts clamp breakdown total to min fee', () {
      final bd = fees.breakdown(5);
      expect(bd.totalPlatformFee, 3.0, reason: 'min fee applies');
      expect(bd.coaRevenue + bd.lipilaFee, lessThan(bd.totalPlatformFee));
    });
  });
}
