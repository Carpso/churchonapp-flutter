import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
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
  bool _isPollingInFlight = false;

  @override
  Future<LipilaPaymentState> build() async {
    ref.onDispose(_cancelPolling);
    return const LipilaPaymentState();
  }

  Map<String, dynamic> _buildMetadata({
    String? referenceId,
    String? category,
  }) {
    final profile = ref.read(profileProvider).value;
    final user = Supabase.instance.client.auth.currentUser;
    final organizationId = profile?.organizationId;
    final tenantId = profile?.tenantId;
    return {
      if (user != null) 'user_id': user.id,
      if (organizationId != null && organizationId.isNotEmpty) 'organization_id': organizationId,
      if (tenantId != null && tenantId.isNotEmpty) 'tenant_id': tenantId,
      if (tenantId != null && tenantId.isNotEmpty) 'branch_id': tenantId,
      if (referenceId != null) 'reference_id': referenceId,
      // lipila-collect reads these into coa_payments.service_type / .category —
      // without them every server-created payment row lands as generic 'giving'.
      if (category != null && category.isNotEmpty) 'service_type': category,
      if (category != null && category.isNotEmpty) 'category': category,
    };
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
      isCancelled: true,
    ));
  }

  Future<void> initiatePayment({
    required String phone,
    required double amount,
    required String description,
    String? narration,
    String? reference,
    String? category,
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
      // A server-issued reference (e.g. request_meeting_subscription) is used
      // verbatim so the confirmed coa_payments anchor is the one the server
      // pre-created; otherwise a fresh client reference is generated.
      final String referenceId = reference ?? const Uuid().v4();

      final response = await client.functions
          .invoke('lipila-collect', body: {
            "action": "initiate",
            "accountNumber": formattedPhone,
            "amount": amount,
            "narration": narration ?? description,
            "reference": referenceId,
            "metadata": _buildMetadata(
              referenceId: referenceId,
              category: category,
            ),
          })
          .timeout(const Duration(seconds: 30));

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
    String? reference,
    String? category,
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
      final String referenceId = reference ?? const Uuid().v4();

      final response = await client.functions
          .invoke('lipila-card-collect', body: {
            "amount": amount,
            "narration": narration ?? description,
            "reference": referenceId,
            "firstName": firstName,
            "lastName": lastName,
            "email": email ?? "",
            "phone": phone ?? "",
            "metadata": _buildMetadata(
              referenceId: referenceId,
              category: category,
            ),
          })
          .timeout(const Duration(seconds: 30));

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
      await _startPolling(referenceId, client, isCard: true);
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
    SupabaseClient client, {
    bool isCard = false,
  }) async {
    // Card: the user is completing payment on an external redirect page, so
    // give it room (150 x 3s = 7.5 min). MoMo: PIN prompt is near-instant
    // (60 x 2s = 2 min — was 40s, which timed out while people were still
    // entering their PIN).
    final int maxAttempts = isCard ? 150 : 60;
    final Duration pollEvery = Duration(seconds: isCard ? 3 : 2);
    // How often to ask the server to reconcile with Lipila. Every 5th tick keeps
    // Edge invocations reasonable while still resolving well inside the poll window.
    const int activeReconcileEvery = 5;
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

    _pollTimer = Timer.periodic(pollEvery, (timer) async {
      // Skip this tick if the previous iteration is still awaiting a response,
      // so overlapping polls can never race on shared state.
      if (_isPollingInFlight) return;
      _isPollingInFlight = true;

      attempts++;

      if (state.value?.isCancelled == true) {
        timer.cancel();
        _isPollingInFlight = false;
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
            _isPollingInFlight = false;
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
            _isPollingInFlight = false;
            return;
          }
        }
      } catch (e) {
        debugPrint('LipilaService: Poll DB check failed (attempt $attempts): $e');
      }

      try {
        final statusResponse = await client.functions
            .invoke('lipila-collect', body: {
              "action": "status",
              "reference": referenceId,
            })
            .timeout(const Duration(seconds: 15));

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
            _isPollingInFlight = false;
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
            _isPollingInFlight = false;
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
            _isPollingInFlight = false;
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
            _isPollingInFlight = false;
            return;
          }
        }
} catch (e) {
          debugPrint('LipilaService: Final DB check failed (attempt $attempts): $e');
        }

        // ------------------------------------------------------------------
        // ACTIVE RECONCILIATION (the fix for "money deducted, no receipt")
        //
        // Until now this poll ONLY read coa_payments, which meant the webhook
        // was the single path to success. If Lipila took the money but the
        // webhook was delayed, dropped or rejected, the user watched a spinner
        // for two minutes and then saw a failure - despite having paid. That is
        // the worst possible failure for a payment product.
        //
        // The Edge Function already implements `action: 'status'`, which asks
        // Lipila directly and, when it reports a confirmed collection, WRITES
        // `settled` back to coa_payments and runs settlement. That safety net
        // existed but was never called by any client, so it was dead code.
        //
        // We now nudge it periodically while polling (throttled: every 5th
        // tick, so a 2-minute poll makes ~24 Edge calls rather than 60), and
        // once more at the very end before giving up. The DB poll above still
        // decides the UI, so this can never turn a pending payment into a false
        // success - it only makes the authoritative answer arrive sooner.
        // ------------------------------------------------------------------
        if (attempts % activeReconcileEvery == 0 || attempts >= maxAttempts) {
          final wasFinalAttempt = attempts >= maxAttempts;
          await _askServerForStatus(referenceId);
          if (wasFinalAttempt) {
            // Give the write a moment to land before reading it back.
            await Future<void>.delayed(const Duration(milliseconds: 1200));
            final settled = await _isConfirmedInDb(client, referenceId);
            timer.cancel();
            if (settled) {
              state = AsyncData(
                (state.value ?? const LipilaPaymentState()).copyWith(
                  status: PaymentStatus.succeeded,
                  statusMessage: "Payment confirmed.",
                  referenceId: referenceId,
                ),
              );
              _isPollingInFlight = false;
              return;
            }

            // Still unconfirmed. Do NOT tell the user it failed: the money may
            // well have left their account. Say what is actually true, and give
            // them the reference so support can trace it. This mirrors the
            // wording chisomo uses, which is deliberately reassuring-but-honest.
            final reliability = PaymentReliabilityService(client);
            unawaited(reliability.queuePaymentForRetry(
              referenceId: referenceId,
              amount: 0.0,
              recipientPhone: '',
              method: 'coa_payment',
              metadata: {'type': 'coa_payment_unconfirmed', 'reference': referenceId},
            ));
            state = AsyncData(
              (state.value ?? const LipilaPaymentState()).copyWith(
                status: PaymentStatus.failed,
                errorMessage:
                    "We are still confirming this payment. If you completed it, "
                    "it may take a moment to show. Reference: $referenceId",
                statusMessage: "Still confirming payment. Reference: $referenceId",
              ),
            );
            _isPollingInFlight = false;
            return;
          }
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
              errorMessage:
                  "Payment confirmation is taking longer than usual. Your money "
                  "has been deducted and will still be recorded. Reference: $referenceId",
              statusMessage: "Still confirming payment. Reference: $referenceId",
            ),
          );
        }

        _isPollingInFlight = false;
    });
  }

  /// Asks the Edge Function to resolve the payment with Lipila directly.
  ///
  /// Fire-and-forget: the response is deliberately NOT treated as the answer,
  /// because `coa_payments` is the single source of truth the rest of the app
  /// (receipts, giving history, settlement) reads from. This only nudges the
  /// server so that source of truth gets updated promptly.
  ///
  /// Never throws - a failure here must never break the user's payment screen.
  Future<void> _askServerForStatus(String referenceId) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'lipila-collect',
        body: {'action': 'status', 'reference': referenceId},
      );
      debugPrint(
          'LipilaService: asked server to reconcile $referenceId with Lipila');
    } catch (e) {
      debugPrint('LipilaService: status reconcile call failed (non-fatal): $e');
    }
  }

  /// Reads the authoritative status back out of `coa_payments`.
  Future<bool> _isConfirmedInDb(
      SupabaseClient client, String referenceId) async {
    try {
      final row = await client
          .from('coa_payments')
          .select('status')
          .eq('payment_ref', referenceId)
          .maybeSingle();
      final s = (row?['status'] ?? '').toString().toLowerCase();
      return s == 'approved' ||
          s == 'completed' ||
          s == 'confirmed' ||
          s == 'settled';
    } catch (e) {
      debugPrint('LipilaService: confirmation read failed (non-fatal): $e');
      return false;
    }
  }
}

final lipilaPaymentProvider =
    AsyncNotifierProvider<LipilaPaymentNotifier, LipilaPaymentState>(
  LipilaPaymentNotifier.new,
);
