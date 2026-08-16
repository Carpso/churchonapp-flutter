import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/core/widgets/coa_payment_sheet.dart';
import '../data/jobs_service.dart';

class JobPromotionSheet extends ConsumerStatefulWidget {
  final String jobId;
  const JobPromotionSheet({super.key, required this.jobId});

  @override
  ConsumerState<JobPromotionSheet> createState() => _JobPromotionSheetState();
}

class _JobPromotionSheetState extends ConsumerState<JobPromotionSheet> {
  bool _isProcessing = false;

  Future<void> _payWithMobileMoney(double amount) async {
    final paymentRef = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CoaPaymentSheet(
        serviceType: 'job_promotion',
        amount: amount,
        serviceLabel: "Job Promotion",
        description: "Pay K${amount.toStringAsFixed(0)} directly to Church On App to feature your job.",
        onComplete: (paymentId, paymentRef) {},
      ),
    );
    if (paymentRef != null && paymentRef.isNotEmpty) {
      await ref.read(jobsServiceProvider).promoteJobWithMobileMoney(
        jobId: widget.jobId,
        amount: amount,
        phone: paymentRef,
      );
      if (mounted) {
        PremiumToast.showSuccess(context, "Job promoted successfully!", title: "Featured");
        Navigator.pop(context);
      }
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.all(25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Promote Your Job", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(LucideIcons.x), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 8),
          Text("Get more applicants by featuring your job at the top of the list.", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 25),

          _buildPackageCard(
            icon: LucideIcons.zap,
            title: "1 Week Featured",
            subtitle: "Boost visibility for 7 days",
            amount: "K50",
            color: Colors.amber,
            onPayWithMobile: () => _payWithMobileMoney(50),
          ),
          const SizedBox(height: 15),
          _buildPackageCard(
            icon: LucideIcons.zap,
            title: "1 Month Featured",
            subtitle: "Boost visibility for 30 days",
            amount: "K150",
            color: Theme.of(context).primaryColor,
            onPayWithMobile: () => _payWithMobileMoney(150),
          ),

          if (_isProcessing) ...[
            const SizedBox(height: 20),
            Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ],

          const SizedBox(height: 20),
          const Center(child: Text("Promoted jobs show at top with a special badge", style: TextStyle(color: Colors.grey, fontSize: 11))),
        ],
      ),
    );
  }

  Widget _buildPackageCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String amount,
    required Color color,
    required VoidCallback onPayWithMobile,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ],
                ),
              ),
              Text(amount, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onPayWithMobile,
              icon: const Icon(LucideIcons.smartphone, size: 16),
              label: const Text("Pay with Mobile Money", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
