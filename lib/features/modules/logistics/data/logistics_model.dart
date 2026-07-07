import 'package:latlong2/latlong.dart';

class BusInfo {
  final String id;
  final String name;
  final String route;
  final String eta;
  final String nextStop;
  final List<LatLng> path;
  final List<BusStop> stops;

  BusInfo({
    required this.id,
    required this.name,
    required this.route,
    required this.eta,
    required this.nextStop,
    this.path = const [],
    this.stops = const [],
  });
}

class BusStop {
  final String name;
  final LatLng position;

  const BusStop({required this.name, required this.position});
}

class TrafficAlert {
  final String road;
  final String description;
  final String status;
  final String severity;

  TrafficAlert({
    required this.road,
    required this.description,
    required this.status,
    required this.severity,
  });
}

class ParkingZone {
  final String name;
  final int available;
  final int total;
  final String status;

  ParkingZone({
    required this.name,
    required this.available,
    required this.total,
  }) : status = available == 0 ? 'FULL' : available < 5 ? 'LOW' : 'OPEN';

  bool get isFull => available == 0;
  bool get isLow => available < 5 && available > 0;
}

class QuickRoute {
  final String title;
  final String time;
  final String via;
  final String iconName;

  QuickRoute({
    required this.title,
    required this.time,
    required this.via,
    this.iconName = 'home',
  });
}
