import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/config/app_constants.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/church_map.dart';
import 'package:church_on_app/features/admin/data/organization_service.dart';

/// Organisation branch density map — real branches of the bishop's
/// organisation, weighted by actual member count, plotted on the self-hosted
/// Protomaps basemap. Replaces the old single-tenant query that read
/// non-existent `lat`/`lng`/`attendance` columns and therefore rendered nothing.
class BishopHeatmapScreen extends ConsumerStatefulWidget {
  const BishopHeatmapScreen({super.key});

  @override
  ConsumerState<BishopHeatmapScreen> createState() => _BishopHeatmapScreenState();
}

class _BishopHeatmapScreenState extends ConsumerState<BishopHeatmapScreen> {
  final List<Marker> _markers = [];
  final List<CircleMarker> _circles = [];
  LatLng _center = const LatLng(-15.3875, 28.3228);
  bool _isLoading = true;
  bool _empty = false;
  int _plotted = 0;
  int _totalMembers = 0;

  @override
  void initState() {
    super.initState();
    _loadHeatmapData();
  }

  Future<void> _loadHeatmapData() async {
    setState(() => _isLoading = true);
    try {
      final profile = ref.read(profileProvider).value;
      final client = Supabase.instance.client;

      // Central organisation resolution (bishop_id first, then the caller's
      // church link) — the same source of truth as the bishop dashboard.
      final orgs = await ref
          .read(organizationServiceProvider)
          .resolveMyOrganisations(tenantId: profile?.tenantId);
      if (orgs.isEmpty) {
        if (mounted) setState(() { _isLoading = false; _empty = true; });
        return;
      }
      final orgId = orgs.first['id']?.toString();
      if (orgId == null || orgId.isEmpty) {
        if (mounted) setState(() { _isLoading = false; _empty = true; });
        return;
      }

      final counts = await ref.read(organizationServiceProvider).getOrganizationChurchMemberCounts(orgId);
      final memberByChurch = <String, int>{
        for (final c in counts)
          if (c['church_id'] != null) c['church_id'].toString(): (c['member_count'] as num?)?.toInt() ?? 0,
      };

      final branches = await client
          .from('churches')
          .select('id, name, latitude, longitude, is_verified')
          .eq('organization_id', orgId);

      final markers = <Marker>[];
      final circles = <CircleMarker>[];
      var members = 0;
      double? sumLat;
      double? sumLng;
      var plotted = 0;

      for (final b in (branches as List)) {
        final lat = (b['latitude'] as num?)?.toDouble();
        final lng = (b['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        final name = b['name']?.toString() ?? 'Branch';
        final memberCount = memberByChurch[b['id']?.toString()] ?? 0;
        members += memberCount;
        sumLat = (sumLat ?? 0) + lat;
        sumLng = (sumLng ?? 0) + lng;
        plotted++;
        final point = LatLng(lat, lng);

        markers.add(Marker(
          point: point,
          width: 44,
          height: 44,
          child: Tooltip(
            message: '$name\n$memberCount members',
            child: const Icon(Icons.location_on, color: AppConstants.sunflowerYellow, size: 34),
          ),
        ));

        circles.add(CircleMarker(
          point: point,
          radius: (18 + memberCount * 1.6).clamp(24.0, 140.0),
          useRadiusInMeter: true,
          color: AppConstants.sunflowerYellow.withValues(alpha: 0.22),
          borderColor: AppConstants.sunflowerYellow.withValues(alpha: 0.7),
          borderStrokeWidth: 1,
        ));
      }

      if (!mounted) return;
      setState(() {
        _markers
          ..clear()
          ..addAll(markers);
        _circles
          ..clear()
          ..addAll(circles);
        _plotted = plotted;
        _totalMembers = members;
        if (plotted > 0 && sumLat != null && sumLng != null) {
          _center = LatLng(sumLat / plotted, sumLng / plotted);
        }
        _isLoading = false;
        _empty = plotted == 0;
      });
    } catch (e) {
      debugPrint('[bishop_heatmap_screen] Failed to load branches: $e');
      if (mounted) setState(() { _isLoading = false; _empty = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('BRANCH MAP', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _isLoading ? null : _loadHeatmapData),
        ],
      ),
      body: Stack(
        children: [
          ChurchMap(
            center: _center,
            zoom: 6,
            markers: _markers,
            extraLayers: [CircleLayer(circles: _circles)],
            showPlaces: false,
            showSavePin: false,
            showLocateButton: false,
          ),
          if (_isLoading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.activity, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Branch Density', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(
                          _empty
                              ? 'No mapped branches yet'
                              : '$_plotted branches • $_totalMembers members plotted',
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: const Text('LIVE', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          if (_empty && !_isLoading)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10)],
                ),
                child: const Row(children: [
                  Icon(LucideIcons.info, color: Colors.grey, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Branches appear here once their latitude and longitude are set in Church Settings.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
