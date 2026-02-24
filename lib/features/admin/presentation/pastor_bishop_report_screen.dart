import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/admin/data/reporting_service.dart';
import 'package:church_on_app/features/admin/data/organization_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PastorBishopReportScreen extends ConsumerStatefulWidget {
  const PastorBishopReportScreen({super.key});

  @override
  ConsumerState<PastorBishopReportScreen> createState() => _PastorBishopReportScreenState();
}

class _PastorBishopReportScreenState extends ConsumerState<PastorBishopReportScreen> {
  final _contentCtrl = TextEditingController();
  bool _isSyncing = false;
  Map<String, dynamic> _syncedStats = {'attendance': 0, 'offering': 0.0, 'services': 0};

  @override
  void initState() {
    super.initState();
    _syncData();
  }

  Future<void> _syncData() async {
    setState(() => _isSyncing = true);
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) return;

    try {
      final res = await Supabase.instance.client
          .from('service_reports')
          .select('attendance, offering')
          .eq('tenant_id', tenant.id)
          .eq('type', 'service')
          .gte('created_at', DateTime.now().subtract(const Duration(days: 30)).toIso8601String());

      int totalAttendance = 0;
      double totalOffering = 0.0;
      for (var item in res) {
        totalAttendance += (item['attendance'] as num?)?.toInt() ?? 0;
        totalOffering += (item['offering'] as num?)?.toDouble() ?? 0.0;
      }

      setState(() {
        _syncedStats = {
          'attendance': totalAttendance,
          'offering': totalOffering,
          'services': res.length,
        };
        _isSyncing = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _handleSubmit() async {
    final profile = ref.read(profileProvider).value;
    final tenant = ref.read(currentTenantProvider);
    if (profile == null || tenant == null) return;

    final orgId = tenant.settings?['organization_id'] ?? 'default_org';

    try {
      await ref.read(organizationServiceProvider).submitPastorReport(
        pastorId: profile.id,
        orgId: orgId,
        content: _contentCtrl.text,
        stats: _syncedStats,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Report submitted to Bishop's Office"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Submission failed: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("Submit Report to Bishop", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSyncStatusCard(),
            const SizedBox(height: 30),
            const Text("Pastoral Remarks", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: _contentCtrl,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: "State any challenges, testimonies, or personal field reports to the Bishop...",
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _handleSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text("SUBMIT TO SECRETARY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF1E293B)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Automatic Sync (Last 30 Days)", style: TextStyle(color: Colors.white70, fontSize: 12)),
              if (_isSyncing) 
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              else
                const Icon(LucideIcons.checkCircle2, color: Colors.green, size: 14),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat("Services", _syncedStats['services'].toString()),
              _buildStat("Avg Attendance", _syncedStats['attendance'].toString()),
              _buildStat("Tithe/Offering", "K ${_syncedStats['offering'].toStringAsFixed(0)}"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String val) {
    return Column(
      children: [
        Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
  }
}
