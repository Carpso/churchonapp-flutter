import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:church_on_app/core/utils/country_detection_util.dart';
import 'package:church_on_app/core/config/app_constants.dart';
import 'package:church_on_app/core/widgets/church_map.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/transport/data/route_service.dart';
import 'package:church_on_app/features/navigation/presentation/main_navigation_shell.dart';

class SelectTenantScreen extends ConsumerStatefulWidget {
  const SelectTenantScreen({super.key});

  @override
  ConsumerState<SelectTenantScreen> createState() => _SelectTenantScreenState();
}

class _SelectTenantScreenState extends ConsumerState<SelectTenantScreen> {
  List<Map<String, dynamic>> _tenants = [];
  List<Map<String, dynamic>> _filteredTenants = [];
  /// Unregistered churches found on OpenStreetMap — shown as grey map pins
  /// ONLY (never in the list). Tapping one toasts "not registered yet".
  List<Map<String, dynamic>> _osmChurches = [];
  bool _loading = true;
  Position? _currentPosition;
  String _currentCountry = "Zambia";
  /// Max distance (km) for the "nearby" list filter when location is known.
  static const double _maxNearbyKm = 50.0;
  final List<String> _supportedCountries = [
    "Zambia", "Zimbabwe", "Kenya", "Nigeria", "Ghana",
    "South Africa", "Tanzania", "Uganda", "Rwanda", "Malawi",
    "Mozambique", "Angola", "Botswana", "Namibia", "DR Congo",
    "Ethiopia", "Cameroon", "Ivory Coast", "Senegal", "Mali",
    "Burundi", "South Sudan", "Eswatini", "Lesotho", "Madagascar",
  ];
  /// Active countries that have live churches. Others show "Coming Soon".
  final Set<String> _activeCountries = {"Zambia"};
  final _searchController = TextEditingController();
  LatLng? _pinPosition;

  /// Map camera controller so a requested route can be fitted into view.
  final MapController _mapController = MapController();

  /// Active route polyline (user → selected entity), drawn by [ChurchMap].
  List<LatLng>? _routePath;
  bool _routeLoading = false;

  @override
  void initState() {
    super.initState();
    _initTenants();
  }

  Future<void> _initTenants() async {
    await _fetchTenants();
    _getUserLocation()
        .then((_) {
          if (mounted) {
            _refreshAll();
          }
        })
        .catchError((e) {
          debugPrint('Error loading user location: $e');
        });
  }

  /// Full refresh: re-fetch tenants AND retry location if not yet obtained.
  Future<void> _refreshAll() async {
    // If we don't have location yet, try again (user may have enabled it)
    if (_currentPosition == null) {
      try {
        await _getUserLocation();
      } catch (_) {}
    }
    await _fetchTenants();
    if (_currentPosition != null) {
      await _fetchNearbyChurches();
    }
  }

  Future<void> _getUserLocation() async {
    // Geolocator is not supported on the web platform; skip it entirely so we
    // don't spam the console with UnsupportedError and misleading toasts.
    if (kIsWeb) {
      debugPrint('Location skipped on web — showing all churches.');
      return;
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Location is off — showing all churches. Enable for nearby (50 km)."),
              action: SnackBarAction(label: "Enable", onPressed: () => Geolocator.openLocationSettings()),
            ),
          );
        }
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Location permanently denied — open Settings to allow."),
              action: SnackBarAction(label: "Settings", onPressed: () => Geolocator.openAppSettings()),
            ),
          );
        }
        return;
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position? position;
        try {
          position = await Geolocator.getLastKnownPosition();
          if (position != null && DateTime.now().difference(position.timestamp) > const Duration(minutes: 10)) {
            position = null;
          }
        } catch (locErr) {
          debugPrint('getLastKnownPosition failed (non-fatal): $locErr');
        }
        try {
          position ??= await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 30)),
          );
        } catch (locErr) {
          debugPrint('getCurrentPosition failed (non-fatal): $locErr');
          // If we have no lastKnownPosition either, just continue without
          // location — the map/list still shows all churches nationwide.
        }
        if (mounted && position != null) {
          setState(() {
            _currentPosition = position;
            _currentCountry = detectCountryFromCoordinates(
              position!.latitude,
              position.longitude,
            );
          });
        }
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      // Show a less alarming message — location failure is non-fatal
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Could not get location — showing all churches."),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  static double? _parseDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.trim());
    return null;
  }

  Future<void> _fetchTenants() async {
    try {
      final tenantService = ref.read(tenantServiceProvider);
      final allTenants = await tenantService.getAllTenants();

      // Add distance if position available
      final pos = _currentPosition;
      if (pos != null) {
        for (var tenant in allTenants) {
          final lat = _parseDouble(tenant['latitude']);
          final lng = _parseDouble(tenant['longitude']);
          if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
            try {
              final distance = Geolocator.distanceBetween(
                pos.latitude,
                pos.longitude,
                lat,
                lng,
              );
              tenant['_distance'] = distance;
            } catch (e) {
              debugPrint('Distance calculation error: $e');
            }
          }
        }
      }

      // Sort: Proximity First (if location available), otherwise Registered First
      allTenants.sort((a, b) {
        if (_currentPosition != null) {
          final distA = (a['_distance'] as num?)?.toDouble() ?? 999999999.0;
          final distB = (b['_distance'] as num?)?.toDouble() ?? 999999999.0;
          if (distA != distB) return distA.compareTo(distB);
        }
        final regA = a['_registered'] == true ? 0 : 1;
        final regB = b['_registered'] == true ? 0 : 1;
        return regA.compareTo(regB);
      });

      // List = registered/platform churches & bookshops, ALL shown. "Near
      // you" is a SORT preference (proximity first), never a hard filter —
      // every church and bookshop stays visible even beyond 50 km so a
      // programmatically-onboarded church (Rock Of Ages) is never hidden.
      // Populate active countries from the data so countries that actually
      // have churches (e.g. Zimbabwe) never show a false "Coming Soon".
      for (final t in allTenants) {
        final c = (t['country'] ?? '').toString().trim();
        if (c.isNotEmpty && _supportedCountries.contains(c)) {
          _activeCountries.add(c);
        }
      }

      if (mounted) {
        setState(() {
          _tenants = allTenants;
          _osmChurches = [];
          _loading = false;
        });
        _filterTenants(_searchController.text);
      }
    } catch (e) {
      debugPrint('Error fetching tenants: $e');
      if (mounted) {
        setState(() {
          _tenants = TenantService.fallbackChurches
              .map(
                (c) => ({
                  ...c,
                  '_registered': c['slug'] == 'rock-of-ages-kabulonga',
                }),
              )
              .toList();
          _filteredTenants = _tenants;
          _loading = false;
        });
      }
    }
  }

  void _filterTenants(String query) {
    setState(() {
      final countryFilter = _currentCountry.toLowerCase();
      final q = query.toLowerCase();
      // List shows platform (DB) churches & bookshops only — unregistered
      // OpenStreetMap results never appear here (they are map pins only).
      _filteredTenants = _tenants.where((c) {
        if (c['_osm'] == true) return false;
        final name = (c['name'] ?? '').toString().toLowerCase();
        final address = (c['address'] ?? '').toString().toLowerCase();
        final type = (c['type'] ?? '').toString().toLowerCase();
        final country = (c['country'] ?? '').toString().toLowerCase();
        // When searching, match by name/address/type/country regardless of
        // the user's current country — the user is explicitly searching.
        // When not searching, scope to the current country.
        final matchesQuery = q.isEmpty ||
            name.contains(q) ||
            address.contains(q) ||
            country.contains(q) ||
            type.contains(q);
        final matchesCountry = country.isEmpty || country.contains(countryFilter);
        if (q.isEmpty && !matchesCountry) return false;
        return matchesQuery;
      }).toList();
    });
  }

  /// Fetch nearby churches (including unregistered ones) from OpenStreetMap
  /// Overpass API so users can see real churches around them even if they
  /// haven't joined Church On App yet. Tapping an unregistered church shows
  /// the "Not Yet Available" dialog.
  Future<void> _fetchNearbyChurches() async {
    final pos = _currentPosition;
    if (pos == null) return;
    try {
      final bbox = '${pos.latitude - 0.5},${pos.longitude - 0.5},'
          '${pos.latitude + 0.5},${pos.longitude + 0.5}';
      final query = '''
        [out:json][timeout:15];
        (
          node["amenity"="place_of_worship"]["religion"="christian"]($bbox);
          way["amenity"="place_of_worship"]["religion"="christian"]($bbox);
        );
        out center 100;
      ''';
      final uri = Uri.parse(
        'https://overpass-api.de/api/interpreter?data=${Uri.encodeQueryComponent(query)}',
      );
      final res = await http.get(uri, headers: {'User-Agent': 'ChurchOnApp/1.0 (contact@churchonapp.com)'}).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        debugPrint('Overpass returned ${res.statusCode}');
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final elements = (data['elements'] as List? ?? []);
      if (elements.isEmpty) return;

      final registeredKeys = _tenants
          .where((t) => t['_registered'] == true)
          .map((t) {
            final lat = _parseDouble(t['latitude']);
            final lng = _parseDouble(t['longitude']);
            return lat != null && lng != null ? (lat, lng) : null;
          })
          .whereType<(double, double)>()
          .toSet();

      final nearby = <Map<String, dynamic>>[];
      for (final el in elements) {
        final double lat;
        final double lng;
        if (el['lat'] != null) {
          lat = (el['lat'] as num).toDouble();
          lng = (el['lon'] as num).toDouble();
        } else {
          final c = el['center'];
          if (c == null) continue;
          lat = (c['lat'] as num).toDouble();
          lng = (c['lon'] as num).toDouble();
        }
        // Skip points already represented by a registered church (haversine, 300m)
        bool tooClose = false;
        for (final r in registeredKeys) {
          if (Geolocator.distanceBetween(r.$1, r.$2, lat, lng) < 300) {
            tooClose = true;
            break;
          }
        }
        if (tooClose) continue;
        if (_currentPosition != null) {
          final d = Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, lat, lng);
          if (d > _maxNearbyKm * 1000) continue;
        }
        final tags = el['tags'] as Map<String, dynamic>? ?? {};
        final name = tags['name']?.toString();
        if (name == null || name.trim().isEmpty) continue;
        nearby.add({
          'id': 'osm_${el['id']}',
          'name': name,
          'type': 'church',
          'latitude': lat,
          'longitude': lng,
          'address': tags['addr:street']?.toString() ?? '',
          'country': _currentCountry,
          'logo_url': null,
          '_registered': false,
          '_osm': true,
        });
      }
      if (nearby.isEmpty || !mounted) return;

      setState(() {
        // Unregistered OSM churches become grey map pins only — they are NOT
        // added to the selectable list. Tapping a pin toasts that the church
        // has not registered on the platform yet.
        _osmChurches = nearby;
      });
    } catch (e) {
      debugPrint('Error fetching nearby churches: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final isSuperadmin = profileAsync.value?.isSuperadmin == true;

    final pos = _currentPosition;
    final center = pos != null
        ? LatLng(pos.latitude, pos.longitude)
        : const LatLng(-15.3875, 28.3228);

    return Scaffold(
      body: Stack(
        children: [
          ChurchMap(
            center: center,
            pmtilesUrl: dotenv.get('MAPS_ZAMBIA_URL'),
            zoom: pos != null ? 13 : 6,
            showPin: true,
            mapController: _mapController,
            path: _routePath,
            // A genuinely useful discovery map: live traffic overlay, a Nearby
            // POI panel (fuel/banks/pharmacies…) and the saved-places layer.
            // topInset pushes the map controls below the host search bar.
            showTraffic: true,
            showNearby: true,
            showPlaces: true,
            topInset: 76,
            initialPinPosition: _pinPosition,
            onPinChanged: (point) {
              setState(() => _pinPosition = point);
            },
            markers:
                _filteredTenants.where((tenant) {
                  // Skip pins without real coordinates instead of stacking
                  // every unknown tenant on Lusaka (-15.3875, 28.3228).
                  return _parseDouble(tenant['latitude']) != null &&
                      _parseDouble(tenant['longitude']) != null;
                }).map((tenant) {
                  final lat = _parseDouble(tenant['latitude'])!;
                  final lng = _parseDouble(tenant['longitude'])!;
                  final isBookshop = tenant['type'] == 'bookshop';
                  final isRegistered = tenant['_registered'] == true;
                  return buildChurchMarker(
                    point: LatLng(lat, lng),
                    name: tenant['name'] ?? 'Tenant',
                    color: isRegistered
                        ? (isBookshop
                            ? AppConstants.primaryDark
                            : AppConstants.sunflowerYellow)
                        : Colors.amber,
                    logoUrl: tenant['logo_url'],
                    isBookshop: isBookshop,
                    onTap: () {
                      if (isRegistered) {
                        _selectTenant(tenant);
                      } else {
                        _showRegisterSheet(tenant);
                      }
                    },
                  );
                }).toList() +
                _osmChurches.map((tenant) {
                  final lat = _parseDouble(tenant['latitude']) ?? -15.3875;
                  final lng = _parseDouble(tenant['longitude']) ?? 28.3228;
                  return buildChurchMarker(
                    point: LatLng(lat, lng),
                    name: tenant['name'] ?? 'Church',
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                    logoUrl: null,
                    isBookshop: false,
                    onTap: () => _showRegisterSheet(tenant),
                  );
                }).toList() +
                [
                  if (pos != null)
                    buildUserMarker(point: LatLng(pos.latitude, pos.longitude)),
                ],
          ),
          _buildSearchOverlay(),
          if (_routeLoading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: Theme.of(context).primaryColor,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
          if (isSuperadmin) _buildMapCounter(),
          _buildTenantList(isSuperadmin),
        ],
      ),
    );
  }

  /// Superadmin-only overlay: total registered churches on the platform,
  /// plus the number of OSM pins currently on the map.
  Widget _buildMapCounter() {
    final theme = Theme.of(context);
    final totalChurches = _tenants.where((t) => t['type'] == 'church').length;
    final registeredChurches =
        _tenants.where((t) => t['type'] == 'church' && t['_registered'] == true).length;
    final bookshops = _tenants.where((t) => t['type'] == 'bookshop').length;
    final osmNearby = _osmChurches.length;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 92,
      left: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.church, size: 16, color: Color(0xFFFFD700)),
            const SizedBox(width: 8),
            Text(
              "$registeredChurches / $totalChurches churches",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (bookshops > 0) ...[
              const SizedBox(width: 10),
              Icon(Icons.store, size: 14, color: Colors.blue.shade600),
              const SizedBox(width: 4),
              Text(
                "$bookshops",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
            if (osmNearby > 0) ...[
              const SizedBox(width: 10),
              Icon(Icons.place_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                "+$osmNearby nearby",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchOverlay() {
    final theme = Theme.of(context);
    return Positioned(
      top: MediaQuery.of(context).padding.top + 20,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _filterTenants,
          decoration: InputDecoration(
            hintText: "Search churches & bookshops in $_currentCountry...",
            border: InputBorder.none,
            icon: Icon(
              Icons.search,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTenantList(bool isSuperadmin) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 380,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 15),
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Select Entity",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                                _activeCountries.contains(_currentCountry)
                                    ? (_currentPosition != null
                                        ? "Select churches & bookshops near you in $_currentCountry"
                                        : "Select churches & bookshops in $_currentCountry")
                                    : "$_currentCountry — Coming Soon",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.primaryColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _currentCountry,
                            isDense: true,
                            icon: Icon(
                              Icons.keyboard_arrow_down,
                              size: 16,
                              color: theme.primaryColor,
                            ),
                            style: TextStyle(
                              color: theme.primaryColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            items: _supportedCountries
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(c),
                                        if (!_activeCountries.contains(c)) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            "✱",
                                            style: TextStyle(
                                              color: theme.primaryColor,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                        if (isSuperadmin)
                                          GestureDetector(
                                            onTapDown: (details) {
                                              _showCountryToggleMenu(c);
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.only(left: 4),
                                              child: Icon(
                                                _activeCountries.contains(c)
                                                    ? Icons.visibility
                                                    : Icons.visibility_off,
                                                size: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null || value == _currentCountry) {
                                return;
                              }
                              setState(() {
                                _currentCountry = value;
                                _filterTenants(_searchController.text);
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _refreshAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.05,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.refresh,
                                size: 14,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "Refresh",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: theme.primaryColor,
                      ),
                    )
                  : !_activeCountries.contains(_currentCountry)
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.public,
                            size: 50,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "$_currentCountry — Coming Soon",
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            "We are expanding to $_currentCountry soon!\nStay tuned for updates.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.4,
                              ),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Builder(builder: (context) {
                      // OSM churches are listed too (not registered in DB, just for discovery)
                      // Filter by 50km if location available, otherwise show all nearby
                      final osmForList = _osmChurches.where((c) {
                        final lat = _parseDouble(c['latitude']);
                        final lng = _parseDouble(c['longitude']);
                        if (lat == null || lng == null) return false;
                        if (_currentPosition == null) return true;
                        final d = Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, lat, lng);
                        return d <= _maxNearbyKm * 1000;
                      }).toList();
                      final allDisplay = [..._filteredTenants, ...osmForList];
                      if (allDisplay.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.church, size: 50, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                              const SizedBox(height: 10),
                              Text("No tenants found", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
                              const SizedBox(height: 5),
                              TextButton(onPressed: _refreshAll, child: const Text("Tap to retry")),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 25),
                        itemCount: allDisplay.length + 1,
                        itemBuilder: (context, index) {
                          if (index == allDisplay.length) {
                            return Column(children: [
                              _buildOnboardingTile(),
                              if (osmForList.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text("${osmForList.length} nearby churches via OpenStreetMap — not registered, shown for discovery only (not saved in our DB). Tap to invite.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 10, fontStyle: FontStyle.italic)),
                                ),
                            ]);
                          }
                          return _buildTenantTile(allDisplay[index], isSuperadmin);
                        },
                      );
                    }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTenantTile(Map<String, dynamic> tenant, bool isSuperadmin) {
    final theme = Theme.of(context);
    final isRegistered = tenant['_registered'] == true;
    final isBookshop = tenant['type'] == 'bookshop';

    return GestureDetector(
      onTap: () {
        if (isRegistered || isBookshop) {
          _selectTenant(tenant);
        } else {
          _showRegisterSheet(tenant);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isRegistered
                ? theme.primaryColor.withValues(alpha: 0.3)
                : theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: isRegistered
                  ? theme.primaryColor.withValues(alpha: 0.1)
                  : theme.colorScheme.onSurface.withValues(alpha: 0.1),
              child: ClipOval(
                child:
                    tenant['logo_url'] != null &&
                        (tenant['logo_url'] as String).isNotEmpty
                    ? AppImage(
                        tenant['logo_url'],
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorWidget: (context, url) {
                          return Icon(
                            isBookshop ? Icons.store : Icons.church,
                            color: isRegistered
                                ? theme.primaryColor
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                          );
                        },
                      )
                    : Icon(
                        isBookshop ? Icons.store : Icons.church,
                        color: isRegistered
                            ? theme.primaryColor
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                      ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tenant['name'] ?? 'Unknown',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isRegistered
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        isBookshop
                            ? 'Bookshop'
                            : (tenant['address'] ?? 'Zambia'),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isBookshop
                              ? Colors.blue.shade50
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isBookshop ? 'Bookshop' : 'Church',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isBookshop ? Colors.blue : Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (tenant['_distance'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        "${(((tenant['_distance'] as num).toDouble()) / 1000).toStringAsFixed(1)} km away",
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (isRegistered || isBookshop)
              Column(
                children: [
                  IconButton(
                    icon: Icon(Icons.directions, size: 20, color: theme.primaryColor),
                    tooltip: "Directions",
                    onPressed: () => _showDirections(tenant),
                  ),
                  Icon(Icons.check_circle, size: 16, color: Colors.green),
                ],
              )
            else
              GestureDetector(
                onTap: () => _showRegisterSheet(tenant),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Text(
                    "Coming Soon — Tap to Register",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            if (isSuperadmin) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  isRegistered ? Icons.remove_circle : Icons.add_circle,
                  color: isRegistered ? Colors.red : Colors.green,
                  size: 24,
                ),
                onPressed: () => _toggleTenantVerification(tenant),
                tooltip: isRegistered
                    ? "Remove Registered Status"
                    : "Approve/Register",
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleTenantVerification(Map<String, dynamic> tenant) async {
    final slug = (tenant['slug'] ?? tenant['id'] ?? 'unknown-tenant')
        .toString();
    final currentlyRegistered = tenant['_registered'] == true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          currentlyRegistered ? "Remove Registration" : "Approve Registration",
        ),
        content: Text(
          "Are you sure you want to set ${tenant['name'] ?? 'this tenant'} to ${currentlyRegistered ? 'Pending' : 'Approved'}?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: currentlyRegistered ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(currentlyRegistered ? "REMOVE" : "APPROVE"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _loading = true;
    });

    try {
      final dbRes = await Supabase.instance.client
          .from('churches')
          .select('id')
          .eq('slug', slug)
          .maybeSingle();

      if (dbRes == null) {
        await Supabase.instance.client.from('churches').insert({
          'slug': slug,
          'name': tenant['name'] ?? 'Unknown',
          'logo_url': tenant['logo_url'],
          'primary_color': tenant['primary_color'] ?? '#FFD700',
          'accent_color': tenant['accent_color'] ?? '#1A1A1A',
          'latitude': tenant['latitude'],
          'longitude': tenant['longitude'],
          'address': tenant['address'],
          'country': tenant['country'] ?? 'Zambia',
          'is_verified': !currentlyRegistered,
        });
      } else {
        await Supabase.instance.client
            .from('churches')
            .update({'is_verified': !currentlyRegistered})
            .eq('slug', slug);
      }

      await _fetchTenants();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "${tenant['name']} set to ${!currentlyRegistered ? 'Approved' : 'Pending'}",
            ),
            backgroundColor: !currentlyRegistered
                ? Colors.green
                : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error toggling tenant verification: $e");
      if (mounted) {
        setState(() {
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to update status: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildOnboardingTile() {
    final theme = Theme.of(context);
    return Column(
      children: [
        GestureDetector(
          onTap: () => context.push('/register-church'),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 6),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add,
                    color: theme.colorScheme.onSecondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Register a New Church",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        "Join the digital ecosystem today.",
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: theme.primaryColor),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: () => _showInviteCodeDialog(context),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 6),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.key, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Enter Invite Code", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
                      Text("Join a church using a pastor's invite code.", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Colors.amber),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: () => context.push('/bookshop-onboarding'),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 6),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.store, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Open a Bookshop",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        "Start selling Christian literature & resources.",
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: Colors.blue),
              ],
            ),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  void _toast(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              backgroundColor ?? Theme.of(context).primaryColor,
        ),
      );
  }

  void _showRegisterSheet(Map<String, dynamic> church) {
    if (!mounted) return;
    final name = church['name']?.toString() ?? 'This church';
    final lat = _parseDouble(church['latitude']);
    final lng = _parseDouble(church['longitude']);
    String distanceLabel = '';
    if (lat != null && lng != null && _currentPosition != null) {
      final d = Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, lat, lng);
      distanceLabel = d < 1000 ? '${d.toStringAsFixed(0)} m away' : '${(d/1000).toStringAsFixed(1)} km away';
    }
    final address = church['address']?.toString() ?? '';
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 16),
            Row(children: [
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.church, color: Colors.amber, size: 24)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (distanceLabel.isNotEmpty) Text(distanceLabel, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                if (address.isNotEmpty) Text(address, style: TextStyle(color: Colors.grey.shade500, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: const Text("Not on COA", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey))),
            ]),
            const SizedBox(height: 12),
            Text("This church is not yet registered on Church On App. We found it near you via OpenStreetMap — it is listed on the map for discovery only and is NOT saved in our database.", style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.4)),
            const SizedBox(height: 8),
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.withValues(alpha: 0.3))), child: Row(children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.amber),
              const SizedBox(width: 8),
              const Expanded(child: Text("Are you the owner? Register your church to claim this listing and appear to nearby members.", style: TextStyle(fontSize: 11, color: Color(0xFF7A5C00)))),
            ])),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () {
              Navigator.pop(ctx);
              // Pass the tapped place so registration CLAIMS this location
              // instead of creating a second pin elsewhere on the map.
              context.push('/register-church', extra: {
                'name': name,
                'address': address,
                'lat': lat,
                'lng': lng,
              });
            }, icon: const Icon(Icons.app_registration, size: 18), label: const Text("Register This Church"))),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () { Navigator.pop(ctx); _toast("Share: $name — invite at churchonapp.com/register-church"); }, icon: const Icon(Icons.share, size: 16), label: const Text("Share Invite"))),
          ],
        ),
      ),
    );
  }

  void _showCountryToggleMenu(String country) {
    final isActive = _activeCountries.contains(country);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("${isActive ? 'Deactivate' : 'Activate'} $country"),
        content: Text(
          isActive
              ? "Hide $country from the country selector for regular users?"
              : "Make $country visible and selectable for all users?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                if (isActive) {
                  _activeCountries.remove(country);
                } else {
                  _activeCountries.add(country);
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(isActive ? "DEACTIVATE" : "ACTIVATE"),
          ),
        ],
      ),
    );
  }

  void _showInviteCodeDialog(BuildContext context) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Enter Invite Code"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Paste the invite code your pastor shared with you."),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              decoration: InputDecoration(
                hintText: "e.g. COA-ZM_CH_0001",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(LucideIcons.key),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              final code = codeController.text.trim();
              Navigator.pop(ctx);
              if (code.isNotEmpty) {
                context.go('/join?code=$code');
              }
            },
            child: const Text("Join"),
          ),
        ],
      ),
    );
  }

  /// Real directions from the user's current location to a tapped entity:
  /// fetches an OSRM road route via [RouteService], draws it on the map, fits
  /// the camera to it, and shows distance + ETA with a one-tap external
  /// navigation hand-off.
  Future<void> _showDirections(Map<String, dynamic> tenant) async {
    final lat = _parseDouble(tenant['latitude']);
    final lng = _parseDouble(tenant['longitude']);
    if (lat == null || lng == null) {
      _toast('This entity has no location on record.');
      return;
    }
    final dest = LatLng(lat, lng);
    final name = tenant['name']?.toString() ?? 'Destination';

    if (_currentPosition == null) {
      _toast('Enable location for distance & ETA — opening maps.',
          backgroundColor: Colors.orange);
      await _openExternalDirections(dest);
      return;
    }

    setState(() => _routeLoading = true);
    try {
      final route = await RouteService.fetchRoute(
        from: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        to: dest,
      );
      if (!mounted) return;
      setState(() {
        _routePath = route.points;
        _routeLoading = false;
        _pinPosition = dest;
      });
      try {
        _mapController.fitCamera(CameraFit.coordinates(
          coordinates: route.points,
          padding: const EdgeInsets.all(70),
        ));
      } catch (e) {
        debugPrint('fit route camera failed (non-fatal): $e');
      }
      if (!mounted) return;
      _showRouteSheet(name, route, dest);
    } catch (e) {
      if (mounted) {
        setState(() => _routeLoading = false);
        _toast('Could not build a route: $e', backgroundColor: Colors.red);
      }
    }
  }

  void _showRouteSheet(String name, RouteResult route, LatLng dest) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                _routeStat(Icons.route, route.distanceText, 'Distance'),
                const SizedBox(width: 12),
                _routeStat(Icons.schedule, route.etaText, 'ETA'),
                const SizedBox(width: 12),
                _routeStat(Icons.alt_route,
                    route.isFallback ? 'Direct' : '${route.steps.length}',
                    'Steps'),
              ],
            ),
            if (route.isFallback) ...[
              const SizedBox(height: 10),
              Text(
                'Road routing is unavailable right now — showing a straight-line estimate.',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openExternalDirections(dest);
                },
                icon: const Icon(Icons.navigation, size: 18),
                label: const Text('START NAVIGATION'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _routePath = null);
                },
                icon: const Icon(Icons.close, size: 16),
                label: const Text('CLEAR ROUTE'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeStat(IconData icon, String value, String label) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: theme.primaryColor),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 14)),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5))),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternalDirections(LatLng dest) async {
    final origin = _currentPosition != null
        ? '&origin=${_currentPosition!.latitude},${_currentPosition!.longitude}'
        : '';
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1$origin&destination=${dest.latitude},${dest.longitude}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('directions launch failed: $e');
      if (mounted) _toast('Could not open maps', backgroundColor: Colors.red);
    }
  }

  Future<void> _selectTenant(Map<String, dynamic> tenant) async {
    // Capture providers/notifiers BEFORE any `await`. Reading `ref` after the
    // widget has been unmounted (the user navigates away while the tenant
    // switch/notify calls are in flight) throws
    // "Bad state: Using ref when a widget is about to or has been unmounted".
    final tenantNotifier = ref.read(currentTenantProvider.notifier);
    final navBarNotifier = ref.read(navBarVisibleProvider.notifier);
    try {
      final rawId = tenant['id']?.toString() ?? '';
      final rawSlug = tenant['slug']?.toString() ?? '';
      final finalId = rawId.isNotEmpty ? rawId : (rawSlug.isNotEmpty ? rawSlug : 'zm_1');
      final finalSlug = rawSlug.isNotEmpty ? rawSlug : finalId;

      final tenantObj = Tenant.fromMap({
        ...tenant,
        'id': finalId,
        'slug': finalSlug,
        'name': tenant['name'] ?? 'Church On App',
      });

      await tenantNotifier.setTenant(tenantObj);

      if (!mounted) return;
      ref.invalidate(profileProvider);

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        try {
          String newUserName = 'A new member';
          final meta = user.userMetadata;
          if (meta is Map<String, dynamic>) {
            final fullName = meta['full_name'];
            if (fullName != null && fullName.toString().trim().isNotEmpty) {
              newUserName = fullName.toString().trim();
            } else if (user.email != null && user.email!.isNotEmpty) {
              newUserName = user.email!;
            }
          } else if (user.email != null && user.email!.isNotEmpty) {
            newUserName = user.email!;
          }

          final token = Supabase.instance.client.auth.currentSession?.accessToken;
          if (token != null) {
            await Supabase.instance.client.functions.invoke(
              'new-member-notify',
              body: {
                'newUserId': user.id,
                'newUserName': newUserName,
                'churchId': tenantObj.id,
                'churchName': tenantObj.name,
              },
              headers: {'Authorization': 'Bearer $token'},
            );
          }
        } catch (e) {
          debugPrint('notify join error: $e');
        }
      }

      if (mounted) {
        navBarNotifier.show();
        final redirect = GoRouterState.of(context).uri.queryParameters['redirect'];
        if (redirect != null && redirect.isNotEmpty) {
          context.go(Uri.decodeComponent(redirect));
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          context.go('/');
        }
      }
    } catch (e, stack) {
      debugPrint('TENANT SELECTION ERROR: $e');
      debugPrint("TENANT ERROR: $e\n$stack");
    }
  }
}
