import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/admin/data/promo_code_service.dart';

/// User-facing entry point to redeem a promo code.
///
/// Redeeming is fully server-side (`redeem_promo_code`) — limits, expiry and
/// the per-user cap are enforced by the database, never the client.
class RedeemCodeScreen extends ConsumerStatefulWidget {
  const RedeemCodeScreen({super.key});

  @override
  ConsumerState<RedeemCodeScreen> createState() => _RedeemCodeScreenState();
}

class _RedeemCodeScreenState extends ConsumerState<RedeemCodeScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _success = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final res = await ref.read(promoCodeServiceProvider).redeem(code);
      if (!mounted) return;
      if (res['ok'] == true) {
        ref.invalidate(profileProvider);
        setState(() {
          _success = true;
          final kind = res['kind'];
          _message = kind == 'cc'
              ? 'Success! ${(res['value'] as num?)?.toInt() ?? 0} Church Coins added.'
              : 'Code redeemed (${res['kind']}).';
        });
      } else {
        setState(() {
          _success = false;
          _message = _reason(res['reason']?.toString());
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _success = false;
          _message = 'Could not redeem: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _reason(String? reason) {
    switch (reason) {
      case 'not_found':
        return 'That code does not exist.';
      case 'expired':
        return 'That code has expired.';
      case 'inactive':
        return 'That code is no longer active.';
      case 'exhausted':
        return 'That code has reached its usage limit.';
      case 'per_user_limit':
        return 'You have already used that code.';
      default:
        return 'Could not redeem that code.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Redeem a Code')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),
          Icon(LucideIcons.ticket, size: 48, color: theme.primaryColor),
          const SizedBox(height: 16),
          const Text(
            'Enter a promo code',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Promo codes can add Church Coins, unlock a quiz pass or apply a discount.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              labelText: 'Promo code',
              hintText: 'COA-PROMO-XXXXXX',
              border: OutlineInputBorder(),
              prefixIcon: Icon(LucideIcons.tag),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _busy ? null : _redeem,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('REDEEM'),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (_success ? Colors.green : Colors.red).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(_success ? LucideIcons.checkCircle : LucideIcons.alertCircle,
                    size: 18, color: _success ? Colors.green : Colors.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_message!,
                      style: TextStyle(
                          fontSize: 13,
                          color: _success ? Colors.green : Colors.red)),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
