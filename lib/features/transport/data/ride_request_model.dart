import 'package:latlong2/latlong.dart';

class RideRequest {
  final String id;
  final String riderId;
  final String? driverId;
  final LatLng pickup;
  final LatLng destination;
  final double fare;
  final String status; // 'pending', 'accepted', 'active', 'completed', 'cancelled'
  final DateTime createdAt;

  RideRequest({
    required this.id,
    required this.riderId,
    this.driverId,
    required this.pickup,
    required this.destination,
    required this.fare,
    required this.status,
    required this.createdAt,
  });

  factory RideRequest.fromMap(Map<String, dynamic> map) {
    return RideRequest(
      id: map['id'],
      riderId: map['rider_id'],
      driverId: map['driver_id'],
      pickup: LatLng(map['pickup_lat'], map['pickup_lng']),
      destination: LatLng(map['dest_lat'], map['dest_lng']),
      fare: (map['offered_fare'] as num).toDouble(),
      status: map['status'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'rider_id': riderId,
      'driver_id': driverId,
      'pickup_lat': pickup.latitude,
      'pickup_lng': pickup.longitude,
      'dest_lat': destination.latitude,
      'dest_lng': destination.longitude,
      'offered_fare': fare,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

