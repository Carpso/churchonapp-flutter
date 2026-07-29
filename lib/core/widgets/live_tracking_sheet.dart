import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';

class LiveTrackingStep {
  final String title;
  final String description;
  final bool isCompleted;
  final bool isCurrent;

  const LiveTrackingStep({
    required this.title,
    required this.description,
    required this.isCompleted,
    required this.isCurrent,
  });
}

class LiveTrackingSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final String statusText;
  final Color statusColor;
  final String? driverName;
  final String? driverPhone;
  final String? vehicleInfo;
  final String? etaText;
  final List<LiveTrackingStep> steps;
  final VoidCallback? onRefresh;

  const LiveTrackingSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.statusText,
    required this.statusColor,
    this.driverName,
    this.driverPhone,
    this.vehicleInfo,
    this.etaText,
    required this.steps,
    this.onRefresh,
  });

  static void show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String statusText,
    required Color statusColor,
    String? driverName,
    String? driverPhone,
    String? vehicleInfo,
    String? etaText,
    required List<LiveTrackingStep> steps,
    VoidCallback? onRefresh,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LiveTrackingSheet(
        title: title,
        subtitle: subtitle,
        statusText: statusText,
        statusColor: statusColor,
        driverName: driverName,
        driverPhone: driverPhone,
        vehicleInfo: vehicleInfo,
        etaText: etaText,
        steps: steps,
        onRefresh: onRefresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusText.toUpperCase(),
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          if (etaText != null && etaText!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.clock, color: Color(0xFF2563EB), size: 20),
                  const SizedBox(width: 12),
                  Text("Estimated Arrival: ", style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                  Text(etaText!, style: const TextStyle(color: Color(0xFF1D4ED8), fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          const Text("Live Timeline & Progress", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
          const SizedBox(height: 12),
          ...steps.asMap().entries.map((entry) {
            final idx = entry.key;
            final step = entry.value;
            final isLast = idx == steps.length - 1;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: step.isCompleted
                            ? Colors.green
                            : step.isCurrent
                                ? Colors.amber.shade700
                                : Colors.grey.shade300,
                      ),
                      child: Icon(
                        step.isCompleted ? LucideIcons.check : LucideIcons.circle,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                    if (!isLast)
                      Container(
                        width: 2,
                        height: 32,
                        color: step.isCompleted ? Colors.green : Colors.grey.shade300,
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: TextStyle(
                            fontWeight: step.isCurrent || step.isCompleted ? FontWeight.bold : FontWeight.normal,
                            color: step.isCurrent || step.isCompleted ? Colors.black87 : Colors.grey.shade500,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          step.description,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
          if (driverName != null && driverName!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.amber.shade700,
                    child: const Icon(LucideIcons.user, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(driverName!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        if (vehicleInfo != null && vehicleInfo!.isNotEmpty)
                          Text(vehicleInfo!, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (driverPhone != null && driverPhone!.isNotEmpty)
                    IconButton(
                      icon: const Icon(LucideIcons.phoneCall, color: Colors.green),
                      onPressed: () async {
                        final uri = Uri.parse("tel:${driverPhone!.replaceAll(RegExp(r'\D'), '')}");
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        } else if (context.mounted) {
                          PremiumToast.showInfo(context, "Call: ${driverPhone!}");
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (onRefresh != null) onRefresh!();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text("CLOSE TRACKER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
