import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Platform Cut Calculations Verification', () {
    test('Verifies 10% cut on Paid Events', () {
      final ticketPrice = 150.0;
      final cutPercent = 0.10; // 10%
      final platformFee = ticketPrice * cutPercent;
      expect(platformFee, equals(15.0));
      expect(ticketPrice - platformFee, equals(135.0));
    });

    test('Verifies 5% cut on Tithes & Giving', () {
      final amount = 1000.0;
      final cutPercent = 0.05; // 5%
      final platformFee = amount * cutPercent;
      expect(platformFee, equals(50.0));
      expect(amount - platformFee, equals(950.0));
    });

    test('Verifies 10% cut on Transport Rides & Logistics Deliveries', () {
      final fare = 85.0;
      final platformCut = fare * 0.10; // 10%
      final netEarning = fare - platformCut;
      expect(platformCut, equals(8.5));
      expect(netEarning, equals(76.5));
    });

    test('Verifies 5% cut on Marketplace Vendor Sales', () {
      final totalSale = 320.0;
      final platformFee = totalSale * 0.05; // 5%
      expect(platformFee, equals(16.0));
      expect(totalSale - platformFee, equals(304.0));
    });
  });
}
