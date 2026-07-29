import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/admin/presentation/admin_hub_screen.dart';
import 'package:church_on_app/features/admin/presentation/global_broadcast_screen.dart';
import 'package:church_on_app/features/admin/presentation/member_management_screen.dart';
import 'package:church_on_app/features/admin/presentation/event_scheduler_screen.dart';

class HomeAdminDashboard extends ConsumerWidget {
  const HomeAdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    if (profile == null || !profile.isAdminOrHigher) return const SizedBox.shrink();

    final chips = [
      ("Dashboard", LucideIcons.layoutDashboard, Colors.indigo, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminHubScreen()))),
      ("Broadcast", LucideIcons.megaphone, Colors.purple, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GlobalBroadcastScreen()))),
      ("Members", LucideIcons.users, Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemberManagementScreen()))),
      ("Events", LucideIcons.calendarDays, Colors.red, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EventSchedulerScreen()))),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, "Admin Tools"),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final (label, icon, color, onTap) = chips[index];
              return ActionChip(
                onPressed: onTap,
                backgroundColor: color.withValues(alpha: 0.1),
                side: BorderSide(color: color.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 6),
                    Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15.0),
      child: Row(
        children: [
          Container(width: 4, height: 18, decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
