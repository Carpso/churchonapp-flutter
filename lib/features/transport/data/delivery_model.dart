import 'package:latlong2/latlong.dart';

class DeliveryRequest {
  final String id;
  final String senderId;
  final String? driverId;
  final String itemDescription;
  final String itemCategory; // 'marketplace', 'parcel', 'cargo'
  final String weight; // 'Light', 'Medium', 'Heavy'
  final LatLng pickup;
  final LatLng destination;
  final double fare;
  final String status; // 'pending', 'accepted', 'assigned', 'in_transit', 'delivered', 'cancelled'
  final DateTime createdAt;
  final String? vendorPhone;
  final String? vendorName;
  final double? itemPrice;
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

  DeliveryRequest({
    required this.id,
    required this.senderId,
    this.driverId,
    required this.itemDescription,
    required this.itemCategory,
    required this.weight,
    required this.pickup,
    required this.destination,
    required this.fare,
    required this.status,
    required this.createdAt,
    this.vendorPhone,
    this.vendorName,
    this.itemPrice,
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

  factory DeliveryRequest.fromMap(Map<String, dynamic> map) {
    return DeliveryRequest(
      id: map['id'],
      senderId: map['sender_id'],
      driverId: map['driver_id'],
      itemDescription: map['item_description'],
      itemCategory: map['item_category'],
      weight: map['weight'],
      pickup: LatLng(map['pickup_lat'], map['pickup_lng']),
      destination: LatLng(map['dest_lat'], map['dest_lng']),
      fare: (map['offered_fare'] as num).toDouble(),
      status: map['status'],
      createdAt: DateTime.parse(map['created_at']),
      vendorPhone: map['vendor_phone'],
      vendorName: map['vendor_name'],
      itemPrice: map['item_price'] != null ? (map['item_price'] as num).toDouble() : null,
      negotiationStatus: map['negotiation_status'] ?? 'none',
      negotiatedFare: map['negotiated_fare'] != null ? (map['negotiated_fare'] as num).toDouble() : null,
      paymentStatus: map['payment_status'] ?? 'unpaid',
      pickupLabel: map['pickup_label'],
      destLabel: map['dest_label'],
      negotiationRound: (map['negotiation_round'] as num?)?.toInt() ?? 0,
      lastOfferBy: map['last_offer_by'],
      proposalExpiresAt: map['proposal_expires_at'] != null ? DateTime.parse(map['proposal_expires_at']) : null,
      cancelledAt: map['cancelled_at'] != null ? DateTime.parse(map['cancelled_at']) : null,
      cancelledBy: map['cancelled_by'],
    );
  }

  double get currentFare => negotiatedFare ?? fare;

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'sender_id': senderId,
      'driver_id': driverId,
      'item_description': itemDescription,
      'item_category': itemCategory,
      'weight': weight,
      'pickup_lat': pickup.latitude,
      'pickup_lng': pickup.longitude,
      'dest_lat': destination.latitude,
      'dest_lng': destination.longitude,
      'offered_fare': fare,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'vendor_phone': vendorPhone,
      'vendor_name': vendorName,
      'item_price': itemPrice,
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

