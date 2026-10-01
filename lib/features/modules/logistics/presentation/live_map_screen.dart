import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/services/nearby_places_service.dart';
import '../../../../core/services/tenant_service.dart';
import '../../../../core/widgets/church_map.dart';
import '../data/map_live_models.dart';
import '../data/map_live_service.dart';

/// The one live map: buses, traffic, parking, quick routes and nearby places on
/// the same self-hosted basemap every other screen uses.
///
/// Honesty rules honoured here:
///   * an empty layer says WHY it is empty — no invented buses or traffic;
///   * traffic is labelled crowd-sourced, and "no data" is never "clear";
///   * a bus with no recent ping is OFFLINE, not drawn as if it were moving.
class LiveMapScreen extends ConsumerStatefulWidget {
  const LiveMapScreen({super.key, this.initialCenter});

  final LatLng? initialCenter;

  @override
  ConsumerState<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends ConsumerState<LiveMapScreen> {
  static const _kabulonga = LatLng(-15.3875, 28.3228);

  static const _layers = <String, ({String label, IconData icon})>{
    'buses': (label: 'Buses', icon: LucideIcons.bus),
    'traffic': (label: 'Traffic', icon: LucideIcons.car),
    'parking': (label: 'Parking', icon: LucideIcons.parkingCircle),
    'nearby': (label: 'Nearby', icon: LucideIcons.store),
  };

  final Set<String> _on = {'buses', 'traffic', 'parking'};
  double? _userLat;
  double? _userLng;

  String get _tenantId => ref.read(currentTenantProvider)?.id ?? '';

  Future<void> _ensureUserLocation() async {
    if (_userLat != null) return;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    );
    if (!mounted) return;
    setState(() {
      _userLat = p.latitude;
      _userLng = p.longitude;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tenantId = _tenantId;
    final center = widget.initialCenter ?? _kabulonga;

    // Only the bus layer is needed up here (it marks the map); the rest of the
    // data is read inside the bottom sheet's tabs, so nothing is fetched twice.
    ref.watch(liveBusesProvider(tenantId));
    final hasFix = _userLat != null && _userLng != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Live Map',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () {
              ref.invalidate(liveBusesProvider(tenantId));
              ref.invalidate(parkingProvider(tenantId));
              ref.invalidate(incidentsProvider(tenantId));
              ref.invalidate(quickRoutesProvider(tenantId));
              if (hasFix) {
                ref.invalidate(trafficSegmentsProvider(
                    LatLng(_userLat!, _userLng!)));
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ChurchMap(
              center: center,
              zoom: 13,
              // The map already draws the crowd-sourced traffic discs itself
              // when showTraffic is on, so we do not inject our own layer.
              showTraffic: _on.contains('traffic'),
              showNearby: _on.contains('nearby'),
              showPlaces: _on.contains('parking'),
              showAddressSearch: true,
              showSavePin: false,
              showOfflineButton: false,
              showLocateButton: true,
              topInset: 56,
            ),
          ),

          // Layer toggles
          Positioned(
            left: 12,
            top: 12,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in _layers.entries)
                  _layerChip(context, e.key, e.value.label, e.value.icon),
              ],
            ),
          ),

          // Permission / location prompt for the location-driven layers.
          if (!hasFix && (_on.contains('traffic') || _on.contains('nearby')))
            Positioned(
              left: 12,
              right: 12,
              top: 62,
              child: _needLocationCard(context),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _bottomSheet(context, theme, center),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'live_map_report',
        onPressed: () => _openReportSheet(context, tenantId),
        icon: const Icon(LucideIcons.plus),
        label: const Text('REPORT'),
      ),
    );
  }

  Widget _needLocationCard(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(LucideIcons.mapPin, size: 16, color: Colors.blueGrey),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Turn on location to see traffic and places around you.',
                style: TextStyle(fontSize: 11, height: 1.3),
              ),
            ),
            FilledButton(
              onPressed: _ensureUserLocation,
              style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: const Text('ENABLE', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _layerChip(
      BuildContext context, String key, String label, IconData icon) {
    final active = _on.contains(key);
    final theme = Theme.of(context);
    return Material(
      color: active ? theme.primaryColor : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() {
          if (active) {
            _on.remove(key);
          } else {
            _on.add(key);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: active ? Colors.white : theme.colorScheme.onSurface),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: active ? Colors.white : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomSheet(BuildContext context, ThemeData theme, LatLng center) {
    final tenantId = _tenantId;
    final busesAsync = ref.watch(liveBusesProvider(tenantId));
    final parkingAsync = ref.watch(parkingProvider(tenantId));
    final routesAsync = ref.watch(quickRoutesProvider(tenantId));
    final hasFix = _userLat != null;
    final trafficAsync = hasFix
        ? ref.watch(trafficSegmentsProvider(LatLng(_userLat!, _userLng!)))
        : AsyncValue<List<MapTrafficSegment>>.data(const []);
    final nearbyAsync = hasFix
        ? ref.watch(nearbyPlacesProvider((
            lat: _userLat!,
            lng: _userLng!,
            radiusMeters: 2000.0,
            category: null,
          )))
        : AsyncValue<List<NearbyPlace>>.data(const []);

    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      color: theme.colorScheme.surface,
      child: DefaultTabController(
        length: 5,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              tabs: [
                const Tab(text: 'Buses'),
                Tab(text: 'Traffic'),
                const Tab(text: 'Parking'),
                const Tab(text: 'Nearby'),
                const Tab(text: 'Routes'),
              ],
            ),
            SizedBox(
              height: 210,
              child: TabBarView(
                children: [
                  _busesTab(theme, busesAsync.value, busesAsync.isLoading),
                  _trafficTab(theme, trafficAsync.value, trafficAsync.isLoading,
                      hasFix),
                  _parkingTab(theme, parkingAsync.value, parkingAsync.isLoading),
                  _nearbyTab(theme, nearbyAsync.value, nearbyAsync.isLoading,
                      hasFix),
                  _routesTab(theme, routesAsync.value, routesAsync.isLoading),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ── Buses ────────────────────────────────────────────────────────────────
  Widget _busesTab(ThemeData theme, List<LiveBus>? buses, bool loading) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final list = buses ?? const <LiveBus>[];
    if (list.isEmpty) {
      return _empty(
        theme,
        LucideIcons.bus,
        'No buses registered',
        'Add buses from Admin ▸ Church Fleet, then they appear here with live positions.',
      );
    }
    final live = list.where((b) => b.hasLiveFix).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('$live of ${list.length} reporting a live position',
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
        ),
        for (final b in list)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              b.hasLiveFix ? LucideIcons.bus : LucideIcons.bus,
              color: b.hasLiveFix ? Colors.green : Colors.grey,
              size: 20,
            ),
            title: Text(b.name,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text(
              [
                if (b.route != null && b.route!.isNotEmpty) b.route!,
                if (b.speedKmh != null) '${b.speedKmh!.toStringAsFixed(0)} km/h',
                b.statusLabel,
              ].join(' · '),
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
            trailing: b.recordedAt == null
                ? null
                : Text(
                    DateFormat.Hm().format(b.recordedAt!.toLocal()),
                    style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
                  ),
          ),
      ],
    );
  }

  // ── Traffic ──────────────────────────────────────────────────────────────
  Widget _trafficTab(ThemeData theme, List<MapTrafficSegment>? segs, bool loading,
      bool hasFix) {
    if (!hasFix) {
      return _empty(
        theme,
        LucideIcons.mapPin,
        'Location needed',
        'Traffic is read for the area around you. Enable location above.',
      );
    }
    if (loading) return const Center(child: CircularProgressIndicator());
    final list = segs ?? const <MapTrafficSegment>[];
    final known = list.where((s) => !s.isUnknown).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      children: [
        Text(MapLiveService.trafficSourceNote,
            style: const TextStyle(fontSize: 10, color: Colors.blueGrey, height: 1.3)),
        const SizedBox(height: 10),
        if (list.isEmpty)
          _empty(
            theme,
            LucideIcons.car,
            'No recent road data',
            'Nobody has driven here in the last 30 minutes, so we show nothing rather than guessing. Colour the roads in as drivers report.',
          )
        else ...[
          if (known.isNotEmpty)
            for (final s in known)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_trafficIcon(s.condition),
                    color: _trafficColor(s.condition), size: 18),
                title: Text(_trafficLabel(s.condition),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(
                    'avg ${s.avgSpeed.toStringAsFixed(0)} km/h from ${s.samples} reports',
                    style: const TextStyle(fontSize: 11)),
              ),
          if (known.length != list.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  '${list.length - known.length} area(s) have too few reports to judge — shown grey on the map, never as clear.',
                  style: const TextStyle(
                      fontSize: 10, color: Colors.blueGrey, height: 1.3)),
            ),
        ],
      ],
    );
  }

  static IconData _trafficIcon(String c) => switch (c) {
        'heavy' => LucideIcons.triangle,
        'moderate' => LucideIcons.clock,
        'clear' => LucideIcons.circle,
        _ => LucideIcons.helpCircle,
      };

  static Color _trafficColor(String c) => switch (c) {
        'heavy' => Colors.red,
        'moderate' => Colors.orange,
        'clear' => Colors.green,
        _ => Colors.grey,
      };

  static String _trafficLabel(String c) => switch (c) {
        'heavy' => 'Heavy traffic',
        'moderate' => 'Slower than usual',
        'clear' => 'Flowing freely',
        _ => 'Not enough data',
      };

  // ── Parking ──────────────────────────────────────────────────────────────
  Widget _parkingTab(ThemeData theme, List<ParkingArea>? zones, bool loading) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final list = zones ?? const <ParkingArea>[];
    if (list.isEmpty) {
      return _empty(
        theme,
        LucideIcons.parkingCircle,
        'No parking zones yet',
        'A church leader can add its car park with real coordinates and space counts.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      children: [
        for (final p in list)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              p.isFull ? LucideIcons.circleOff : LucideIcons.parkingCircle,
              color: p.isFull ? Colors.red : Colors.green,
              size: 18,
            ),
            title: Text(p.name,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text(
              '${p.available}/${p.total} free'
              '${p.feeKwacha > 0 ? ' · K${p.feeKwacha.toStringAsFixed(0)}' : ''}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Text(p.statusLabel,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: p.isFull ? Colors.red : Colors.green)),
          ),
      ],
    );
  }

  // ── Nearby ───────────────────────────────────────────────────────────────
  Widget _nearbyTab(
      ThemeData theme, List<NearbyPlace>? places, bool loading, bool hasFix) {
    if (!hasFix) {
      return _empty(theme, LucideIcons.mapPin, 'Location needed',
          'Nearby places are searched around you. Enable location above.');
    }
    if (loading) return const Center(child: CircularProgressIndicator());
    final list = places ?? const <NearbyPlace>[];
    if (list.isEmpty) {
      return _empty(
        theme,
        LucideIcons.store,
        'Nothing scanned nearby',
        'We query OpenStreetMap for real places around you. Nothing within 2 km right now.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      children: [
        Text('${list.length} real places from OpenStreetMap within 2 km',
            style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
        const SizedBox(height: 6),
        for (final p in list)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(_nearbyIcon(p.category), size: 18),
            title: Text(p.name,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text(
              [p.category.label, if (p.address != null) p.address!]
                  .join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
            trailing: Text(
                p.distanceKm < 1
                    ? '${(p.distanceKm * 1000).toStringAsFixed(0)} m'
                    : '${p.distanceKm.toStringAsFixed(1)} km',
                style: const TextStyle(fontSize: 11)),
          ),
      ],
    );
  }

  static IconData _nearbyIcon(NearbyCategory c) => switch (c) {
        NearbyCategory.fuel => LucideIcons.fuel,
        NearbyCategory.restaurant => LucideIcons.utensils,
        NearbyCategory.cafe => LucideIcons.coffee,
        NearbyCategory.bank => LucideIcons.landmark,
        NearbyCategory.hospital => LucideIcons.cross,
        NearbyCategory.supermarket => LucideIcons.shoppingCart,
        NearbyCategory.hotel => LucideIcons.bed,
        NearbyCategory.church => LucideIcons.church,
        NearbyCategory.police => LucideIcons.shield,
        NearbyCategory.busStation => LucideIcons.bus,
        NearbyCategory.parking => LucideIcons.parkingCircle,
      };

  // ── Quick routes ─────────────────────────────────────────────────────────
  Widget _routesTab(
      ThemeData theme, List<SavedQuickRoute>? routes, bool loading) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final list = routes ?? const <SavedQuickRoute>[];
    if (list.isEmpty) {
      return _empty(
        theme,
        LucideIcons.milestone,
        'No saved routes',
        'Save Home → Church or any regular trip and it appears here, ready to navigate.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      children: [
        for (final r in list)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.milestone, size: 18),
            title: Text(r.title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text(
              [
                if (r.fromLabel != null && r.toLabel != null)
                  '${r.fromLabel} → ${r.toLabel}',
                if (r.time != null && r.time!.isNotEmpty) r.time!,
              ].join(' · '),
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
            trailing: r.isRoutable
                ? const Icon(LucideIcons.navigation, size: 16)
                : const Icon(LucideIcons.triangle, size: 16, color: Colors.orange),
          ),
      ],
    );
  }

  Widget _empty(ThemeData theme, IconData icon, String title, String body) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: Colors.grey.withValues(alpha: 0.4)),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11, color: Colors.blueGrey, height: 1.35)),
          ],
        ),
      ),
    );
  }

  Future<void> _openReportSheet(BuildContext context, String tenantId) async {
    if (tenantId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 18,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Help the next driver',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(MapLiveService.trafficSourceNote,
                style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
            const SizedBox(height: 14),
            for (final s in const [
              ('low', 'Roads are clear'),
              ('medium', 'Slower than usual'),
              ('high', 'Heavy traffic / an accident'),
            ])
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.milestone, size: 18),
                title: Text(s.$2),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref.read(mapLiveServiceProvider).reportIncident(
                        tenantId: tenantId,
                        road: 'Nearby',
                        description: '${s.$2} (member report)',
                        severity: s.$1,
                        lat: _userLat,
                        lng: _userLng,
                      );
                  messenger.showSnackBar(SnackBar(
                      content: Text('Thanks — reported "${s.$2}".')));
                },
              ),
          ],
        ),
      ),
    );
  }
}
