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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
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
    };
  }
}

