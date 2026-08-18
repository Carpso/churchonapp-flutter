import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/church_map.dart';

/// Member Live Heatmap — real member locations from profiles.lat/lng where
/// last_seen is within the last 10 minutes (tenant-scoped for church admins,
/// platform-wide for superadmins/COA).
class LiveViewerHeatmapScreen extends ConsumerStatefulWidget {
  const LiveViewerHeatmapScreen({super.key});

  @override
  ConsumerState<LiveViewerHeatmapScreen> createState() => _LiveViewerHeatmapScreenState();
}

class _LiveViewerHeatmapScreenState extends ConsumerState<LiveViewerHeatmapScreen> {
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;
  String? _error;
  DateTime _lastUpdated = DateTime.now();
  Timer? _timer;
  String _scopedFor = '';

  static const _liveWindowMinutes = 10;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _loadMembers());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profile = ref.watch(profileProvider).value;
    final key = profile == null ? '' : '${profile.role}|${profile.tenantId}';
    if (key != _scopedFor) {
      _scopedFor = key;
      _loadMembers();
    }
  }

  bool _isGlobal(UserProfile? profile) =>
      profile?.role == 'superadmin' || profile?.role == 'coa_employee';

  Future<void> _loadMembers() async {
    try {
      final client = Supabase.instance.client;
      final profile = ref.read(profileProvider).value;
      final cutoff = DateTime.now().subtract(const Duration(minutes: _liveWindowMinutes)).toIso8601String();

      dynamic query = client
          .from('profiles')
          .select('id, full_name, lat, lng, last_seen')
          .not('lat', 'is', null)
          .not('lng', 'is', null)
          .gte('last_seen', cutoff)
          .limit(500);
      if (!_isGlobal(profile)) {
        final tenantId = profile?.tenantId;
        if (tenantId != null && tenantId.isNotEmpty) {
          query = query.eq('tenant_id', tenantId);
        }
      }
      final res = await query;
      _members = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Live heatmap load failed: $e');
      _error = e.toString();
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
        _lastUpdated = DateTime.now();
      });
    }
  }

  String get _lastUpdatedLabel {
    final diff = DateTime.now().difference(_lastUpdated);
    return "Updated ${diff.inSeconds}s ago";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Member Live Heatmap", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            onPressed: _loadMembers,
          )
        ],
      ),
      body: _isLoading && _members.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ChurchMap(
                  markers: _members.map((m) {
                    final lat = (m['lat'] as num?)?.toDouble() ?? 0.0;
                    final lng = (m['lng'] as num?)?.toDouble() ?? 0.0;
                    final name = m['full_name']?.toString() ?? 'Member';
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () => _showMemberSheet(name),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red.withAlpha(51),
                            border: Border.all(color: Colors.red.withAlpha(127), width: 2),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                Positioned(
                  bottom: 30,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(204),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.activity, color: Colors.green, size: 20),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "${_members.length} members live now",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                _members.isEmpty
                                    ? "No members shared location in the last $_liveWindowMinutes minutes"
                                    : "Last $_liveWindowMinutes minutes • $_lastUpdatedLabel",
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: Colors.black.withAlpha(25), blurRadius: 10)],
                    ),
                    child: const Row(
                      children: [
                        CircleAvatar(radius: 4, backgroundColor: Colors.red),
                        SizedBox(width: 8),
                        Text("LIVE HEAT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Positioned(
                    top: 70,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "Error: $_error",
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  void _showMemberSheet(String name) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.red.withAlpha(30),
              child: const Icon(LucideIcons.user, color: Colors.red, size: 28),
            ),
            const SizedBox(height: 12),
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            const Text("Active in the last 10 minutes", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}