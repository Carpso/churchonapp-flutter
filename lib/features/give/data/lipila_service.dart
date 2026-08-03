import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:church_on_app/core/services/payment_reliability_service.dart';
import 'package:church_on_app/features/give/presentation/widgets/payment_status_overlay.dart';
import 'package:church_on_app/features/give/presentation/widgets/momo_phone_input_widget.dart';

class LipilaPaymentState {
  final PaymentStatus status;
  final String statusMessage;
  final String? errorMessage;
  final String? referenceId;
  final String? cardUrl;
  final bool isCancelled;
  final bool isPolling;
  final int pollAttempt;

  const LipilaPaymentState({
    this.status = PaymentStatus.idle,
    this.statusMessage = '',
    this.errorMessage,
    this.referenceId,
    this.cardUrl,
    this.isCancelled = false,
    this.isPolling = false,
    this.pollAttempt = 0,
  });

  bool get isBusy =>
      status == PaymentStatus.initiating || status == PaymentStatus.awaitingPin;

  LipilaPaymentState copyWith({
    PaymentStatus? status,
    String? statusMessage,
    String? errorMessage,
    String? referenceId,
    String? cardUrl,
    bool? isCancelled,
    bool? isPolling,
    int? pollAttempt,
  }) {
    return LipilaPaymentState(
      status: status ?? this.status,
      statusMessage: statusMessage ?? this.statusMessage,
      errorMessage: errorMessage,
      referenceId: referenceId ?? this.referenceId,
      cardUrl: cardUrl ?? this.cardUrl,
      isCancelled: isCancelled ?? this.isCancelled,
      isPolling: isPolling ?? this.isPolling,
      pollAttempt: pollAttempt ?? this.pollAttempt,
    );
  }
}

class LipilaPaymentNotifier extends AsyncNotifier<LipilaPaymentState> {
  Timer? _pollTimer;

  @override
  Future<LipilaPaymentState> build() async {
    ref.onDispose(_cancelPolling);
    return const LipilaPaymentState();
  }

  void _cancelPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void reset() {
    _cancelPolling();
    state = const AsyncData(LipilaPaymentState());
  }

  void cancel() {
    _cancelPolling();
    state = const AsyncData(LipilaPaymentState(
      status: PaymentStatus.cancelled,
      statusMessage: "Payment cancelled. Tap retry to try again.",
    ));
  }

  Future<void> initiatePayment({
    required String phone,
    required double amount,
    required String description,
    String? narration,
  }) async {
    if (phone.isEmpty) {
      state = AsyncData(
        const LipilaPaymentState().copyWith(
          status: PaymentStatus.failed,
          errorMessage: "Phone number is required",
        ),
      );
      return;
    }

    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    final token = session?.accessToken;
    if (token == null) {
      state = AsyncData(
        const LipilaPaymentState().copyWith(
          status: PaymentStatus.failed,
          errorMessage: "Not authenticated. Please sign in.",
        ),
      );
      return;
    }

    state = AsyncData(
      const LipilaPaymentState().copyWith(
        status: PaymentStatus.initiating,
        statusMessage: "Connecting to Lipila Gateway...",
      ),
    );

    try {
      final formattedPhone = MomoPhoneInputWidget.formatPhone(phone);
      final String referenceId = const Uuid().v4();

      final response = await client.functions.invoke('lipila-collect', body: {
        "action": "initiate",
        "accountNumber": formattedPhone,
        "amount": amount,
        "narration": narration ?? description,
        "reference": referenceId,
      });

      if (response.data == null) {
        throw Exception(response.status != 200
            ? "Collection failed (${response.status})"
            : "No response from gateway");
      }

      state = AsyncData(
        (state.value ?? const LipilaPaymentState()).copyWith(
          status: PaymentStatus.awaitingPin,
          statusMessage: "Pushing PIN prompt to $phone...",
        ),
      );

      await _startPolling(referenceId, client);
    } catch (e) {
      _cancelPolling();
      final current = state.value;
      state = AsyncData(
        current?.copyWith(
              status: PaymentStatus.failed,
              errorMessage: e.toString().replaceFirst("Exception: ", ""),
            ) ??
            const LipilaPaymentState().copyWith(
              status: PaymentStatus.failed,
              errorMessage: e.toString().replaceFirst("Exception: ", ""),
            ),
      );
    }
  }

  Future<void> initiateCardPayment({
    required double amount,
    required String description,
    String? narration,
    required String firstName,
    required String lastName,
    String? email,
    String? phone,
  }) async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    final token = session?.accessToken;
    if (token == null) {
      state = AsyncData(
        const LipilaPaymentState().copyWith(
          status: PaymentStatus.failed,
          errorMessage: "Not authenticated. Please sign in.",
        ),
      );
      return;
    }

    state = AsyncData(
      const LipilaPaymentState().copyWith(
        status: PaymentStatus.initiating,
        statusMessage: "Connecting to card payment gateway...",
      ),
    );

    try {
      final String referenceId = const Uuid().v4();

      final response = await client.functions.invoke('lipila-card-collect', body: {
        "amount": amount,
        "narration": narration ?? description,
        "reference": referenceId,
        "firstName": firstName,
        "lastName": lastName,
        "email": email ?? "",
        "phone": phone ?? "",
      });

      if (response.data == null) {
        throw Exception(response.status != 200
            ? "Card collection failed (${response.status})"
            : "No response from gateway");
      }

      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : {};

      final cardUrl = data['url'] as String?;
      if (cardUrl == null || cardUrl.isEmpty) {
        throw Exception("No card payment URL returned");
      }

      state = AsyncData(
        (state.value ?? const LipilaPaymentState()).copyWith(
          status: PaymentStatus.cardRedirect,
          statusMessage: "Opening card payment page...",
          referenceId: referenceId,
          cardUrl: cardUrl,
        ),
      );

      // Start polling after redirect — user will complete card payment externally
      await _startPolling(referenceId, client);
    } catch (e) {
      _cancelPolling();
      final current = state.value;
      state = AsyncData(
        current?.copyWith(
              status: PaymentStatus.failed,
              errorMessage: e.toString().replaceFirst("Exception: ", ""),
            ) ??
            const LipilaPaymentState().copyWith(
              status: PaymentStatus.failed,
              errorMessage: e.toString().replaceFirst("Exception: ", ""),
            ),
      );
    }
  }

  Future<void> _startPolling(
    String referenceId,
    SupabaseClient client,
  ) async {
    const maxAttempts = 20;
    int attempts = 0;

    _cancelPolling();

    // Check DB immediately first (fastest path)
    try {
      final localPayment = await client
          .from('coa_payments')
          .select('status, payment_ref')
          .eq('payment_ref', referenceId)
          .maybeSingle();

      if (localPayment != null) {
        final dbStatus = (localPayment['status'] ?? '').toString().toLowerCase();
        if (dbStatus == 'approved' || dbStatus == 'completed' || dbStatus == 'confirmed' || dbStatus == 'settled') {
          state = AsyncData(
            (state.value ?? const LipilaPaymentState()).copyWith(
              status: PaymentStatus.succeeded,
              statusMessage: "Payment verified.",
              referenceId: referenceId,
            ),
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('LipilaService: Initial DB check failed: $e');
    }

    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;

      if (state.value?.isCancelled == true) {
        timer.cancel();
        return;
      }

      final current = state.value;
      state = AsyncData(
        (current ?? const LipilaPaymentState()).copyWith(
          statusMessage: "Verifying payment... ($attempts/$maxAttempts)",
          pollAttempt: attempts,
        ),
      );

      // Check DB first on each poll (faster than Edge Function round-trip)
      try {
        final localPayment = await client
            .from('coa_payments')
            .select('status, payment_ref')
            .eq('payment_ref', referenceId)
            .maybeSingle();

        if (localPayment != null) {
          final dbStatus = (localPayment['status'] ?? '').toString().toLowerCase();
          if (dbStatus == 'approved' || dbStatus == 'completed' || dbStatus == 'confirmed' || dbStatus == 'settled') {
            timer.cancel();
            state = AsyncData(
              (state.value ?? const LipilaPaymentState()).copyWith(
                status: PaymentStatus.succeeded,
                statusMessage: "Payment verified.",
                referenceId: referenceId,
              ),
            );
            return;
          } else if (dbStatus == 'rejected' || dbStatus == 'failed' || dbStatus == 'cancelled') {
            timer.cancel();
            state = AsyncData(
              (state.value ?? const LipilaPaymentState()).copyWith(
                status: PaymentStatus.failed,
                errorMessage: "Payment was $dbStatus by administrator.",
                statusMessage: "Payment $dbStatus.",
              ),
            );
            return;
          }
        }
      } catch (e) {
        debugPrint('LipilaService: Poll DB check failed (attempt $attempts): $e');
      }

      try {
        final statusResponse = await client.functions.invoke('lipila-collect', body: {
          "action": "status",
          "reference": referenceId,
        });

        if (statusResponse.data != null) {
          final statusData = statusResponse.data is Map
              ? Map<String, dynamic>.from(statusResponse.data as Map)
              : jsonDecode(jsonEncode(statusResponse.data)) as Map<String, dynamic>;

          String status = '';
          try {
            status = (statusData['data']?['status'] ??
                    statusData['data']?['data']?['status'] ??
                    statusData['data']?['transaction']?['status'] ??
                    statusData['status'] ??
                    statusData['transaction']?['status'] ??
                    statusData['data']?['transactionStatus'] ??
                    statusData['transactionStatus'] ??
                    '')
                .toString()
                .toLowerCase()
                .trim();
          } catch (_) {
            status = '';
          }

          if (status == 'successful' ||
              status == 'paid' ||
              status == 'completed' ||
              status == 'settled' ||
              status == 'success' ||
              status == 'approved' ||
              status == 'accepted' ||
              status == 'confirmed') {
            timer.cancel();
            state = AsyncData(
              (state.value ?? const LipilaPaymentState()).copyWith(
                status: PaymentStatus.succeeded,
                statusMessage: "Payment confirmed. Finishing settlement...",
                referenceId: referenceId,
              ),
            );
            return;
          } else if (status == 'failed' ||
              status == 'cancelled' ||
              status == 'rejected' ||
              status == 'declined' ||
              status == 'error' ||
              status == 'timeout') {
            timer.cancel();
            state = AsyncData(
              (state.value ?? const LipilaPaymentState()).copyWith(
                status: PaymentStatus.failed,
                errorMessage: "Transaction was $status by user or provider.",
                statusMessage: "Transaction $status. Tap retry to try again.",
              ),
            );
            return;
          }
        }
      } catch (e) {
        debugPrint("Error polling payment status (attempt $attempts): $e");
      }

      try {
        final payment = await client
            .from('coa_payments')
            .select('status, payment_ref')
            .eq('payment_ref', referenceId)
            .maybeSingle();

        if (payment != null) {
          final dbStatus = (payment['status'] ?? '').toString().toLowerCase();
          if (dbStatus == 'approved' || dbStatus == 'completed' || dbStatus == 'confirmed' || dbStatus == 'settled') {
            timer.cancel();
            state = AsyncData(
              (state.value ?? const LipilaPaymentState()).copyWith(
                status: PaymentStatus.succeeded,
                statusMessage: "Payment verified successfully.",
                referenceId: referenceId,
              ),
            );
            return;
          } else if (dbStatus == 'rejected' || dbStatus == 'failed' || dbStatus == 'cancelled') {
            timer.cancel();
            state = AsyncData(
              (state.value ?? const LipilaPaymentState()).copyWith(
                status: PaymentStatus.failed,
                errorMessage: "Payment was $dbStatus by administrator.",
                statusMessage: "Payment $dbStatus.",
              ),
            );
            return;
          }
        }
      } catch (e) {
        debugPrint('LipilaService: Final DB check failed (attempt $attempts): $e');
      }

      if (attempts >= maxAttempts) {
        timer.cancel();
        final reliability = PaymentReliabilityService(client);
        unawaited(reliability.queuePaymentForRetry(
          referenceId: referenceId,
          amount: 0.0,
          recipientPhone: '',
          method: 'coa_payment',
          metadata: {'type': 'coa_payment_timeout', 'reference': referenceId},
        ));
        state = AsyncData(
          (state.value ?? const LipilaPaymentState()).copyWith(
            status: PaymentStatus.failed,
            errorMessage: "Payment verification timed out. Your money has been deducted. Reference: $referenceId",
            statusMessage: "Still verifying payment. Reference: ${referenceId.substring(0, referenceId.length.clamp(0, 8))}",
          ),
        );
      }
    });
  }
}

final lipilaPaymentProvider =
    AsyncNotifierProvider<LipilaPaymentNotifier, LipilaPaymentState>(
  LipilaPaymentNotifier.new,
);
