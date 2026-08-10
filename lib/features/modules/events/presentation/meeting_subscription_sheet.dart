import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/widgets/coa_payment_sheet.dart';

class MeetingSubscriptionSheet extends ConsumerStatefulWidget {
  final Future<bool> Function(String planType, double amountZmw, String? paymentRef) onSubscribe;
  const MeetingSubscriptionSheet({super.key, required this.onSubscribe});

  @override
  ConsumerState<MeetingSubscriptionSheet> createState() => _MeetingSubscriptionSheetState();
}

class _MeetingSubscriptionSheetState extends ConsumerState<MeetingSubscriptionSheet> {
  String _selectedPlan = 'monthly';
  bool _isProcessing = false;

  double get _amount => _selectedPlan == 'yearly' ? 1500.0 : 150.0;
  String get _planLabel => _selectedPlan == 'yearly' ? 'Yearly' : 'Monthly';

  Future<void> _payWithMobileMoney() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CoaPaymentSheet(
        serviceType: 'meeting_subscription',
        amount: _amount,
        serviceLabel: "Pro Meeting Suite - $_planLabel",
        description: "Pay K${_amount.toStringAsFixed(0)} directly to Church On App to activate your $_planLabel subscription.",
        onComplete: (paymentId, paymentRef) async {
          Navigator.pop(ctx);
          setState(() => _isProcessing = true);
          final ok = await widget.onSubscribe(_selectedPlan, _amount, paymentRef);
          setState(() => _isProcessing = false);
          if (ok && mounted) {
            Navigator.pop(context);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.all(25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Pro Meeting Suite", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(LucideIcons.x, color: Colors.white54), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 8),
          Text("Unlock encrypted video meetings, live minutes, voting & more.", style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
          const SizedBox(height: 25),

          Row(
            children: [
              Expanded(child: _buildPlanCard("monthly", "Monthly", "K150", "K150/month", "Billed monthly")),
              const SizedBox(width: 12),
              Expanded(child: _buildPlanCard("yearly", "Yearly", "K1,500", "K125/month", "Save 17%")),
            ],
          ),

          const SizedBox(height: 25),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Premium Features", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                _featureRow(LucideIcons.video, "Encrypted HD Video Calls"),
                _featureRow(LucideIcons.messageSquare, "Live Meeting Minutes & Notes"),
                _featureRow(LucideIcons.barChart3, "Real-time Voting & Polls"),
                _featureRow(LucideIcons.users, "Up to 10 Participants"),
                _featureRow(LucideIcons.fileText, "Meeting Records & History"),
              ],
            ),
          ),

          const SizedBox(height: 25),
          if (_isProcessing)
            const Center(child: CircularProgressIndicator(color: Colors.amber))
          else
            ElevatedButton.icon(
              onPressed: _payWithMobileMoney,
              icon: const Icon(LucideIcons.smartphone, color: Colors.black),
              label: Text("Pay K${_amount.toStringAsFixed(0)} with Mobile Money", style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPlanCard(String type, String label, String price, String subtitle, String badge) {
    final selected = _selectedPlan == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? Colors.amber.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.amber : Colors.white12, width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? Colors.amber : Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(badge, style: TextStyle(color: selected ? Colors.black : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            Text(price, style: TextStyle(color: selected ? Colors.amber : Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: selected ? Colors.amber : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber, size: 16),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
        ],
      ),
    );
  }
}
