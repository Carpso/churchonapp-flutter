import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import 'ride_request_model.dart';
import 'delivery_model.dart';
import '../../../core/services/sms_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

class RideRegistration {
  final String id;
  final String userId;
  final String type; // 'driver' or 'rider'
  final String status; // 'available', 'active', 'offline'
  final double lat;
  final double lng;
  final String? vehicleInfo;
  final DateTime updatedAt;

  RideRegistration({
    required this.id,
    required this.userId,
    required this.type,
    required this.status,
    required this.lat,
    required this.lng,
    this.vehicleInfo,
    required this.updatedAt,
  });

  factory RideRegistration.fromMap(Map<String, dynamic> map) {
    return RideRegistration(
      id: map['id'],
      userId: map['user_id'],
      type: map['type'],
      status: map['status'],
      lat: map['lat'],
      lng: map['lng'],
      vehicleInfo: map['vehicle_info'],
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }
}

class TransportService {
  final SupabaseClient _client;
  final Ref _ref;

  TransportService(this._client, this._ref);

  Stream<List<RideRegistration>> getActiveDriversStream() {
    return _client
        .from('ride_registrations')
        .stream(primaryKey: ['id'])
        .eq('type', 'driver')
        .map((data) => data
            .where((map) => map['status'] == 'available')
            .map((map) => RideRegistration.fromMap(map))
            .toList());
  }

  Future<void> updateLocation(double lat, double lng) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('ride_registrations').upsert({
      'user_id': user.id,
      'lat': lat,
      'lng': lng,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<String?> requestRide(LatLng start, LatLng dest, double price) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final request = RideRequest(
      id: const Uuid().v4(),
      riderId: user.id,
      pickup: start,
      destination: dest,
      fare: price,
      status: 'pending',
      createdAt: DateTime.now(),
    );

    await _client.from('ride_requests').insert(request.toMap());
    return request.id;
  }

  Stream<List<RideRequest>> getPendingRidesStream() {
    return _client
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .map((data) => data.map((e) => RideRequest.fromMap(e)).toList());
  }

  Stream<RideRequest?> getMyRideRequestStream() {
    final user = _client.auth.currentUser;
    if (user == null) return Stream.value(null);

    return _client
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('rider_id', user.id)
        .order('created_at', ascending: false)
        .limit(1)
        .map((data) => data.isNotEmpty ? RideRequest.fromMap(data.first) : null);
  }

  Future<void> acceptRide(String requestId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    // 1. Get ride details to find the rider_id
    final rideRes = await _client.from('ride_requests').select('rider_id').eq('id', requestId).single();
    final riderId = rideRes['rider_id'];

    // 2. Accept the ride
    await _client.from('ride_requests').update({
      'driver_id': user.id,
      'status': 'accepted',
    }).eq('id', requestId);

    // 3. Notify the rider via Push
    await _client.from('notifications').insert({
      'user_id': riderId,
      'title': 'Kingdom Driver Found!',
      'body': 'A driver has accepted your ride request and is on the way.',
      'is_read': false,
    });

    // 4. Mission-Critical SMS Alert
    try {
      final riderProfile = await _client.from('profiles').select('full_name, phone_number').eq('id', riderId).single();
      final riderPhone = riderProfile['phone_number'];
      if (riderPhone != null) {
        await _ref.read(smsServiceProvider).sendMissionMatchedAlert(
          riderPhone, 
          "Kingdom Ride", 
          user.userMetadata?['full_name'] ?? 'a Kingdom Driver'
        );
      }
    } catch (e) {
      print("SMS Alert Failed: $e");
    }
  }

  Future<void> updateRideStatus(String requestId, String status) async {
    await _client.from('ride_requests').update({'status': status}).eq('id', requestId);
    
    // Auto-settle if completed
    if (status == 'completed') {
      await _settleRide(requestId);
    }
  }

  Future<void> _settleRide(String requestId) async {
    // 1. Fetch ride details
    final res = await _client.from('ride_requests').select('rider_id, driver_id, offered_fare').eq('id', requestId).single();
    final riderId = res['rider_id'];
    final driverId = res['driver_id'];
    final fare = (res['offered_fare'] as num).toDouble();

    if (driverId == null) return;

    // 2. Transfer Coins
    // Deduct from Rider
    await _updateUserBalance(riderId, -fare);
    // Add to Driver
    await _updateUserBalance(driverId, fare);

    // 3. Log Transaction
    await _client.from('wallet_transactions').insert({
      'user_id': riderId,
      'amount': -fare,
      'type': 'ride_payment',
      'reference_id': requestId,
      'description': 'Payment for Kingdom Ride',
    });

    await _client.from('wallet_transactions').insert({
      'user_id': driverId,
      'amount': fare,
      'type': 'ride_earning',
      'reference_id': requestId,
      'description': 'Earning from Kingdom Ride',
    });
  }

  Future<void> _updateUserBalance(String userId, double delta) async {
    final res = await _client.from('profiles').select('coins').eq('id', userId).single();
    final current = (res['coins'] as num).toDouble();
    await _client.from('profiles').update({'coins': current + delta}).eq('id', userId);
  }

  Stream<LatLng?> watchDriverLocation(String driverId) {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', driverId)
        .map((data) {
          if (data.isEmpty) return null;
          final p = data.first;
          if (p['lat'] != null && p['lng'] != null) {
            return LatLng(p['lat'], p['lng']);
          }
          return null;
        });
  }

  // --- Delivery Logic ---

  Future<String?> requestDelivery({
    required LatLng pickup,
    required LatLng dest,
    required String desc,
    required String category,
    required String weight,
    required double fare,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final request = DeliveryRequest(
      id: const Uuid().v4(),
      senderId: user.id,
      itemDescription: desc,
      itemCategory: category,
      weight: weight,
      pickup: pickup,
      destination: dest,
      fare: fare,
      status: 'pending',
      createdAt: DateTime.now(),
    );

    await _client.from('delivery_requests').insert(request.toMap());
    return request.id;
  }

  Stream<List<DeliveryRequest>> getPendingDeliveriesStream() {
    return _client
        .from('delivery_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .map((data) => data.map((e) => DeliveryRequest.fromMap(e)).toList());
  }

  Future<void> acceptDelivery(String deliveryId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    // 1. Get delivery details for notification
    final res = await _client.from('delivery_requests').select('sender_id').eq('id', deliveryId).single();
    final senderId = res['sender_id'];

    // 2. Assign driver
    await _client.from('delivery_requests').update({
      'driver_id': user.id,
      'status': 'accepted',
    }).eq('id', deliveryId);

    // 3. Notify the sender via Push
    await _client.from('notifications').insert({
      'user_id': senderId,
      'title': 'Courier Found!',
      'body': 'A Kingdom Courier has accepted your cargo mission.',
      'is_read': false,
    });

    // 4. Mission-Critical SMS Alert
    try {
      final senderProfile = await _client.from('profiles').select('full_name, phone_number').eq('id', senderId).single();
      final senderPhone = senderProfile['phone_number'];
      if (senderPhone != null) {
        await _ref.read(smsServiceProvider).sendMissionMatchedAlert(
          senderPhone, 
          "Cargo Mission", 
          user.userMetadata?['full_name'] ?? 'a Kingdom Courier'
        );
      }
    } catch (e) {
      print("SMS Alert Failed: $e");
    }
  }

  Future<void> updateDeliveryStatus(String deliveryId, String status) async {
    await _client.from('delivery_requests').update({'status': status}).eq('id', deliveryId);
    
    // Auto-settle if delivered
    if (status == 'delivered') {
      await _settleDelivery(deliveryId);
    }
  }

  Future<void> _settleDelivery(String deliveryId) async {
    final res = await _client.from('delivery_requests').select('sender_id, driver_id, offered_fare, item_description').eq('id', deliveryId).single();
    final senderId = res['sender_id'];
    final driverId = res['driver_id'];
    final fare = (res['offered_fare'] as num).toDouble();

    if (driverId == null) return;

    // Transfer Coins
    await _updateUserBalance(senderId, -fare);
    await _updateUserBalance(driverId, fare);

    // Log Transaction
    await _client.from('wallet_transactions').insert({
      'user_id': senderId,
      'amount': -fare,
      'type': 'delivery_payment',
      'reference_id': deliveryId,
      'description': 'Payment for Cargo: ${res['item_description']}',
    });

    await _client.from('wallet_transactions').insert({
      'user_id': driverId,
      'amount': fare,
      'type': 'delivery_earning',
      'reference_id': deliveryId,
      'description': 'Earning from Cargo mission',
    });
  }

  Stream<DeliveryRequest?> getMyDeliveryStream() {
    final user = _client.auth.currentUser;
    if (user == null) return const Stream.empty();

    return _client
        .from('delivery_requests')
        .stream(primaryKey: ['id'])
        .eq('sender_id', user.id)
        .order('created_at', ascending: false)
        .limit(1)
        .map((data) => data.isNotEmpty ? DeliveryRequest.fromMap(data.first) : null);
  }
}

final transportServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return TransportService(client, ref);
});

final activeDriversStreamProvider = StreamProvider<List<RideRegistration>>((ref) {
  return ref.watch(transportServiceProvider).getActiveDriversStream();
});

final pendingRidesStreamProvider = StreamProvider<List<RideRequest>>((ref) {
  return ref.watch(transportServiceProvider).getPendingRidesStream();
});

final myRideRequestStreamProvider = StreamProvider<RideRequest?>((ref) {
  return ref.watch(transportServiceProvider).getMyRideRequestStream();
});

final pendingDeliveriesStreamProvider = StreamProvider<List<DeliveryRequest>>((ref) {
  return ref.watch(transportServiceProvider).getPendingDeliveriesStream();
});

final myDeliveryStreamProvider = StreamProvider<DeliveryRequest?>((ref) {
  return ref.watch(transportServiceProvider).getMyDeliveryStream();
});

