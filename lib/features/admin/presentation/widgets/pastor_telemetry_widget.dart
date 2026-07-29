import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class PastorTelemetryWidget extends StatelessWidget {
  final double totalTithes;
  final double totalOfferings;
  final double totalPledges;
  final int activeMembersCount;
  final int averageAttendance;

  const PastorTelemetryWidget({
    super.key,
    required this.totalTithes,
    required this.totalOfferings,
    required this.totalPledges,
    required this.activeMembersCount,
    required this.averageAttendance,
  });

  double get totalIncome => totalTithes + totalOfferings + totalPledges;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grandTotal = totalIncome > 0 ? totalIncome : 1.0;

    final tithePercent = (totalTithes / grandTotal).clamp(0.0, 1.0);
    final offeringPercent = (totalOfferings / grandTotal).clamp(0.0, 1.0);
    final pledgePercent = (totalPledges / grandTotal).clamp(0.0, 1.0);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.barChart2, color: theme.primaryColor, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      "Ministry Telemetry",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "Realtime",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),

            // Revenue Distribution Bar
            Text(
              "Financial Breakdown",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    Expanded(
                      flex: (tithePercent * 100).round(),
                      child: Container(color: const Color(0xFF10B981)), // Emerald Green
                    ),
                    Expanded(
                      flex: (offeringPercent * 100).round(),
                      child: Container(color: const Color(0xFF3B82F6)), // Blue
                    ),
                    Expanded(
                      flex: (pledgePercent * 100).round(),
                      child: Container(color: const Color(0xFFF59E0B)), // Amber
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Legend Tiers
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildLegendItem("Tithes", "K${totalTithes.toStringAsFixed(0)}", const Color(0xFF10B981)),
                _buildLegendItem("Offerings", "K${totalOfferings.toStringAsFixed(0)}", const Color(0xFF3B82F6)),
                _buildLegendItem("Pledges", "K${totalPledges.toStringAsFixed(0)}", const Color(0xFFF59E0B)),
              ],
            ),
            const Divider(height: 30),

            // Attendance & Growth Telemetry
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    label: "Active Members",
                    value: activeMembersCount.toString(),
                    icon: LucideIcons.users,
                    color: const Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildMetricTile(
                    label: "Avg. Attendance",
                    value: averageAttendance.toString(),
                    icon: LucideIcons.userCheck,
                    color: const Color(0xFF8B5CF6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, String amount, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(amount, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
