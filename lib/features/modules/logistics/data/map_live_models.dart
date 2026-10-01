import 'package:latlong2/latlong.dart';

/// ── Stream audience ────────────────────────────────────────────────────────
/// One person watching = one viewer, even across two devices.
class StreamWatcher {
  const StreamWatcher({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.role,
    this.joinedAt,
    this.watchedSeconds = 0,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final String? role;
  final DateTime? joinedAt;
  final int watchedSeconds;

  factory StreamWatcher.fromJson(Map<String, dynamic> j) => StreamWatcher(
        userId: j['user_id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'Member',
        avatarUrl: j['avatar_url']?.toString(),
        role: j['role']?.toString(),
        joinedAt: DateTime.tryParse(j['joined_at']?.toString() ?? ''),
        watchedSeconds: (j['watched_seconds'] as num?)?.toInt() ?? 0,
      );

  String get watchedLabel {
    if (watchedSeconds < 60) return '${watchedSeconds}s';
    final m = watchedSeconds ~/ 60;
    if (m < 60) return '${m}m';
    return '${m ~/ 60}h ${m % 60}m';
  }
}

class StreamAudience {
  const StreamAudience({
    this.viewersNow = 0,
    this.streamedMinutes,
    this.watchers = const [],
  });

  final int viewersNow;
  final double? streamedMinutes;
  final List<StreamWatcher> watchers;

  bool get isEmpty => viewersNow == 0;

  factory StreamAudience.fromJson(Map<String, dynamic> j) => StreamAudience(
        viewersNow: (j['viewers_now'] as num?)?.toInt() ?? 0,
        streamedMinutes: (j['streamed_minutes'] as num?)?.toDouble(),
        watchers: ((j['watchers'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(StreamWatcher.fromJson)
            .toList(),
      );

  static const empty = StreamAudience();
}

/// ── Live bus position ──────────────────────────────────────────────────────
class LiveBus {
  const LiveBus({
    required this.busId,
    required this.name,
    this.route,
    this.eta,
    this.nextStop,
    this.position,
    this.heading,
    this.speedKmh,
    this.recordedAt,
    this.isStale = false,
    this.isActive = true,
  });

  final String busId;
  final String name;
  final String? route;
  final String? eta;
  final String? nextStop;
  final LatLng? position;
  final double? heading;
  final double? speedKmh;
  final DateTime? recordedAt;

  /// No ping for 3+ minutes — the vehicle is not reporting, so we say so
  /// instead of drawing a marker at its last known spot as if it were live.
  final bool isStale;
  final bool isActive;

  /// A bus we can actually put on the map.
  bool get hasLiveFix => position != null && !isStale;

  factory LiveBus.fromJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble();
    final lng = (j['lng'] as num?)?.toDouble();
    return LiveBus(
      busId: j['bus_id']?.toString() ?? j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? 'Bus',
      route: j['route']?.toString(),
      eta: j['eta']?.toString(),
      nextStop: j['next_stop']?.toString(),
      position: (lat != null && lng != null) ? LatLng(lat, lng) : null,
      heading: (j['heading'] as num?)?.toDouble(),
      speedKmh: (j['speed_kmh'] as num?)?.toDouble(),
      recordedAt: DateTime.tryParse(j['recorded_at']?.toString() ?? ''),
      isStale: j['stale'] == true,
      isActive: j['is_active'] != false,
    );
  }

  String get statusLabel {
    if (!isActive) return 'OFF DUTY';
    if (position == null) return 'NOT REPORTING';
    if (isStale) return 'SIGNAL LOST';
    return 'ON ROUTE';
  }
}

/// ── Traffic ────────────────────────────────────────────────────────────────
class MapTrafficSegment {
  const MapTrafficSegment({
    required this.position,
    required this.condition,
    required this.avgSpeed,
    required this.samples,
  });

  final LatLng position;

  /// clear | moderate | heavy | unknown
  final String condition;
  final double avgSpeed;
  final int samples;

  /// No data is NOT "clear" — it is unknown, and we label it as such.
  bool get isUnknown => condition == 'unknown';

  factory MapTrafficSegment.fromJson(Map<String, dynamic> j) => MapTrafficSegment(
        position: LatLng(
          (j['lat'] as num?)?.toDouble() ?? 0,
          (j['lng'] as num?)?.toDouble() ?? 0,
        ),
        condition: j['condition']?.toString() ?? 'unknown',
        avgSpeed: (j['avg_speed'] as num?)?.toDouble() ?? 0,
        samples: (j['samples'] as num?)?.toInt() ?? 0,
      );
}

class TrafficIncident {
  const TrafficIncident({
    required this.id,
    required this.road,
    required this.description,
    required this.status,
    required this.severity,
    this.position,
    this.radiusM = 500,
    this.createdAt,
  });

  final String id;
  final String road;
  final String description;
  final String status;
  final String severity;
  final LatLng? position;
  final int radiusM;
  final DateTime? createdAt;

  bool get hasPosition => position != null;

  factory TrafficIncident.fromJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble();
    final lng = (j['lng'] as num?)?.toDouble();
    return TrafficIncident(
      id: j['id']?.toString() ?? '',
      road: j['road']?.toString() ?? '',
      description: j['description']?.toString() ?? '',
      status: j['status']?.toString() ?? 'Unknown',
      severity: j['severity']?.toString() ?? 'low',
      position: (lat != null && lng != null) ? LatLng(lat, lng) : null,
      radiusM: (j['radius_m'] as num?)?.toInt() ?? 500,
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
    );
  }
}

/// ── Parking ────────────────────────────────────────────────────────────────
class ParkingArea {
  const ParkingArea({
    required this.id,
    required this.name,
    required this.available,
    required this.total,
    this.position,
    this.zoneType,
    this.feeKwacha = 0,
    this.updatedAt,
  });

  final String id;
  final String name;
  final int available;
  final int total;
  final LatLng? position;
  final String? zoneType;
  final double feeKwacha;
  final DateTime? updatedAt;

  bool get hasPosition => position != null;
  bool get isFull => available <= 0;
  double get occupancy => total <= 0 ? 0 : (1 - (available / total)).clamp(0, 1);

  String get statusLabel {
    if (total <= 0) return 'UNKNOWN';
    if (available <= 0) return 'FULL';
    if (available < 5) return 'ALMOST FULL';
    return 'OPEN';
  }

  factory ParkingArea.fromJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble();
    final lng = (j['lng'] as num?)?.toDouble();
    return ParkingArea(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? 'Parking',
      available: (j['available'] as num?)?.toInt() ?? 0,
      total: (j['total'] as num?)?.toInt() ?? 0,
      position: (lat != null && lng != null) ? LatLng(lat, lng) : null,
      zoneType: j['zone_type']?.toString(),
      feeKwacha: (j['fee_kwacha'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.tryParse(j['updated_at']?.toString() ?? ''),
    );
  }
}

/// ── Quick routes ───────────────────────────────────────────────────────────
class SavedQuickRoute {
  const SavedQuickRoute({
    required this.id,
    required this.title,
    this.time,
    this.via,
    this.iconName = 'home',
    this.fromLabel,
    this.toLabel,
    this.fromPosition,
    this.toPosition,
  });

  final String id;
  final String title;
  final String? time;
  final String? via;
  final String iconName;
  final String? fromLabel;
  final String? toLabel;
  final LatLng? fromPosition;
  final LatLng? toPosition;

  /// Only a route with two real endpoints can actually be navigated.
  bool get isRoutable => fromPosition != null && toPosition != null;

  factory SavedQuickRoute.fromJson(Map<String, dynamic> j) {
    final flat = (j['from_lat'] as num?)?.toDouble();
    final flng = (j['from_lng'] as num?)?.toDouble();
    final tlat = (j['to_lat'] as num?)?.toDouble();
    final tlng = (j['to_lng'] as num?)?.toDouble();
    return SavedQuickRoute(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? 'Route',
      time: j['time']?.toString(),
      via: j['via']?.toString(),
      iconName: j['icon']?.toString() ?? 'home',
      fromLabel: j['from_label']?.toString(),
      toLabel: j['to_label']?.toString(),
      fromPosition: (flat != null && flng != null) ? LatLng(flat, flng) : null,
      toPosition: (tlat != null && tlng != null) ? LatLng(tlat, tlng) : null,
    );
  }
}
