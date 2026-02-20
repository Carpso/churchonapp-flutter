import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as renderer;
import 'package:lucide_icons/lucide_icons.dart';

class ChurchMap extends StatefulWidget {
  final LatLng center;
  final double zoom;
  final List<Marker> markers;
  final List<LatLng>? path;

  const ChurchMap({
    super.key,
    this.center = const LatLng(-15.3875, 28.3228), // Lusaka
    this.zoom = 14,
    this.markers = const [],
    this.path,
  });

  @override
  State<ChurchMap> createState() => _ChurchMapState();
}

class _ChurchMapState extends State<ChurchMap> {
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.center,
        initialZoom: widget.zoom,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
        ),
        if (widget.path != null && widget.path!.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.path!,
                color: Theme.of(context).primaryColor.withOpacity(0.6),
                strokeWidth: 6,
              ),
              Polyline(
                points: widget.path!,
                color: Colors.white.withOpacity(0.8),
                strokeWidth: 2,
              ),
            ],
          ),
        MarkerLayer(markers: widget.markers),
      ],
    );
  }

  renderer.Theme _getSunflowerVectorTheme() {
    // Custom vector theme to match the Sunflower style (dark with yellow accents)
    return renderer.ThemeReader().read({
      "version": 8,
      "layers": [
        {
          "id": "background",
          "type": "background",
          "paint": {"background-color": "#0f172a"}
        },
        {
          "id": "roads",
          "type": "line",
          "source": "source",
          "source-layer": "transportation",
          "paint": {
            "line-color": "#fbbf24",
            "line-width": 1.0,
            "line-opacity": 0.4
          }
        },
        {
          "id": "water",
          "type": "fill",
          "source": "source",
          "source-layer": "water",
          "paint": {"fill-color": "#1e293b"}
        },
        {
          "id": "building",
          "type": "fill",
          "source": "source",
          "source-layer": "building",
          "paint": {
            "fill-color": "#334155",
            "fill-opacity": 0.2
          }
        }
      ]
    });
  }
}

Marker buildChurchMarker({required LatLng point, required String name, required Color color}) {
  return Marker(
    point: point,
    width: 80,
    height: 80,
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)],
          ),
          child: const Icon(LucideIcons.church, color: Colors.black, size: 24),
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
