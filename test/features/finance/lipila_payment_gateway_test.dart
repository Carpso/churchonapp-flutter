import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LipilaPaymentGateway Status Parsing Verification', () {
    String parseStatus(dynamic responseData) {
      if (responseData != null && responseData is Map) {
        final statusData = responseData;
        final data = statusData['data'] is Map ? statusData['data'] as Map : null;
        final nestedData = data?['data'] is Map ? data!['data'] as Map : null;
        return (nestedData?['status'] ?? data?['status'] ?? '').toString().toLowerCase();
      }
      return '';
    }

    test('Parses standard Map<String, dynamic> status response successfully', () {
      final Map<String, dynamic> response = {
        'status': 200,
        'data': {
          'status': 'SUCCESSFUL',
          'message': 'Transaction was successful',
        }
      };

      expect(parseStatus(response), equals('successful'));
    });

    test('Parses nested Map<String, dynamic> status response successfully', () {
      final Map<String, dynamic> response = {
        'status': 200,
        'data': {
          'data': {
            'status': 'PAID',
          }
        }
      };

      expect(parseStatus(response), equals('paid'));
    });

    test('Parses Map<dynamic, dynamic> status response successfully without runtime crashes', () {
      final Map<dynamic, dynamic> response = {
        'status': 200,
        'data': {
          'status': 'COMPLETED',
        }
      };

      expect(parseStatus(response), equals('completed'));
    });

    test('Parses deeply nested Map<dynamic, dynamic> status response successfully without runtime crashes', () {
      final Map<dynamic, dynamic> response = {
        'status': 200,
        'data': {
          'data': {
            'status': 'SETTLED',
          }
        }
      };

      expect(parseStatus(response), equals('settled'));
    });

    test('Returns empty string when status is missing', () {
      final Map<String, dynamic> response = {
        'status': 200,
        'data': {
          'message': 'No status field',
        }
      };

      expect(parseStatus(response), equals(''));
    });
  });
}
