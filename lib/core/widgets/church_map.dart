import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:church_on_app/core/config/app_constants.dart';
import 'package:church_on_app/core/services/geocoding_service.dart';
import 'package:church_on_app/features/transport/presentation/saved_places_sheet.dart';
import 'maps/protomaps_light_v4_layers.dart';
import 'maps/protomaps_dark_v4_layers.dart';
import 'app_image.dart';

/// Protomaps v4 "light" theme with **self-hosted** glyphs + sprites.
///
/// The package's `ProtomapsThemes.lightV4()` hardcodes protomaps.github.io for
/// font glyphs and does not expose the URL, so we build the theme from our own
/// copy of the v4 layer list (see `maps/protomaps_light_v4_layers.dart`) and
/// point glyphs/sprites at assets served from OUR domain (`web/map-assets/…`,
/// bundled into every web deploy). Map labels therefore need no third-party
/// dependency and keep working offline once cached.
final _brandLightMapTheme = ProtomapsThemes(
  glyphs: 'https://maps.churchonapp.com/map-assets/fonts/{fontstack}/{range}.pbf',
  sprites: 'https://maps.churchonapp.com/map-assets/sprites/v4/light',
).build(kProtomapsLightV4Layers);

/// Protomaps v4 "dark" theme with **self-hosted** glyphs + sprites (mirrors the
/// light theme above). Labels are drawn with local Flutter fonts by the current
/// renderer, but the local layer list + self-hosted asset URLs keep dark mode
/// free of any `protomaps.github.io` dependency and offline-capable.
final _brandDarkMapTheme = ProtomapsThemes(
  glyphs: 'https://maps.churchonapp.com/map-assets/fonts/{fontstack}/{range}.pbf',
  sprites: 'https://maps.churchonapp.com/map-assets/sprites/v4/dark',
).build(kProtomapsDarkV4Layers);

/// A reusable map widget: self-hosted Protomaps basemap, optional pin
/// placement + save, saved-places layer, address search, and theme awareness.
class ChurchMap extends ConsumerStatefulWidget {
  final LatLng center;
  final double zoom;
  final List<Marker> markers;
  final List<LatLng>? path;
  final bool darkMode;
  final String? pmtilesUrl;

  // Pin placement mode
  final bool showPin;
  final LatLng? initialPinPosition;
  final ValueChanged<LatLng>? onPinChanged;
  /// When true (and [showPin] is on), a "SAVE THIS PIN" action appears once a
  /// pin is dropped — it reverse-geocodes the point into a street name and
  /// stores it in the server-side `saved_places` table so it is reusable for
  /// last-mile delivery on any device.
  final bool showSavePin;

  // Saved-places layer (own places + tenant landmarks from `saved_places`).
  /// Show the places layer initially (a toggle button lets the user hide it).
  final bool showPlaces;
  /// Called when a place marker is tapped (e.g. set it as the destination).
  final ValueChanged<SavedPlace>? onPlaceTap;

  // Address search
  final bool showAddressSearch;
  final String? addressSearchHint;
  final ValueChanged<String>? onAddressSelected;

  // Interaction
  final ValueChanged<LatLng>? onMapTapped;

  /// Extra flutter_map layers drawn between the basemap and the place/pin
  /// markers — e.g. a `CircleLayer` for heatmaps or a `MarkerLayer`.
  final List<Widget> extraLayers;

  /// When true, shows a "located me" style recenter control.
  final bool showLocateButton;

  /// When true, shows a "download this area" control that pre-caches the
  /// current view (across zoom levels) so it keeps working without signal.
  final bool showOfflineButton;

  /// Warm the basemap toward the brand sunflower yellow (a very light multiply
  /// over the tiles). Purely cosmetic; set false if you want a neutral basemap.
  final bool brandTint;

  // Optional external controller (for programmatic map movement)
  final MapController? mapController;

  const ChurchMap({
    super.key,
    this.center = const LatLng(-15.3875, 28.3228),
    this.zoom = 14,
    this.markers = const [],
    this.path,
    this.darkMode = false,
    this.pmtilesUrl,
    this.showPin = false,
    this.initialPinPosition,
    this.onPinChanged,
    this.showSavePin = true,
    this.showPlaces = false,
    this.onPlaceTap,
    this.showAddressSearch = false,
    this.addressSearchHint,
    this.onAddressSelected,
    this.onMapTapped,
    this.extraLayers = const [],
    this.showLocateButton = true,
    this.showOfflineButton = true,
    this.brandTint = true,
    this.mapController,
  });

  @override
  ConsumerState<ChurchMap> createState() => _ChurchMapState();
}

class _ChurchMapState extends ConsumerState<ChurchMap> {
  final MapController _mapController = MapController();
  late Future<PmTilesVectorTileProvider> _tileProvider;

  LatLng? _pinPosition;
  bool _savingPin = false;
  bool _placesVisible = false;
  bool _downloading = false;
  double _zoom = 14;
  final TextEditingController _searchCtrl = TextEditingController();

  /// Grid-based marker clustering. When there are many markers at a low zoom,
  /// nearby pins are merged into a single count badge; tapping a cluster zooms
  /// in. Keeps dense maps (a whole town of churches) readable without pulling in
  /// a clustering dependency.
  static const int _clusterThreshold = 8;

  List<Marker> _clusterMarkers(List<Marker> markers, ThemeData theme) {
    if (_zoom >= 15 || markers.length <= _clusterThreshold) return markers;

    // Cell size in degrees: ~84px at the equator at this zoom, so the grouping
    // radius stays visually constant as you zoom.
    final cell = 84.375 / math.pow(2, _zoom);
    if (cell <= 0 || !cell.isFinite) return markers;

    final buckets = <String, List<Marker>>{};
    for (final m in markers) {
      final key =
          '${(m.point.latitude / cell).floor()}:${(m.point.longitude / cell).floor()}';
      buckets.putIfAbsent(key, () => []).add(m);
    }

    final result = <Marker>[];
    for (final group in buckets.values) {
      if (group.length == 1) {
        result.add(group.first);
      } else {
        final lat =
            group.fold<double>(0, (s, m) => s + m.point.latitude) / group.length;
        final lng = group.fold<double>(0, (s, m) => s + m.point.longitude) /
            group.length;
        result.add(_buildClusterMarker(LatLng(lat, lng), group.length, theme));
      }
    }
    return result;
  }

  Marker _buildClusterMarker(LatLng point, int count, ThemeData theme) {
    return Marker(
      point: point,
      width: 54,
      height: 54,
      child: GestureDetector(
        onTap: () {
          final next = (_zoom + 2).clamp(3.0, 18.0);
          _mapController.move(point, next);
        },
        child: Container(
          decoration: BoxDecoration(
            color: theme.primaryColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  /// Pre-caches the current view for offline use.
  ///
  /// Walks the camera through the useful zoom levels around the current centre
  /// so the vector tile layer fetches and (disk) caches every tile for this
  /// area — those tiles then render with no signal (90-day cache).
  Future<void> _downloadArea() async {
    if (_downloading) return;
    final cam = _mapController.camera;
    final center = cam.center;
    final originalZoom = cam.zoom;
    setState(() => _downloading = true);
    try {
      for (final z in <double>[13, 14, 15]) {
        _mapController.move(center, z);
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    } catch (e) {
      debugPrint('download area failed (non-fatal): $e');
    } finally {
      _mapController.move(center, originalZoom);
      if (mounted) setState(() => _downloading = false);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This area is cached — it now works offline.'),
        backgroundColor: Colors.green,
      ));
    }
  }

  /// Reverse-geocodes the dropped pin into a street name and stores it in the
  /// server-side `saved_places` table (reusable for last-mile delivery).
  Future<void> _savePin() async {
    final point = _pinPosition;
    if (point == null) return;
    setState(() => _savingPin = true);

    var address =
        '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
    try {
      final places =
          await placemarkFromCoordinates(point.latitude, point.longitude);
      if (places.isNotEmpty) {
        final p = places.first;
        final street = [p.street, p.subLocality]
            .where((s) => s != null && s.isNotEmpty)
            .join(', ');
        final area = [p.locality, p.subAdministrativeArea]
            .where((s) => s != null && s.isNotEmpty)
            .join(', ');
        final label = [street, area].where((s) => s.isNotEmpty).join(', ');
        if (label.isNotEmpty) address = label;
      }
    } catch (e) {
      debugPrint('save pin: geocode failed (non-fatal): $e');
    }

    if (!mounted) return;
    try {
      // Ask for a name + scope before saving so couriers can reuse shared
      // landmarks ("Main Gate", "Depot") across the church.
      final labelCtrl = TextEditingController(text: 'Pinned location');
      final share = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save this place'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(address,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Main Gate, Home, Depot',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('JUST ME'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('SHARE WITH CHURCH'),
            ),
          ],
        ),
      );
      if (share == null) return; // cancelled

      final label = labelCtrl.text.trim().isEmpty
          ? 'Pinned location'
          : labelCtrl.text.trim();
      await SavedPlacesService().add(
        label,
        address,
        isPublic: share,
        lat: point.latitude,
        lng: point.longitude,
      );
      ref.invalidate(savedPlacesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(share
                  ? 'Shared with your church: $label'
                  : 'Pin saved: $label')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save pin: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPin = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _pinPosition = widget.initialPinPosition;
    _placesVisible = widget.showPlaces;
    _zoom = widget.zoom;
    _initializeProvider();
  }

  @override
  void didUpdateWidget(ChurchMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pmtilesUrl != widget.pmtilesUrl) {
      _initializeProvider();
    }
    if (oldWidget.initialPinPosition != widget.initialPinPosition) {
      _pinPosition = widget.initialPinPosition;
    }
    if (oldWidget.showPlaces != widget.showPlaces) {
      _placesVisible = widget.showPlaces;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _initializeProvider() {
    final url = widget.pmtilesUrl ?? dotenv.env['MAPS_ZAMBIA_URL'] ?? '';
    _tileProvider = PmTilesVectorTileProvider.fromSource(url);
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (widget.showPin) {
      setState(() => _pinPosition = point);
      widget.onPinChanged?.call(point);
    }
    widget.onMapTapped?.call(point);
  }

  Future<void> _searchAddress() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;

    try {
      // Resilient chain (cache → self-hosted/Nominatim → Photon).
      final hit = await GeocodingService.forward(query);
      if (hit == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No location found for that address')),
          );
        }
        return;
      }

      final point = LatLng(hit.lat, hit.lng);
      _mapController.move(point, 16);

      if (widget.showPin) {
        setState(() => _pinPosition = point);
        widget.onPinChanged?.call(point);
      }
      widget.onAddressSelected?.call(query);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    }
  }

  Future<void> _goToCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      final point = LatLng(pos.latitude, pos.longitude);
      _mapController.move(point, 16);

      if (widget.showPin) {
        setState(() => _pinPosition = point);
        widget.onPinChanged?.call(point);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get current location')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Saved places (own + tenant landmarks) — only watched when the layer is on
    // so maps that don't want it pay nothing.
    final places = _placesVisible
        ? (ref.watch(savedPlacesProvider).value ?? const <SavedPlace>[])
        : const <SavedPlace>[];

    return Stack(
      children: [
        // Map layer
        FutureBuilder<PmTilesVectorTileProvider>(
          future: _tileProvider,
          builder: (context, snapshot) {
            final vectorProvider = snapshot.data;
            return FlutterMap(
              mapController: widget.mapController ?? _mapController,
              options: MapOptions(
                initialCenter: widget.center,
                initialZoom: widget.zoom,
                maxZoom: 18,
                minZoom: 3,
                onTap: _onMapTap,
                onPositionChanged: (camera, hasGesture) {
                  final z = camera.zoom;
                  if ((z - _zoom).abs() >= 0.25 && mounted) {
                    setState(() => _zoom = z);
                  }
                },
              ),
              children: [
                // Self-hosted Protomaps vector basemap (maps.churchonapp.com).
                // Carries street-name labels (roads/places layers) and needs no
                // third-party tile service. Falls back to OSM raster if the
                // archive can't be opened.
                _brandTintWrap(
                  vectorProvider != null
                      ? VectorTileLayer(
                          tileProviders: TileProviders({'protomaps': vectorProvider}),
                          theme: widget.darkMode
                              ? _brandDarkMapTheme
                              : _brandLightMapTheme,
                          // The archive covers z0–15; over-zoom is handled below.
                          maximumZoom: 15,
                          // Offline-friendly: tiles are cached to disk for 90
                          // days with a 250 MB budget, so an area a courier has
                          // already viewed keeps working with no signal.
                          fileCacheTtl: const Duration(days: 90),
                          fileCacheMaximumSizeInBytes: 250 * 1024 * 1024,
                        )
                      : TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.churchonapp.flutter',
                          tileDisplay: const TileDisplay.fadeIn(),
                        ),
                ),
                ...widget.extraLayers,
                if (widget.path != null && widget.path!.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: widget.path!,
                        color: theme.primaryColor.withValues(alpha: 0.3),
                        strokeWidth: 8,
                      ),
                      Polyline(
                        points: widget.path!,
                        color: theme.primaryColor,
                        strokeWidth: 4,
                        borderColor: Colors.white,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    ..._clusterMarkers(widget.markers, theme),
                    // Saved places layer (own places + tenant landmarks).
                    ...places
                        .where((p) => p.lat != null && p.lng != null)
                        .map((p) => _buildPlaceMarker(p, theme)),
                    // Pin marker
                    if (widget.showPin && _pinPosition != null)
                      _buildPinMarker(_pinPosition!, theme),
                  ],
                ),
              ],
            );
          },
        ),

        // Address search bar
        if (widget.showAddressSearch) _buildSearchBar(theme),

        // Map controls — each gets its own slot so they never overlap.
        // Slot 1: places layer toggle.
        Positioned(
          right: 16,
          bottom: 80,
          child: _buildFloatingButton(
            icon: _placesVisible ? LucideIcons.mapPin : LucideIcons.bookmark,
            color: AppConstants.primaryDark,
            filled: _placesVisible,
            onTap: () => setState(() => _placesVisible = !_placesVisible),
          ),
        ),
        // Slot 2: recenter on my location.
        if (widget.showLocateButton)
          Positioned(
            right: 16,
            bottom: 132,
            child: _buildFloatingButton(
              icon: LucideIcons.crosshair,
              color: theme.primaryColor,
              onTap: _goToCurrentLocation,
            ),
          ),
        // Slot 3: pre-cache this view for offline use.
        if (widget.showOfflineButton)
          Positioned(
            right: 16,
            bottom: 184,
            child: _buildFloatingButton(
              icon: _downloading ? LucideIcons.loader : LucideIcons.download,
              color: AppConstants.primaryDark,
              onTap: _downloading ? () {} : _downloadArea,
            ),
          ),

        // "Save this pin" — persists the dropped pin as a map place so it can
        // be reused for pickup/dropoff and last-mile delivery.
        if (widget.showPin && widget.showSavePin && _pinPosition != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(14),
              color: theme.primaryColor,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _savingPin ? null : _savePin,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_savingPin)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      else
                        const Icon(LucideIcons.bookmark,
                            color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        _savingPin ? 'SAVING…' : 'SAVE THIS PIN',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(14),
        color: theme.cardColor,
        child: TextField(
          controller: _searchCtrl,
          style: TextStyle(color: theme.textTheme.bodyLarge?.color),
          decoration: InputDecoration(
            hintText: widget.addressSearchHint ?? 'Search address…',
            hintStyle: TextStyle(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6)),
            prefixIcon: Icon(LucideIcons.search, color: theme.primaryColor, size: 20),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(LucideIcons.x, color: theme.textTheme.bodySmall?.color, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {});
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: theme.cardColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _searchAddress(),
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }

  /// Subtle brand warm-up of the basemap so the map matches the app's
  /// sunflower-yellow identity (light themes only; dark stays neutral).
  Widget _brandTintWrap(Widget child) {
    if (!widget.brandTint || widget.darkMode) return child;
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Color(0xFFFDF2C9), BlendMode.multiply),
      child: child,
    );
  }

  /// Marker for a saved place (own place or tenant landmark).
  Marker _buildPlaceMarker(SavedPlace place, ThemeData theme) {
    final isLandmark = place.placeType == 'landmark' || place.isPublic;
    // Brand sunflower for personal places; dark for tenant landmarks so they
    // stay distinguishable while remaining on-brand.
    final color =
        isLandmark ? AppConstants.primaryDark : AppConstants.sunflowerYellow;
    final onColor = isLandmark ? Colors.white : AppConstants.primaryDark;
    return Marker(
      point: LatLng(place.lat!, place.lng!),
      width: 150,
      height: 62,
      child: GestureDetector(
        // Tapping a place drops the pin on it (when pin mode is on) so it can be
        // used as the pickup/dropoff, then notifies the caller.
        onTap: () {
          final point = LatLng(place.lat!, place.lng!);
          if (widget.showPin) {
            setState(() => _pinPosition = point);
            widget.onPinChanged?.call(point);
          }
          _mapController.move(point, _mapController.camera.zoom);
          widget.onPlaceTap?.call(place);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isLandmark ? LucideIcons.star : LucideIcons.bookmark,
                      size: 12, color: onColor),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      place.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: onColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.mapPin, color: color, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          // Active/selected controls are filled with the brand sunflower colour.
          color: filled ? AppConstants.sunflowerYellow : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Icon(icon, color: filled ? AppConstants.primaryDark : color, size: 22),
      ),
    );
  }

  Marker _buildPinMarker(LatLng point, ThemeData theme) {
    return Marker(
      point: point,
      width: 60,
      height: 60,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppConstants.sunflowerYellow,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6)],
            ),
            child: const Icon(LucideIcons.mapPin, size: 14, color: AppConstants.primaryDark),
          ),
          Container(
            width: 0,
            height: 14,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: theme.primaryColor, width: 2),
                right: BorderSide(color: theme.primaryColor, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Marker buildChurchMarker({
  required LatLng point,
  required String name,
  required Color color,
  String? logoUrl,
  VoidCallback? onTap,
  bool isBookshop = false,
  bool animated = true,
}) {
  return Marker(
    point: point,
    width: 100,
    height: 120,
    child: _AnimatedPin(
      name: name,
      // Churches use the brand sunflower; bookshops a dark brand tone so the
      // two entity types stay visually distinct.
      color: isBookshop ? AppConstants.primaryDark : color,
      logoUrl: logoUrl,
      isBookshop: isBookshop,
      animated: animated,
      onTap: onTap,
    ),
  );
}

class _AnimatedPin extends StatefulWidget {
  final String name;
  final Color color;
  final String? logoUrl;
  final bool isBookshop;
  final bool animated;
  final VoidCallback? onTap;

  const _AnimatedPin({required this.name, required this.color, this.logoUrl, this.isBookshop = false, this.animated = true, this.onTap});

  @override
  State<_AnimatedPin> createState() => _AnimatedPinState();
}

class _AnimatedPinState extends State<_AnimatedPin> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    if (widget.animated) {
      _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
      _bounce = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    if (widget.animated) _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bounceOffset = widget.animated ? _bounce.value * 6 : 0.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: Transform.translate(
        offset: Offset(0, -bounceOffset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Teardrop pin: a single continuous shape (circular head + tapered
            // tail) with the entity's LOGO sitting on top of it.
            SizedBox(
              width: 54,
              height: 70,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  CustomPaint(
                    size: const Size(54, 70),
                    painter: _TeardropPinPainter(widget.color),
                  ),
                  // Logo / icon seated inside the circular head.
                  Positioned(
                    top: 7,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: ClipOval(
                        child: (widget.logoUrl != null &&
                                widget.logoUrl!.trim().isNotEmpty)
                            ? AppImage(widget.logoUrl!,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                errorWidget: (_, __) => _fallbackIcon())
                            : _fallbackIcon(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Name label
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackIcon() {
    return Container(
      color: widget.color.withValues(alpha: 0.12),
      child: Icon(widget.isBookshop ? LucideIcons.store : LucideIcons.church,
          color: widget.color, size: 22),
    );
  }
}

/// A classic map "teardrop" pin: circular head + tapered tail as ONE continuous
/// outline (so the white border never shows a seam), with a drop shadow.
class _TeardropPinPainter extends CustomPainter {
  final Color color;
  _TeardropPinPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final r = w / 2;
    final cx = w / 2;

    // NB: `Path` must be qualified — flutter_map also exports a `Path` type.
    final head = ui.Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, r), radius: r - 2));

    // Tail: sweeps from the head's lower flanks down to a point.
    final shoulder = r * 0.60;
    final tail = ui.Path()
      ..moveTo(cx - shoulder, r + shoulder)
      ..quadraticBezierTo(cx - shoulder * 0.35, size.height - 14, cx, size.height - 1)
      ..quadraticBezierTo(cx + shoulder * 0.35, size.height - 14, cx + shoulder, r + shoulder)
      ..close();

    final shape = ui.Path.combine(ui.PathOperation.union, head, tail);

    canvas.drawShadow(shape, Colors.black.withValues(alpha: 0.35), 5, false);
    canvas.drawPath(shape, Paint()..color = color..style = PaintingStyle.fill);
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _TeardropPinPainter oldDelegate) =>
      oldDelegate.color != color;
}

Marker buildRideMarker({required LatLng point, Color? color}) {
  final c = color ?? Colors.blueAccent;
  return Marker(
    point: point,
    width: 50,
    height: 50,
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10)],
      ),
      child: Icon(LucideIcons.car, color: Colors.black, size: 20),
    ),
  );
}

Marker buildUserMarker({required LatLng point, Color? color}) {
  final c = color ?? Colors.blue;
  return Marker(
    point: point,
    width: 40,
    height: 40,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ],
    ),
  );
}

Marker buildCarpsoDestinationMarker({required LatLng point, required String label}) {
  return Marker(
    point: point,
    width: 80,
    height: 80,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD700),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.4), blurRadius: 8)],
          ),
          child: const Icon(LucideIcons.mapPin, color: Colors.black, size: 16),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// A live bus marker shown at the bus's current GPS position.
Marker buildBusMarker({required LatLng point, required String name, Color? color}) {
  final c = color ?? const Color(0xFFE8C547);
  return Marker(
    point: point,
    width: 80,
    height: 80,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 8)],
          ),
          child: const Icon(LucideIcons.bus, color: Colors.black, size: 16),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            name,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

Marker buildBusStopMarker({required LatLng point, required String name, Color? color}) {
  final c = color ?? Colors.orange;
  return Marker(
    point: point,
    width: 80,
    height: 80,
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.3), blurRadius: 8)],
          ),
          child: Icon(LucideIcons.bus, color: Colors.white, size: 16),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            name,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}
