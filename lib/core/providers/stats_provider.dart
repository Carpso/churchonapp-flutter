import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/features/admin/data/admin_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminStats {
  final int totalMembers;
  final String growthRate;
  final String recentGiving;
  final String liveViewers;
  final int totalMissions;
  final int pendingCargo;
  final int activeCouriers;

  AdminStats({
    required this.totalMembers,
    required this.growthRate,
    required this.recentGiving,
    required this.liveViewers,
    required this.totalMissions,
    required this.pendingCargo,
    required this.activeCouriers,
  });
}

/// REAL data only — no hardcoded fallbacks. Any unavailable metric degrades to
/// an honest 0 / "—" rather than a fake 4,250 members / +12.5% growth.
final adminStatsProvider = FutureProvider<AdminStats>((ref) async {
  final adminService = ref.watch(adminServiceProvider);

  try {
    final tenantId = ref.watch(currentTenantProvider)?.id;
    final profile = ref.watch(profileProvider).value;
    final isCoa = profile != null && (profile.isSuperadmin || profile.role == 'coa_employee' || profile.role == 'employee');
    // COA team sees global Carpso couriers; tenants see their church fleet.
    final members = await adminService.getMembersStream().first;
    final totalMembers = members.length;
    final totalRides = await adminService.getTotalRidesCount();
    final pendingCargo = await adminService.getPendingDeliveriesCount();
    final activeCouriers = await adminService.getActiveCouriersCount(tenantId: isCoa ? null : tenantId);
    final financeMap = await adminService.getMonthlyFinancialStats();

    // Real member growth (this month vs last month) — mirrors pastor dashboard.
    var growthRate = "0%";
    try {
      final client = Supabase.instance.client;
      final now = DateTime.now();
      final firstOfMonth = DateTime(now.year, now.month, 1);
      final firstOfLastMonth = DateTime(now.year, now.month - 1, 1);
      final thisRes = await client
          .from('profiles')
          .select('id')
          .gte('created_at', firstOfMonth.toIso8601String());
      final lastRes = await client
          .from('profiles')
          .select('id')
          .gte('created_at', firstOfLastMonth.toIso8601String())
          .lt('created_at', firstOfMonth.toIso8601String());
      final lastCount = (lastRes as List).length;
      final thisCount = (thisRes as List).length;
      if (lastCount > 0) {
        final g = ((thisCount - lastCount) / lastCount * 100).round();
        growthRate = "${g >= 0 ? '+' : ''}$g%";
      } else if (thisCount > 0) {
        growthRate = "new";
      }
    } catch (_) {}

    // Real live viewers = count of streams currently marked live.
    var liveViewers = "0";
    try {
      final live = await Supabase.instance.client
          .from('live_streams')
          .select('id')
          .eq('status', 'live')
          .limit(100);
      liveViewers = '${(live as List).length}';
    } catch (_) {}

    return AdminStats(
      totalMembers: totalMembers,
      growthRate: growthRate,
      recentGiving: "K ${financeMap['total']?.toInt() ?? 0}",
      liveViewers: liveViewers,
      totalMissions: totalRides,
      pendingCargo: pendingCargo,
      activeCouriers: activeCouriers,
    );
  } catch (e) {
    return AdminStats(
      totalMembers: 0,
      growthRate: "0%",
      recentGiving: "K 0",
      liveViewers: "0",
      totalMissions: 0,
      pendingCargo: 0,
      activeCouriers: 0,
    );
  }
});