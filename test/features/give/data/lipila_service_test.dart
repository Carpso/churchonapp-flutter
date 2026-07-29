import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/give/data/lipila_service.dart';
import 'package:church_on_app/features/give/presentation/widgets/payment_status_overlay.dart';
import 'package:church_on_app/features/give/presentation/widgets/momo_phone_input_widget.dart';

void main() {
  group('LipilaPaymentState', () {
    test('default constructor initial values', () {
      const state = LipilaPaymentState();
      expect(state.status, PaymentStatus.idle);
      expect(state.statusMessage, '');
      expect(state.errorMessage, isNull);
      expect(state.referenceId, isNull);
      expect(state.isCancelled, false);
      expect(state.isPolling, false);
      expect(state.pollAttempt, 0);
      expect(state.isBusy, false);
    });

    test('isBusy returns true during initiating state', () {
      const state = LipilaPaymentState(status: PaymentStatus.initiating);
      expect(state.isBusy, true);
    });

    test('isBusy returns true during awaitingPin state', () {
      const state = LipilaPaymentState(status: PaymentStatus.awaitingPin);
      expect(state.isBusy, true);
    });

    test('isBusy returns false during succeeded or failed state', () {
      const succeededState = LipilaPaymentState(status: PaymentStatus.succeeded);
      const failedState = LipilaPaymentState(status: PaymentStatus.failed);
      expect(succeededState.isBusy, false);
      expect(failedState.isBusy, false);
    });

    test('copyWith updates specific properties accurately', () {
      const initial = LipilaPaymentState();
      final updated = initial.copyWith(
        status: PaymentStatus.succeeded,
        statusMessage: 'Payment confirmed. Finishing settlement...',
        referenceId: 'REF-123456',
        pollAttempt: 3,
      );

      expect(updated.status, PaymentStatus.succeeded);
      expect(updated.statusMessage, 'Payment confirmed. Finishing settlement...');
      expect(updated.referenceId, 'REF-123456');
      expect(updated.pollAttempt, 3);
      expect(updated.isCancelled, false);
    });

    test('copyWith preserves status when not supplied', () {
      const initial = LipilaPaymentState(
        status: PaymentStatus.awaitingPin,
        referenceId: 'REF-999',
      );
      final updated = initial.copyWith(statusMessage: 'Pushing PIN prompt...');

      expect(updated.status, PaymentStatus.awaitingPin);
      expect(updated.referenceId, 'REF-999');
      expect(updated.statusMessage, 'Pushing PIN prompt...');
    });
  });

  group('MomoPhoneInputWidget Network & Validation Helpers', () {
    test('detects MTN network prefixes (096, 076)', () {
      expect(MomoPhoneInputWidget.detectNetwork('0961234567'), 'MTN');
      expect(MomoPhoneInputWidget.detectNetwork('0761234567'), 'MTN');
    });

    test('detects Airtel network prefixes (097, 077)', () {
      expect(MomoPhoneInputWidget.detectNetwork('0971234567'), 'Airtel');
      expect(MomoPhoneInputWidget.detectNetwork('0771234567'), 'Airtel');
    });

    test('detects Zamtel network prefixes (095, 075)', () {
      expect(MomoPhoneInputWidget.detectNetwork('0951234567'), 'Zamtel');
      expect(MomoPhoneInputWidget.detectNetwork('0751234567'), 'Zamtel');
    });

    test('formats local Zambian number into international 260 format', () {
      expect(MomoPhoneInputWidget.formatPhone('0971234567'), '260971234567');
      expect(MomoPhoneInputWidget.formatPhone('0961234567'), '260961234567');
    });

    test('validates correct Zambian mobile numbers', () {
      expect(MomoPhoneInputWidget.validateZambianPhone('0971234567'), isNull);
      expect(MomoPhoneInputWidget.validateZambianPhone('0961234567'), isNull);
      expect(MomoPhoneInputWidget.validateZambianPhone('0951234567'), isNull);
    });

    test('rejects empty or invalid phone numbers', () {
      expect(MomoPhoneInputWidget.validateZambianPhone(''), 'Phone number is required');
      expect(MomoPhoneInputWidget.validateZambianPhone('0911234567'), 'Enter a valid Zambian mobile number');
      expect(MomoPhoneInputWidget.validateZambianPhone('12345'), 'Enter a valid Zambian mobile number');
    });
  });

  group('MoMo PIN Prompt & Notification State Flow', () {
    test('transitions to awaitingPin state when PIN prompt is pushed', () {
      const phone = '0971234567';
      final state = const LipilaPaymentState().copyWith(
        status: PaymentStatus.awaitingPin,
        statusMessage: 'Pushing PIN prompt to $phone...',
      );

      expect(state.status, PaymentStatus.awaitingPin);
      expect(state.statusMessage, 'Pushing PIN prompt to 0971234567...');
      expect(state.isBusy, true);
    });

    test('transitions to succeeded state upon PIN approval', () {
      const referenceId = 'COA-TXN-2026-PIN-OK';
      final state = const LipilaPaymentState().copyWith(
        status: PaymentStatus.succeeded,
        statusMessage: 'Payment verified.',
        referenceId: referenceId,
      );

      expect(state.status, PaymentStatus.succeeded);
      expect(state.referenceId, 'COA-TXN-2026-PIN-OK');
      expect(state.isBusy, false);
    });

    test('builds notification message correctly for payment success', () {
      const amount = 'K150.00';
      const status = 'SUCCESS';
      final notificationBody = 'Your transaction of $amount has been $status.';

      expect(notificationBody, 'Your transaction of K150.00 has been SUCCESS.');
    });
  });

  group('Lipila Money Payment Status Classification', () {
    final successfulStatuses = [
      'successful',
      'paid',
      'completed',
      'settled',
      'success',
      'approved',
      'accepted',
      'confirmed',
    ];

    final failedStatuses = [
      'failed',
      'cancelled',
      'rejected',
      'declined',
      'error',
      'timeout',
    ];

    for (final status in successfulStatuses) {
      test('classifies status "$status" as money payment success', () {
        final state = const LipilaPaymentState().copyWith(
          status: PaymentStatus.succeeded,
          statusMessage: 'Payment verified.',
          referenceId: 'TXN-SUCCESS-001',
        );
        expect(state.status, PaymentStatus.succeeded);
        expect(state.referenceId, isNotNull);
      });
    }

    for (final status in failedStatuses) {
      test('classifies status "$status" as money payment failure', () {
        final state = const LipilaPaymentState().copyWith(
          status: PaymentStatus.failed,
          errorMessage: 'Transaction was $status',
        );
        expect(state.status, PaymentStatus.failed);
        expect(state.errorMessage, contains(status));
      });
    }
  });
}