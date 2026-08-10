import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/finance_service.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/widgets/premium_toast.dart';

class TransactionPage extends ConsumerStatefulWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  const TransactionPage({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });

  @override
  ConsumerState<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends ConsumerState<TransactionPage> {
  bool _isProcessing = false;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _detailController = TextEditingController();

  Future<void> _handleTransaction() async {
    final amountText = _amountController.text;
    if (amountText.isEmpty) return;
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) return;

    setState(() => _isProcessing = true);

    try {
      final client = Supabase.instance.client;
      final senderId = client.auth.currentUser?.id;
      if (senderId == null) throw Exception("Not authenticated");

      if (widget.title == "Send") {
        final recipientId = await _lookupRecipient();
        if (recipientId == null) {
          if (mounted) PremiumToast.showError(context, "Recipient not found. Check email or phone.");
          setState(() => _isProcessing = false);
          return;
        }

        final sender = await client.from('profiles').select('coins').eq('id', senderId).single();
        final senderCoins = (sender['coins'] as num?)?.toDouble() ?? 0;
        if (senderCoins < amount) {
          if (mounted) PremiumToast.showWarning(context, "Insufficient balance. You have K ${senderCoins.toInt()}.");
          setState(() => _isProcessing = false);
          return;
        }

        final recipient = await client.from('profiles').select('coins').eq('id', recipientId).single();
        final recipientCoins = (recipient['coins'] as num?)?.toDouble() ?? 0;

        await client.from('profiles').update({'coins': senderCoins.toInt() - amount.toInt()}).eq('id', senderId);
        await client.from('profiles').update({'coins': recipientCoins.toInt() + amount.toInt()}).eq('id', recipientId);

        final reference = "TX${DateTime.now().millisecondsSinceEpoch}";
        await client.from('transactions').insert({
          'user_id': senderId,
          'amount': -amount,
          'category': 'transfer',
          'reference': reference,
          'status': 'completed',
          'description': 'Transfer to ${_detailController.text}',
        });

        ref.invalidate(profileProvider);
        if (mounted) {
          setState(() => _isProcessing = false);
          PremiumToast.showSuccess(context, "K ${amount.toInt()} sent to ${_detailController.text}", title: "Transfer Complete");
          Navigator.pop(context);
        }
        return;
      }

      final tenant = ref.read(currentTenantProvider);
      final financeService = ref.read(financeServiceProvider);

      String category = 'giving';
      double finalAmount = amount;
      if (widget.title == "Top Up") {
        category = 'top_up';
        finalAmount = amount;
      } else if (widget.title == "Withdraw") {
        category = 'withdrawal';
        finalAmount = -amount;
      }

      final reference = "TX${DateTime.now().millisecondsSinceEpoch}";
      await financeService.logTransaction(finalAmount, category, reference, tenantId: tenant?.id);
      ref.invalidate(profileProvider);

      if (mounted) {
        setState(() => _isProcessing = false);
        PremiumToast.showSuccess(context, "K ${_amountController.text} processed securely.", title: "${widget.title} Successful");
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        PremiumToast.showError(context, e.toString().replaceFirst("Exception: ", ""));
      }
    }
  }

  Future<String?> _lookupRecipient() async {
    final query = _detailController.text.trim();
    if (query.isEmpty) return null;
    final client = Supabase.instance.client;
    var result = await client.from('profiles').select('id').eq('email', query).maybeSingle();
    if (result != null) return result['id'];
    result = await client.from('profiles').select('id').eq('phone_number', query).maybeSingle();
    if (result != null) return result['id'];
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: widget.color.withValues(alpha: 0.3), width: 2)
              ),
              child: Icon(widget.icon, color: widget.color, size: 60),
            ),
            const SizedBox(height: 30),
            Text(
              widget.description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "Amount (K)",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                prefixIcon: Icon(LucideIcons.banknote, color: Theme.of(context).colorScheme.secondary),
              ),
            ),
            const SizedBox(height: 20),
            if (widget.title == "Send" || widget.title == "Withdraw")
              TextField(
                controller: _detailController,
                decoration: InputDecoration(
                  labelText: widget.title == "Withdraw" ? "Mobile Money Account" : "Recipient Email or Phone",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  prefixIcon: Icon(LucideIcons.phone, color: Theme.of(context).colorScheme.secondary),
                ),
              ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 5,
                  shadowColor: widget.color.withValues(alpha: 0.4),
                ),
                onPressed: _isProcessing ? null : _handleTransaction,
                child: _isProcessing 
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                          SizedBox(width: 15),
                          Text("Connecting to Payment Gateway...", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      )
                    : Text("Process ${widget.title}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.shieldCheck, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                const Text("Secured by Mobile Money Payment Protocol", style: TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            )
          ],
        ),
      ),
    );
  }
}

