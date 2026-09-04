import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../profile/data/notification_service.dart';
import '../../../core/providers/profile_provider.dart';
import '../../modules/logistics/presentation/weather_maps_screen.dart';

class ChurchCommuteScreen extends ConsumerStatefulWidget {
  const ChurchCommuteScreen({super.key});

  @override
  ConsumerState<ChurchCommuteScreen> createState() => _ChurchCommuteScreenState();
}

class _ChurchCommuteScreenState extends ConsumerState<ChurchCommuteScreen> {
  final _client = Supabase.instance.client;
  bool _requesting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("Church Commute", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _buildStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final profile = ref.watch(profileProvider).value;
            final allUsers = snapshot.data ?? [];
            final drivers = allUsers.where((u) {
              if (u['role'] != 'driver' && u['role'] != 'rider') return false;
              if (profile?.tenantId != null && u['tenant_id'] != profile!.tenantId) return false;
              return true;
            }).toList();
            if (drivers.isEmpty) {
              return _buildEmptyState();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildQuickActionCard(
                          icon: LucideIcons.bus,
                          label: "Live Bus Tracking",
                          color: Colors.orange,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WeatherMapsScreen())),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickActionCard(
                          icon: LucideIcons.car,
                          label: "Book Carpso Ride",
                          color: const Color(0xFFE8C547),
                          onTap: () => context.push('/ride'),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: drivers.length,
                    itemBuilder: (context, index) {
                      final driver = drivers[index];
                      return _buildDriverCard(driver);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Stream<List<Map<String, dynamic>>> _buildStream() {
    // NOTE: Supabase streams support only ONE eq() filter. Tenant + role
    // filtering happens client-side (see driver list filtering below).
    // Only actual drivers/riders with driver_status='online' count as active
    // couriers — NOT profiles who toggled the generic "privacy mode"
    // (is_work_mode) which was incorrectly leaking non-driver users here.
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('driver_status', 'online');
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.car, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text("No active drivers found", style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          const Text("Try again closer to service time.", style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: () => setState(() {}),
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text("Refresh"),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(25),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Assisted Travel", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("Connect with church-verified drivers and riders for a safe commute to service.", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.grey, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverCard(Map<String, dynamic> driver) {
    final isDriver = driver['role'] == 'driver';
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFFFFDA03).withValues(alpha: 0.1),
            child: Icon(isDriver ? LucideIcons.car : LucideIcons.bike, color: const Color(0xFFFFDA03)),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driver['full_name'] ?? "Brother in Christ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Row(
                  children: [
                    const Icon(LucideIcons.shield, color: Colors.green, size: 12),
                    const SizedBox(width: 4),
                    const Text("Church Verified", style: TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _requesting ? null : () => _handleRequest(driver),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFDA03),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _requesting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text("REQUEST", style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRequest(Map<String, dynamic> driver) async {
    setState(() => _requesting = true);
    try {
      final userProfile = ref.read(profileProvider).value;
      final userName = userProfile?.name ?? "A member";
      await ref.read(profileNotificationServiceProvider).sendNotification(
        userId: driver['id'],
        title: "Commute Request",
        body: "$userName is requesting a ride to church!",
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Request sent to ${driver['full_name'] ?? 'driver'}!"), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send request: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }
}

