import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:church_on_app/core/widgets/church_map.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/plan_service.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  // Zambia focus only — Zimbabwe is an expansion market, not shown here yet.
  final LatLng _lusaka = const LatLng(-15.3875, 28.3228);

  LatLng _center = const LatLng(-15.3875, 28.3228);
  LatLng? _userPosition;
  List<Tenant> _churches = [];
  bool _isLoading = true;
  String? _activePlanFilter;

  static const _filters = [
    (label: "All Branches", icon: LucideIcons.church, color: Colors.amber),
    (label: "Silver", icon: LucideIcons.wallet, color: Colors.grey),
    (label: "Gold", icon: LucideIcons.award, color: Colors.orange),
    (label: "Platinum", icon: LucideIcons.crown, color: Colors.purple),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
    });
    _fetchUserPosition();
    final churches =
        await ref.read(tenantServiceProvider).getNearbyChurches(
              _center.latitude,
              _center.longitude,
            );
    if (mounted) {
      setState(() {
        // Zimbabwe seed branches (zw_*) are not part of the Zambian map yet.
        _churches = churches.where((c) => !c.id.startsWith('zw_')).toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchUserPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition();
        if (mounted) {
          setState(() => _userPosition = LatLng(pos.latitude, pos.longitude));
        }
      }
    } catch (e) {
      debugPrint('MapScreen: location fetch failed: $e');
    }
  }

  void _switchRegion() {
    setState(() => _center = _lusaka);
    _load();
  }

  void _setFilter(String? label) {
    setState(() => _activePlanFilter = label);
  }

  List<Tenant> get _visibleChurches {
    final filtered = _churches.where((c) {
      switch (_activePlanFilter) {
        case 'Silver':
          return c.plan == TenantPlan.silver;
        case 'Gold':
          return c.plan == TenantPlan.gold;
        case 'Platinum':
          return c.plan == TenantPlan.platinum;
        default:
          return true;
      }
    }).toList();
    return filtered;
  }

  void _showChurchInfo(Tenant church) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: church.primaryColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.church,
                      color: church.primaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      church.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _infoRow(
                LucideIcons.gem,
                "Plan",
                church.limits.label,
                church.plan == TenantPlan.platinum
                    ? 'Platinum priority'
                    : '${church.limits.maxMembers} member cap',
              ),
              const SizedBox(height: 10),
              _infoRow(
                LucideIcons.mapPin,
                "Location",
                church.latitude != null && church.longitude != null
                    ? '${church.latitude!.toStringAsFixed(4)}, ${church.longitude!.toStringAsFixed(4)}'
                    : 'Not set',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: church.latitude == null || church.longitude == null
                      ? null
                      : () async {
                          final url = Uri.parse(
                            'https://www.google.com/maps/search/?api=1&query='
                            '${church.latitude!},${church.longitude!}',
                          );
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: church.primaryColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(LucideIcons.navigation),
                  label: const Text(
                    "GET DIRECTIONS",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value,
      [String? sublabel]) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sublabel == null ? value : '$value  •  $sublabel',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleChurches;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Expansion Map", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _load),
        ],
      ),
      body: Stack(
        children: [
          ChurchMap(
            center: _center,
            zoom: 7, // Zambia country view
            markers: [
              if (_userPosition != null)
                buildUserMarker(point: _userPosition!),
              ...visible.map((church) => buildChurchMarker(
                point: LatLng(church.latitude ?? 0, church.longitude ?? 0),
                name: church.name,
                color: church.primaryColor,
                logoUrl: church.logoUrl,
                onTap: () => _showChurchInfo(church),
              )),
            ],
          ),

          // Map Overlay Controls
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: mapFilterBadge(
                        f.label,
                        f.icon,
                        f.color,
                        _activePlanFilter == f.label,
                        onTap: () => _setFilter(f.label),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Region Switcher (Zambia only for now)
          Positioned(
            bottom: 40,
            left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                regionButton("ZAMBIA", _lusaka),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${visible.length} branch${visible.length == 1 ? '' : 'es'}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.amber)),
        ],
      ),
    );
  }

  Widget mapFilterBadge(String label, IconData icon, Color color,
      bool isActive, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? color : Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: isActive ? Colors.white : color, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget regionButton(String label, LatLng center) {
    final isSelected = _center.latitude == center.latitude;
    return GestureDetector(
      onTap: () => _switchRegion(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}