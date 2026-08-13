import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// A reusable map widget with optional pin placement, address search, and theme awareness.
class ChurchMap extends StatefulWidget {
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

  // Address search
  final bool showAddressSearch;
  final String? addressSearchHint;
  final ValueChanged<String>? onAddressSelected;

  // Interaction
  final ValueChanged<LatLng>? onMapTapped;

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
    this.showAddressSearch = false,
    this.addressSearchHint,
    this.onAddressSelected,
    this.onMapTapped,
  });

  @override
  State<ChurchMap> createState() => _ChurchMapState();
}

class _ChurchMapState extends State<ChurchMap> {
  final MapController _mapController = MapController();
  late Future<PmTilesVectorTileProvider> _tileProvider;

  LatLng? _pinPosition;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pinPosition = widget.initialPinPosition;
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
      final locations = await locationFromAddress(query);
      if (locations.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No location found for that address')),
          );
        }
        return;
      }

      final loc = locations.first;
      final point = LatLng(loc.latitude, loc.longitude);

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

    return Stack(
      children: [
        // Map layer
        FutureBuilder<PmTilesVectorTileProvider>(
          future: _tileProvider,
          builder: (context, snapshot) {
            return FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.center,
                initialZoom: widget.zoom,
                maxZoom: 18,
                minZoom: 3,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.churchonapp.flutter',
                  tileDisplay: const TileDisplay.fadeIn(),
                ),
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
                    ...widget.markers,
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

        // Current location button
        Positioned(
          right: 16,
          bottom: 80,
          child: _buildFloatingButton(
            icon: LucideIcons.crosshair,
            color: theme.primaryColor,
            onTap: _goToCurrentLocation,
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

  Widget _buildFloatingButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Icon(icon, color: color, size: 22),
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
              color: theme.primaryColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6)],
            ),
            child: Icon(LucideIcons.mapPin, size: 14, color: Colors.white),
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
      color: isBookshop ? Colors.blue : color,
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
            // Pin head — round container with logo/icon
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: widget.color, width: 2.5),
                    ),
                    child: ClipOval(
                      child: (widget.logoUrl != null && widget.logoUrl!.trim().isNotEmpty)
                          ? CachedNetworkImage(imageUrl: widget.logoUrl!, width: 40, height: 40, fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _fallbackIcon())
                          : _fallbackIcon(),
                    ),
                  ),
                ],
              ),
            ),
            // Pin triangle pointer
            Transform.translate(
              offset: const Offset(0, -3),
              child: CustomPaint(
                size: const Size(16, 10),
                painter: _PinTrianglePainter(widget.color),
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
      color: widget.color.withValues(alpha: 0.1),
      child: Icon(widget.isBookshop ? LucideIcons.store : LucideIcons.church, color: widget.color, size: 24),
    );
  }
}

class _PinTrianglePainter extends CustomPainter {
  final Color color;
  _PinTrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final p = ui.Path();
    p.moveTo(size.width / 2, size.height);
    p.lineTo(2, 0);
    p.lineTo(size.width - 2, 0);
    p.close();
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
