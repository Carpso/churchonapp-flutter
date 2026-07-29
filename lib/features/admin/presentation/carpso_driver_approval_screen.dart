import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/core/widgets/app_image.dart';

class CarpsoDriverApprovalScreen extends ConsumerStatefulWidget {
  const CarpsoDriverApprovalScreen({super.key});

  @override
  ConsumerState<CarpsoDriverApprovalScreen> createState() => _CarpsoDriverApprovalScreenState();
}

class _CarpsoDriverApprovalScreenState extends ConsumerState<CarpsoDriverApprovalScreen> {
  List<Map<String, dynamic>> _applications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchApplications();
  }

  Future<void> _fetchApplications() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final data = await supabase
          .from('driver_applications')
          .select('*, profiles!inner(full_name, phone_number)')
          .order('created_at', ascending: false);
      _applications = (data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Failed to fetch driver applications: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _approveDriver(Map<String, dynamic> app) async {
    try {
      final supabase = Supabase.instance.client;
      final userId = app['user_id'] as String?;
      final profile = ref.read(profileProvider).value;

      await supabase.from('ride_registrations').upsert({
        'user_id': userId,
        'type': 'driver',
        'status': 'offline',
        'approved_by': profile?.id ?? supabase.auth.currentUser?.id,
        'vehicle_info': app['vehicle_make_model'] ?? '',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      await supabase.from('driver_applications').update({'status': 'approved'}).eq('id', app['id']);

      await supabase.from('notifications').insert({
        'user_id': userId,
        'title': 'Carpso Ride Application Approved',
        'body': 'Congratulations! Your driver application has been approved. You can now go online and start accepting rides.',
        'type': 'driver_approval',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        PremiumToast.showSuccess(context, 'Driver approved successfully');
        _fetchApplications();
      }
    } catch (e) {
      debugPrint('Failed to approve driver: $e');
      if (mounted) PremiumToast.showError(context, 'Failed to approve driver');
    }
  }

  Future<void> _rejectDriver(Map<String, dynamic> app) async {
    try {
      await Supabase.instance.client
          .from('driver_applications')
          .update({'status': 'rejected'})
          .eq('id', app['id']);

      if (mounted) {
        PremiumToast.showSuccess(context, 'Driver application rejected');
        _fetchApplications();
      }
    } catch (e) {
      debugPrint('Failed to reject driver: $e');
      if (mounted) PremiumToast.showError(context, 'Failed to reject driver');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Carpso Driver Applications", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: ListSkeleton())
          : _applications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.car, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 20),
                      Text("No pending driver applications", style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchApplications,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _applications.length,
                    itemBuilder: (context, index) {
                      final app = _applications[index];
                      final status = app['status'] as String? ?? 'pending';
                      final profile = app['profiles'] as Map<String, dynamic>?;
                      final name = profile?['full_name'] ?? app['full_name'] ?? 'Unknown';
                      final phone = profile?['phone_number'] ?? app['phone'] ?? '';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                                    child: Icon(LucideIcons.user, color: theme.primaryColor),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                        if (phone.isNotEmpty)
                                          Text(phone, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: status == 'approved'
                                          ? Colors.green.shade50
                                          : status == 'rejected'
                                              ? Colors.red.shade50
                                              : Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: TextStyle(
                                        color: status == 'approved'
                                            ? Colors.green
                                            : status == 'rejected'
                                                ? Colors.red
                                                : Colors.orange,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (app['vehicle_type'] != null && app['vehicle_type'].toString().isNotEmpty)
                                _infoRow(LucideIcons.truck, 'Vehicle Type', app['vehicle_type']),
                              if (app['vehicle_make_model'] != null && app['vehicle_make_model'].toString().isNotEmpty)
                                _infoRow(LucideIcons.settings, 'Make/Model', app['vehicle_make_model']),
                              if (app['license_plate'] != null && app['license_plate'].toString().isNotEmpty)
                                _infoRow(LucideIcons.hash, 'License Plate', app['license_plate']),
                              if (app['vehicle_color'] != null && app['vehicle_color'].toString().isNotEmpty)
                                _infoRow(LucideIcons.palette, 'Color', app['vehicle_color']),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (app['vehicle_photo_url'] != null)
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => _showImage(context, app['vehicle_photo_url'], 'Vehicle Photo'),
                                        child: AppImage(app['vehicle_photo_url'], height: 80, fit: BoxFit.cover, borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  if (app['vehicle_photo_url'] != null && app['drivers_license_url'] != null)
                                    const SizedBox(width: 8),
                                  if (app['drivers_license_url'] != null)
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => _showImage(context, app['drivers_license_url'], "Driver's License"),
                                        child: AppImage(app['drivers_license_url'], height: 80, fit: BoxFit.cover, borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                ],
                              ),
                              if (status == 'pending') ...[
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _approveDriver(app),
                                        icon: const Icon(LucideIcons.check, size: 16),
                                        label: const Text("APPROVE"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _rejectDriver(app),
                                        icon: const Icon(LucideIcons.x, size: 16),
                                        label: const Text("REJECT"),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          side: const BorderSide(color: Colors.red),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Text("$label: ", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showImage(BuildContext context, String url, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: AppImage(url),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CLOSE")),
        ],
      ),
    );
  }
}
