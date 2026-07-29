import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

class LipilaWebhookPayload {
  final String referenceId;
  final String identifier;
  final double amount;
  final String currency;
  final String status;
  final String type; // "Collection" | "Disbursement"
  final String? accountNumber;

  const LipilaWebhookPayload({
    required this.referenceId,
    required this.identifier,
    required this.amount,
    this.currency = 'ZMW',
    required this.status,
    required this.type,
    this.accountNumber,
  });

  bool get isSuccess => status.toLowerCase() == 'successful';

  double calculatePlatformFee({String category = 'giving'}) {
    final cutPercent = category == 'event' ? 0.10 : 0.05;
    final fee = amount * cutPercent;
    return fee > 5.0 ? fee : 5.0;
  }

  double calculateNetPayout({String category = 'giving'}) {
    return amount - calculatePlatformFee(category: category);
  }

  Map<String, dynamic> toJson() => {
        'referenceId': referenceId,
        'identifier': identifier,
        'amount': amount,
        'currency': currency,
        'status': status,
        'type': type,
        'accountNumber': accountNumber,
      };
}

class LipilaWebhookSigner {
  static String generateSignature({
    required String webhookId,
    required String timestamp,
    required String rawBody,
    required String secretBase64,
  }) {
    final payload = '$webhookId.$timestamp.$rawBody';
    final secretBytes = base64.decode(secretBase64);
    final hmac = Hmac(sha256, secretBytes);
    final digest = hmac.convert(utf8.encode(payload));
    final sigBase64 = base64.encode(digest.bytes);
    return 'v1,$sigBase64';
  }

  static bool verifySignature({
    required String webhookId,
    required String timestamp,
    required String rawBody,
    required String secretBase64,
    required String receivedHeader,
  }) {
    final expected = generateSignature(
      webhookId: webhookId,
      timestamp: timestamp,
      rawBody: rawBody,
      secretBase64: secretBase64,
    );
    return expected == receivedHeader;
  }
}

void main() {
  group('Lipila Webhook Payment Success Payload', () {
    test('identifies successful collection callback', () {
      const payload = LipilaWebhookPayload(
        referenceId: 'LIP-998877',
        identifier: 'COA-TXN-2026-001',
        amount: 200.0,
        status: 'Successful',
        type: 'Collection',
        accountNumber: '260971234567',
      );

      expect(payload.isSuccess, true);
      expect(payload.referenceId, 'LIP-998877');
      expect(payload.identifier, 'COA-TXN-2026-001');
      expect(payload.amount, 200.0);
    });

    test('calculates 5% platform fee for giving category (min K5.00)', () {
      const smallPayload = LipilaWebhookPayload(
        referenceId: 'LIP-001',
        identifier: 'COA-TXN-001',
        amount: 50.0, // 5% = K2.50 -> clamped to min K5.00
        status: 'Successful',
        type: 'Collection',
      );
      expect(smallPayload.calculatePlatformFee(category: 'giving'), 5.0);
      expect(smallPayload.calculateNetPayout(category: 'giving'), 45.0);

      const largePayload = LipilaWebhookPayload(
        referenceId: 'LIP-002',
        identifier: 'COA-TXN-002',
        amount: 1000.0, // 5% = K50.00
        status: 'Successful',
        type: 'Collection',
      );
      expect(largePayload.calculatePlatformFee(category: 'giving'), 50.0);
      expect(largePayload.calculateNetPayout(category: 'giving'), 950.0);
    });

    test('calculates 10% platform fee for event ticketing category', () {
      const eventPayload = LipilaWebhookPayload(
        referenceId: 'LIP-EVT-001',
        identifier: 'COA-TKT-2026-001',
        amount: 500.0, // 10% = K50.00
        status: 'Successful',
        type: 'Collection',
      );
      expect(eventPayload.calculatePlatformFee(category: 'event'), 50.0);
      expect(eventPayload.calculateNetPayout(category: 'event'), 450.0);
    });
  });

  group('Lipila Webhook Security & HMAC Verification', () {
    const testSecret = 'c3VwZXJzZWNyZXRrZXkxMjM0NTY3ODkwMTIzNDU2Nzg5MA=='; // base64 encoded
    const webhookId = 'wh_req_998877';
    const timestamp = '1774567800';
    final sampleJson = jsonEncode({
      'referenceId': 'LIP-998877',
      'identifier': 'COA-TXN-2026-001',
      'amount': 150.0,
      'status': 'Successful',
      'type': 'Collection',
    });

    test('generates and verifies valid HMAC-SHA256 signature', () {
      final sigHeader = LipilaWebhookSigner.generateSignature(
        webhookId: webhookId,
        timestamp: timestamp,
        rawBody: sampleJson,
        secretBase64: testSecret,
      );

      expect(sigHeader, startsWith('v1,'));

      final isValid = LipilaWebhookSigner.verifySignature(
        webhookId: webhookId,
        timestamp: timestamp,
        rawBody: sampleJson,
        secretBase64: testSecret,
        receivedHeader: sigHeader,
      );

      expect(isValid, true);
    });

    test('rejects tampered raw body payload', () {
      final sigHeader = LipilaWebhookSigner.generateSignature(
        webhookId: webhookId,
        timestamp: timestamp,
        rawBody: sampleJson,
        secretBase64: testSecret,
      );

      const tamperedJson = '{"amount": 1000.0, "status": "Successful"}';

      final isValid = LipilaWebhookSigner.verifySignature(
        webhookId: webhookId,
        timestamp: timestamp,
        rawBody: tamperedJson,
        secretBase64: testSecret,
        receivedHeader: sigHeader,
      );

      expect(isValid, false);
    });
  });

  group('Webhook Payment Notification Construction', () {
    test('builds payment_success notification payload for user', () {
      const amount = 250.0;
      const churchName = 'Grace Cathedral';
      const ref = 'COA-TXN-2026-099';

      final title = 'Payment Successful';
      final body = 'Your payment of K${amount.toStringAsFixed(2)} to $churchName was successful. Reference: $ref';

      expect(title, 'Payment Successful');
      expect(body, 'Your payment of K250.00 to Grace Cathedral was successful. Reference: COA-TXN-2026-099');
    });

    test('builds payment_received notification payload for pastor/treasurer', () {
      const amount = 500.0;
      const category = 'TITHE';
      const ref = 'COA-TXN-2026-100';

      final title = 'Payment Received';
      final body = 'A payment of K${amount.toStringAsFixed(2)} was received from a member. $category - Ref: $ref';

      expect(title, 'Payment Received');
      expect(body, 'A payment of K500.00 was received from a member. TITHE - Ref: COA-TXN-2026-100');
    });
  });
}
