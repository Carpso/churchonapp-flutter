import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Landing page after a CARD checkout returns from Lipila — the card flow's
/// `backUrl` is `https://churchonapp.com/payment-complete?ref=...`, so this
/// route MUST exist on the web SPA (without it, returning card payers hit the
/// router's not-found page).
///
/// Verifies the payment server-side by polling the `coa_payments` anchor
/// (and the `transactions` history row as a fallback) for the reference.
class PaymentCompleteScreen extends StatefulWidget {
  final String? reference;

  const PaymentCompleteScreen({super.key, this.reference});

  @override
  State<PaymentCompleteScreen> createState() => _PaymentCompleteScreenState();
}

enum _VerifyState { checking, success, failed, unverified }

class _PaymentCompleteScreenState extends State<PaymentCompleteScreen> {
  static const _confirmed = {'approved', 'completed', 'confirmed', 'settled'};
  static const _terminalFail = {'failed', 'cancelled', 'expired'};

  _VerifyState _state = _VerifyState.checking;
  String? _status;
  Timer? _timer;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    if ((widget.reference ?? '').isEmpty) {
      _state = _VerifyState.unverified;
    } else {
      _verify();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verify() async {
    _timer?.cancel();
    setState(() {
      _state = _VerifyState.checking;
      _attempts = 0;
      _status = null;
    });
    _tick();
  }

  Future<void> _tick() async {
    final ref = widget.reference;
    if (ref == null || ref.isEmpty) return;
    final client = Supabase.instance.client;

    // ~60s of polling at 2s intervals.
    while (_attempts < 30 && mounted) {
      _attempts++;
      try {
        final payment = await client
            .from('coa_payments')
            .select('status')
            .eq('payment_ref', ref)
            .maybeSingle();
        String? status = payment?['status'] as String?;
        if (status == null) {
          // transactions stores the reference in `reference` (not payment_ref).
          final tx = await client
              .from('transactions')
              .select('status')
              .eq('reference', ref)
              .maybeSingle();
          status = tx?['status'] as String?;
        }
        if (status != null) {
          if (_confirmed.contains(status)) {
            if (mounted) {
              setState(() {
                _state = _VerifyState.success;
                _status = status;
              });
            }
            return;
          }
          if (_terminalFail.contains(status)) {
            if (mounted) {
              setState(() {
                _state = _VerifyState.failed;
                _status = status;
              });
            }
            return;
          }
          if (mounted) setState(() => _status = status);
        }
      } catch (e) {
        debugPrint('payment-complete verify error: $e');
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    if (mounted && _state == _VerifyState.checking) {
      setState(() => _state = _VerifyState.unverified);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Status'),
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: switch (_state) {
            _VerifyState.checking => _buildChecking(theme),
            _VerifyState.success => _buildSuccess(theme),
            _VerifyState.failed => _buildFailed(theme),
            _VerifyState.unverified => _buildUnverified(theme),
          },
        ),
      ),
    );
  }

  Widget _buildChecking(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        const Text(
          'Verifying your payment…',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'REF: ${widget.reference ?? ''}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (_status != null) ...[
          const SizedBox(height: 6),
          Text(
            'Status: $_status',
            style: TextStyle(fontSize: 12, color: theme.hintColor),
          ),
        ],
      ],
    );
  }

  Widget _buildSuccess(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(LucideIcons.checkCircle, size: 76, color: Colors.green),
        const SizedBox(height: 20),
        const Text(
          'Payment Confirmed',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Your reference ${widget.reference ?? ''} is confirmed ($_status).',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.hintColor),
        ),
        const SizedBox(height: 30),
        FilledButton(
          onPressed: () => context.go('/'),
          style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56)),
          child: const Text('DONE'),
        ),
      ],
    );
  }

  Widget _buildFailed(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(LucideIcons.xCircle, size: 76, color: Colors.red),
        const SizedBox(height: 20),
        const Text(
          'Payment Not Completed',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'The transaction ended as "$_status". No money was taken — you can try again.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.hintColor),
        ),
        const SizedBox(height: 30),
        FilledButton(
          onPressed: () => context.go('/'),
          style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56)),
          child: const Text('BACK TO HOME'),
        ),
      ],
    );
  }

  Widget _buildUnverified(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(LucideIcons.clock, size: 76, color: Colors.amber),
        const SizedBox(height: 20),
        const Text(
          'Still Confirming',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          "We haven't seen the confirmation yet. This usually settles within a minute — check your Giving history in a moment.",
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.hintColor),
        ),
        const SizedBox(height: 30),
        FilledButton(
          onPressed: _verify,
          style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56)),
          child: const Text('CHECK AGAIN'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('BACK TO HOME'),
        ),
      ],
    );
  }
}
