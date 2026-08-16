import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:church_on_app/core/utils/country_detection_util.dart';
import 'package:church_on_app/core/widgets/church_map.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
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

  /// Full refresh: tenants (+ proximity filter) AND the nearby unregistered
  /// OSM map pins. A plain tenant re-fetch clears the OSM pins without
  /// repopulating them, which made the Refresh button look broken.
  Future<void> _refreshAll() async {
    await _fetchTenants();
    if (_currentPosition != null) {
      await _fetchNearbyChurches();
    }
  }

  Future<void> _getUserLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition();
        if (mounted) {
          setState(() {
            _currentPosition = position;
            _currentCountry = detectCountryFromCoordinates(
              position.latitude,
              position.longitude,
            );
          });
        }
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
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

      // List = registered/platform churches near the user only. When the
      // user's position is known, hide tenants farther than _maxNearbyKm;
      // tenants without coordinates are kept (distance unknown) and sort last.
      List<Map<String, dynamic>> nearby;
      if (pos != null) {
        nearby = allTenants.where((t) {
          final d = (t['_distance'] as num?)?.toDouble();
          return d == null || d <= _maxNearbyKm * 1000;
        }).toList();
      } else {
        nearby = allTenants;
      }

      if (mounted) {
        setState(() {
          _tenants = allTenants;
          _filteredTenants = nearby;
          _osmChurches = [];
          _loading = false;
        });
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
      // List shows platform (DB) churches & bookshops only — unregistered
      // OpenStreetMap results never appear here (they are map pins only).
      _filteredTenants = _tenants.where((c) {
        if (c['_osm'] == true) return false;
        final country = (c['country'] ?? '').toString().toLowerCase();
        final matchesCountry = country.contains(countryFilter);
        if (!matchesCountry) return false;

        final name = (c['name'] ?? '').toString().toLowerCase();
        final address = (c['address'] ?? '').toString().toLowerCase();
        final type = (c['type'] ?? '').toString().toLowerCase();
        final matchesQuery = query.isEmpty ||
            name.contains(query.toLowerCase()) ||
            address.contains(query.toLowerCase()) ||
            country.contains(query.toLowerCase()) ||
            type.contains(query.toLowerCase());

        // Keep the near-the-user filter applied on top of the search.
        final pos = _currentPosition;
        if (pos != null) {
          final d = (c['_distance'] as num?)?.toDouble();
          if (d != null && d > _maxNearbyKm * 1000) return false;
        }
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
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
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
        // Skip points already represented by a registered church
        bool tooClose = false;
        for (final r in registeredKeys) {
          if ((r.$1 - lat).abs() < 0.004 && (r.$2 - lng).abs() < 0.004) {
            tooClose = true;
            break;
          }
        }
        if (tooClose) continue;
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
            initialPinPosition: _pinPosition,
            onPinChanged: (point) {
              setState(() => _pinPosition = point);
            },
            markers:
                _filteredTenants.map((tenant) {
                  final lat = _parseDouble(tenant['latitude']) ?? -15.3875;
                  final lng = _parseDouble(tenant['longitude']) ?? 28.3228;
                  final isBookshop = tenant['type'] == 'bookshop';
                  final isRegistered = tenant['_registered'] == true;
                  return buildChurchMarker(
                    point: LatLng(lat, lng),
                    name: tenant['name'] ?? 'Tenant',
                    color: isRegistered
                        ? (isBookshop ? Colors.blue : Theme.of(context).primaryColor)
                        : Colors.amber,
                    logoUrl: tenant['logo_url'],
                    isBookshop: isBookshop,
                    onTap: () {
                      if (isRegistered) {
                        _selectTenant(tenant);
                      } else {
                        _toast(
                          "${tenant['name'] ?? 'This church'} is not on Church On App yet — coming soon!",
                        );
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
                    onTap: () {
                      _toast(
                        "${tenant['name'] ?? 'This church'} is not registered on Church On App yet.",
                      );
                    },
                  );
                }).toList() +
                [
                  if (pos != null)
                    buildUserMarker(point: LatLng(pos.latitude, pos.longitude)),
                ],
          ),
          _buildSearchOverlay(),
          _buildTenantList(isSuperadmin),
        ],
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
                              "Select Tenant",
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
                                        ? "Registered churches & bookshops near you in $_currentCountry"
                                        : "Churches & Bookshops in $_currentCountry")
                                    : "$_currentCountry — Coming Soon",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                  : _filteredTenants.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.church,
                            size: 50,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "No tenants found",
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          TextButton(
                            onPressed: _fetchTenants,
                            child: const Text("Tap to retry"),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 25),
                      itemCount: _filteredTenants.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _filteredTenants.length) {
                          return _buildOnboardingTile();
                        }
                        return _buildTenantTile(
                          _filteredTenants[index],
                          isSuperadmin,
                        );
                      },
                    ),
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
          _toast(
            "${tenant['name'] ?? 'This church'} is not on Church On App yet — coming soon!",
          );
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
                    ? CachedNetworkImage(
                        imageUrl: tenant['logo_url'],
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) {
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
                    icon: Icon(Icons.map, size: 20, color: theme.primaryColor),
                    onPressed: () {
                      final lat = tenant['latitude'];
                      final lng = tenant['longitude'];
                      if (lat != null && lng != null) {
                        final uri = Uri.parse(
                          "https://www.google.com/maps/search/?api=1&query=$lat,$lng",
                        );
                        launchUrl(uri, mode: LaunchMode.inAppWebView);
                      }
                    },
                  ),
                  Icon(Icons.check_circle, size: 16, color: Colors.green),
                ],
              )
            else
              GestureDetector(
                onTap: () => _toast(
                  "${tenant['name'] ?? 'This church'} is not on Church On App yet — coming soon!",
                ),
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
                    "Coming Soon",
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

  Future<void> _selectTenant(Map<String, dynamic> tenant) async {
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

      await ref
          .read(currentTenantProvider.notifier)
          .setTenant(tenantObj);

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
        ref.read(navBarVisibleProvider.notifier).show();
        if (Navigator.of(context).canPop()) {
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
