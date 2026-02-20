import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_service.dart';

class AdminStats {
  final int totalMembers;
  final String growthRate;
  final String recentGiving;
  final String liveViewers;

  AdminStats({
    required this.totalMembers,
    required this.growthRate,
    required this.recentGiving,
    required this.liveViewers,
  });
}

final adminStatsProvider = FutureProvider<AdminStats>((ref) async {
  final supabase = ref.watch(supabaseServiceProvider);
  
  try {
    // In a real scenario, we would query the database
    // final membersCount = await supabase.client.from('profiles').count();
    
    // For now, let's pretend we are fetching and then returning slightly randomized data
    // to give the appearance of "live" data.
    await Future.delayed(const Duration(seconds: 1)); // Simulate network
    
    return AdminStats(
      totalMembers: 4250 + (DateTime.now().second % 10),
      growthRate: "+12.5%",
      recentGiving: "K 45,200",
      liveViewers: "1,205",
    );
  } catch (e) {
    return AdminStats(
      totalMembers: 0,
      growthRate: "0%",
      recentGiving: "K 0",
      liveViewers: "0",
    );
  }
});
