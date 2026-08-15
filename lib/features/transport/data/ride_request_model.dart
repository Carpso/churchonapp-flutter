import 'package:latlong2/latlong.dart';

class RideRequest {
  final String id;
  final String riderId;
  final String? driverId;
  final LatLng pickup;
  final LatLng destination;
  final double fare;
  final String status; // 'pending', 'accepted', 'confirmed', 'completed', 'cancelled'
  final DateTime createdAt;
  final bool escrowHeld;
  final String negotiationStatus; // 'none','passenger_offered','driver_countered','accepted'
  final double? negotiatedFare;
  final String paymentStatus; // 'unpaid','pending','paid'
  final String? pickupLabel;
  final String? destLabel;

  RideRequest({
    required this.id,
    required this.riderId,
    this.driverId,
    required this.pickup,
    required this.destination,
    required this.fare,
    required this.status,
    required this.createdAt,
    this.escrowHeld = false,
    this.negotiationStatus = 'none',
    this.negotiatedFare,
    this.paymentStatus = 'unpaid',
    this.pickupLabel,
    this.destLabel,
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
      escrowHeld: map['escrow_held'] ?? false,
      negotiationStatus: map['negotiation_status'] ?? 'none',
      negotiatedFare: map['negotiated_fare'] != null ? (map['negotiated_fare'] as num).toDouble() : null,
      paymentStatus: map['payment_status'] ?? 'unpaid',
      pickupLabel: map['pickup_label'],
      destLabel: map['dest_label'],
    );
  }

  double get currentFare => negotiatedFare ?? fare;

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'rider_id': riderId,
      'driver_id': driverId,
      'pickup_lat': pickup.latitude,
      'pickup_lng': pickup.longitude,
      'dest_lat': destination.latitude,
      'dest_lng': destination.longitude,
      'offered_fare': fare,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'escrow_held': escrowHeld,
      'negotiation_status': negotiationStatus,
      'negotiated_fare': negotiatedFare,
      'payment_status': paymentStatus,
      'pickup_label': pickupLabel,
      'dest_label': destLabel,
    };
  }
}

