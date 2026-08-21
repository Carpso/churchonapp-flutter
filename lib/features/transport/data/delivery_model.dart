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
      id: map['id']?.toString() ?? '',
      senderId: map['sender_id']?.toString() ?? '',
      driverId: map['driver_id']?.toString(),
      itemDescription: map['item_description']?.toString() ?? '',
      itemCategory: map['item_category']?.toString() ?? 'parcel',
      weight: map['weight']?.toString() ?? 'Light',
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
      vendorPhone: map['vendor_phone']?.toString(),
      vendorName: map['vendor_name']?.toString(),
      itemPrice: map['item_price'] != null ? (map['item_price'] as num).toDouble() : null,
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

