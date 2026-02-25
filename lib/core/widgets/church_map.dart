import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as renderer;
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ChurchMap extends StatefulWidget {
  final LatLng center;
  final double zoom;
  final List<Marker> markers;
  final List<LatLng>? path;
  final bool darkMode;

  const ChurchMap({
    super.key,
    this.center = const LatLng(-15.3875, 28.3228),
    this.zoom = 14,
    this.markers = const [],
    this.path,
    this.darkMode = false,
  });

  @override
  State<ChurchMap> createState() => _ChurchMapState();
}

class _ChurchMapState extends State<ChurchMap> {
  final MapController _mapController = MapController();
  late final String _pmtilesUrl;

  @override
  void initState() {
    super.initState();
    // Use Zambia as default, can be dynamic based on user location
    _pmtilesUrl = dotenv.get('MAPS_ZAMBIA_URL');
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.center,
        initialZoom: widget.zoom,
        maxZoom: 18,
        minZoom: 3,
      ),
      children: [
        // OpenStreetMap tile layer - shows real streets, buildings, locations
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.churchonapp.church_on_app',
          maxZoom: 18,
        ),
        
        // Route polyline
        if (widget.path != null && widget.path!.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.path!,
                color: Theme.of(context).primaryColor,
                strokeWidth: 5,
                borderColor: Colors.white,
                borderStrokeWidth: 2,
              ),
            ],
          ),
        // Markers
        MarkerLayer(markers: widget.markers),
      ],
    );
  }
}

Marker buildChurchMarker({
  required LatLng point, 
  required String name, 
  required Color color, 
  String? logoUrl,
  VoidCallback? onTap,
}) {
  return Marker(
    point: point,
    width: 100,
    height: 100,
    child: GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)],
              border: Border.all(color: color, width: 2),
            ),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white,
              backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
              child: logoUrl == null ? Icon(LucideIcons.church, color: color, size: 20) : null,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}


Marker buildRideMarker({required LatLng point, required Color color}) {
  return Marker(
    point: point,
    width: 50,
    height: 50,
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)],
      ),
      child: const Icon(LucideIcons.car, color: Colors.black, size: 20),
    ),
  );
}

Marker buildUserMarker({required LatLng point}) {
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
            color: Colors.blue.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ],
    ),
  );
}

Marker buildBusStopMarker({required LatLng point, required String name}) {
  return Marker(
    point: point,
    width: 80,
    height: 80,
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 8)],
          ),
          child: const Icon(LucideIcons.bus, color: Colors.white, size: 16),
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
            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

