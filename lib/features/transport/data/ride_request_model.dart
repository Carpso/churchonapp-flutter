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
  final String negotiationStatus; // 'none','passenger_offered','driver_countered','passenger_countered','accepted'
  final double? negotiatedFare;
  final String paymentStatus; // 'unpaid','pending','paid'
  final String? pickupLabel;
  final String? destLabel;
  final int negotiationRound;
  final String? lastOfferBy;
  final DateTime? proposalExpiresAt;
  final DateTime? cancelledAt;
  final String? cancelledBy;

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
    this.negotiationRound = 0,
    this.lastOfferBy,
    this.proposalExpiresAt,
    this.cancelledAt,
    this.cancelledBy,
  });

  factory RideRequest.fromMap(Map<String, dynamic> map) {
    return RideRequest(
      id: map['id']?.toString() ?? '',
      riderId: map['rider_id']?.toString() ?? '',
      driverId: map['driver_id']?.toString(),
      pickup: LatLng(
        (map['pickup_lat'] as num?)?.toDouble() ?? 0,
        (map['pickup_lng'] as num?)?.toDouble() ?? 0,
      ),
      destination: LatLng(
        (map['dest_lat'] as num?)?.toDouble() ?? 0,
        (map['dest_lng'] as num?)?.toDouble() ?? 0,
      ),
      fare: (map['offered_fare'] as num?)?.toDouble() ?? 0,
      status: map['status']?.toString() ?? 'pending',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      escrowHeld: map['escrow_held'] ?? false,
      negotiationStatus: map['negotiation_status']?.toString() ?? 'none',
      negotiatedFare: map['negotiated_fare'] != null ? (map['negotiated_fare'] as num).toDouble() : null,
      paymentStatus: map['payment_status']?.toString() ?? 'unpaid',
      pickupLabel: map['pickup_label']?.toString(),
      destLabel: map['dest_label']?.toString(),
      negotiationRound: (map['negotiation_round'] as num?)?.toInt() ?? 0,
      lastOfferBy: map['last_offer_by']?.toString(),
      proposalExpiresAt: map['proposal_expires_at'] != null ? DateTime.parse(map['proposal_expires_at']) : null,
      cancelledAt: map['cancelled_at'] != null ? DateTime.parse(map['cancelled_at']) : null,
      cancelledBy: map['cancelled_by']?.toString(),
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
      'negotiation_round': negotiationRound,
      'last_offer_by': lastOfferBy,
      'proposal_expires_at': proposalExpiresAt?.toIso8601String(),
      'cancelled_at': cancelledAt?.toIso8601String(),
      'cancelled_by': cancelledBy,
    };
  }
}

