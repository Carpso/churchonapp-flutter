import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

class BishopDashboard extends ConsumerWidget {
  const BishopDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text("Apostolic Oversight", style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Global Metrics", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 15),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 15,
              crossAxisSpacing: 15,
              childAspectRatio: 1.2,
              children: [
                _buildMetricCard(context, "Total Parishes", "42", LucideIcons.map),
                _buildMetricCard(context, "Global Attendance", "12.5k", LucideIcons.users),
                _buildMetricCard(context, "Total Salvations", "840", LucideIcons.heartPulse),
                _buildMetricCard(context, "Global Tithes", "K 1.2M", LucideIcons.wallet),
              ],
            ),
            const SizedBox(height: 40),
            Text("Branch Performance", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 15),
            _buildBranchRow(context, theme, "HQ - Strategic Lane", "+15%", Colors.green),
            _buildBranchRow(context, theme, "North Campus", "+8%", Colors.green),
            _buildBranchRow(context, theme, "East Campus", "-2%", Colors.red),
            _buildBranchRow(context, theme, "South Parish", "+5%", Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(BuildContext context, String title, String value, IconData icon) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: theme.primaryColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: theme.colorScheme.onSecondary, size: 28),
          const Spacer(),
          Text(value, style: TextStyle(color: theme.colorScheme.onSecondary, fontSize: 24, fontWeight: FontWeight.w900)),
          Text(title, style: TextStyle(color: theme.colorScheme.onSecondary.withValues(alpha: 0.7), fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildBranchRow(BuildContext context, ThemeData theme, String branchName, String growth, Color growthColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(branchName, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: growthColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(growth, style: TextStyle(color: growthColor, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
