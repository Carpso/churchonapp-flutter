import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import 'ride_request_model.dart';
import 'delivery_model.dart';
import '../../../core/services/sms_service.dart';
import '../../../core/config/env.dart';
import '../../../core/config/fee_config.dart';
import '../../../core/config/remote_config.dart';
import 'package:latlong2/latlong.dart';

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

  /// Match nearest available driver weighted by rating and distance score.
  Future<Map<String, dynamic>?> findNearestWeightedDriver({
    required LatLng pickupLocation,
    double searchRadiusKm = 10.0,
  }) async {
    try {
      final drivers = await _client
          .from('driver_locations')
          .select('*, profiles!driver_locations_driver_id_fkey(rating)')
          .eq('is_online', true);

      if (drivers.isEmpty) return null;

      Map<String, dynamic>? bestDriver;
      double maxScore = -999999.0;

      for (var d in drivers) {
        final lat = (d['lat'] as num?)?.toDouble() ?? 0.0;
        final lng = (d['lng'] as num?)?.toDouble() ?? 0.0;
        final distanceKm = const Distance().as(
          LengthUnit.Kilometer,
          pickupLocation,
          LatLng(lat, lng),
        );

        if (distanceKm > searchRadiusKm) continue;

        final profile = d['profiles'] as Map<String, dynamic>?;
        final rating = (profile?['rating'] as num?)?.toDouble() ?? 4.5;

        // Score formula: Rating weight (40%) vs Distance penalty (60%)
        final score = (rating * 0.4) - (distanceKm * 0.6);

        if (score > maxScore) {
          maxScore = score;
          bestDriver = {...d, 'distance_km': distanceKm, 'score': score};
        }
      }

      return bestDriver;
    } catch (e) {
      debugPrint('Error matching weighted driver: $e');
      return null;
    }
  }

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

  Future<String?> requestRide(LatLng start, LatLng dest, double price,
      {String? pickupLabel, String? destLabel}) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final request = RideRequest(
      id: '',
      riderId: user.id,
      pickup: start,
      destination: dest,
      fare: price,
      status: 'pending',
      createdAt: DateTime.now(),
      pickupLabel: pickupLabel,
      destLabel: destLabel,
    );

    final inserted = await _client
        .from('ride_requests')
        .insert(request.toMap())
        .select('id')
        .single();
    return inserted['id'] as String?;
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

  Future<bool> acceptRide(String requestId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    // Atomic accept: only succeed if ride is still pending (prevents double-book)
    final result = await _client
        .from('ride_requests')
        .update({
          'driver_id': user.id,
          'status': 'accepted',
          'negotiation_status': 'accepted',
          'fare_locked_at': DateTime.now().toIso8601String(),
          'last_offer_by': null,
        })
        .eq('id', requestId)
        .eq('status', 'pending')
        .select('rider_id')
        .maybeSingle();

    if (result == null) {
      debugPrint("transport_service: Ride $requestId already taken by another driver");
      return false;
    }

    final riderId = result['rider_id'];

    // Notify the rider via Push
    await _client.from('notifications').insert({
      'user_id': riderId,
      'title': 'Driver Found!',
      'body': 'A driver accepted your request at K${_rideFareLabel(requestId)}. Confirm payment to start the trip.',
      'is_read': false,
    });

    // 4. Mission-Critical SMS Alert
    try {
      final riderProfile = await _client.from('profiles').select('full_name, phone_number').eq('id', riderId).single();
      final riderPhone = riderProfile['phone_number'];
      if (riderPhone != null) {
        await _ref.read(smsServiceProvider).sendMissionMatchedAlert(
          riderPhone, 
          "Ride", 
          user.userMetadata?['full_name'] ?? 'a Driver'
        );
      }
    } catch (e) {
      debugPrint("transport_service: SMS Alert Failed: $e");
    }
    return true;
  }

  Future<String> _rideFareLabel(String requestId) async {
    try {
      final res = await _client.from('ride_requests').select('offered_fare, negotiated_fare').eq('id', requestId).maybeSingle();
      final fare = res?['negotiated_fare'] ?? res?['offered_fare'];
      return (fare as num?)?.toStringAsFixed(0) ?? '--';
    } catch (_) {
      return '--';
    }
  }

  // ── Fare negotiation (passenger ↔ driver) ──

  /// Passenger submits a fare offer (below estimated price).
  Future<void> submitFareOffer(String requestId, double offer) async {
    await _client.from('ride_requests').update({
      'negotiated_fare': offer,
      'negotiation_status': 'passenger_offered',
    }).eq('id', requestId);
  }

  /// How long a fare proposal stays open before it lapses (remote-tunable).
  Duration _negotiationTimeout() =>
      Duration(seconds: currentRemoteConfig(_ref).getInt('ride_negotiation_timeout_sec', 120));

  /// Reads the current negotiation round and returns the next one.
  Future<int> _nextNegotiationRound(String table, String id) async {
    try {
      final res = await _client
          .from(table)
          .select('negotiation_round')
          .eq('id', id)
          .maybeSingle();
      return ((res?['negotiation_round'] as num?)?.toInt() ?? 0) + 1;
    } catch (e) {
      debugPrint("transport_service: round read failed: $e");
      return 1;
    }
  }

  /// Driver counters with a different fare (notifies the passenger).
  Future<void> counterFare(String requestId, double counter) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final res = await _client
        .from('ride_requests')
        .select('rider_id')
        .eq('id', requestId)
        .single();
    final round = await _nextNegotiationRound('ride_requests', requestId);
    await _client.from('ride_requests').update({
      'negotiated_fare': counter,
      'negotiation_status': 'driver_countered',
      'negotiation_round': round,
      'last_offer_by': user.id,
      'proposal_expires_at': DateTime.now().add(_negotiationTimeout()).toIso8601String(),
    }).eq('id', requestId).eq('status', 'pending');
    try {
      await _client.from('notifications').insert({
        'user_id': res['rider_id'],
        'title': 'New Fare Offer',
        'body': 'The driver counter-offered K${counter.toStringAsFixed(0)}. Accept, decline or counter to continue.',
        'is_read': false,
      });
    } catch (e) {
      debugPrint("transport_service: counter notification failed: $e");
    }
  }

  /// Passenger counters the driver's offer (inDrive-style back-and-forth).
  /// Drivers see the counter in their portal as 'passenger_countered'.
  Future<void> passengerCounterFare(String requestId, double counter) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final round = await _nextNegotiationRound('ride_requests', requestId);
    await _client.from('ride_requests').update({
      'negotiated_fare': counter,
      'negotiation_status': 'passenger_countered',
      'negotiation_round': round,
      'last_offer_by': user.id,
      'proposal_expires_at': DateTime.now().add(_negotiationTimeout()).toIso8601String(),
    }).eq('id', requestId).eq('status', 'pending');
  }

  /// Passenger accepts the driver's counter-offer → locks fare and accepts ride.
  Future<void> acceptCounterOffer(String requestId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('ride_requests').update({
      'status': 'accepted',
      'negotiation_status': 'accepted',
      'fare_locked_at': DateTime.now().toIso8601String(),
      'last_offer_by': null,
    }).eq('id', requestId).eq('negotiation_status', 'driver_countered');
  }

  /// Driver accepts the passenger's counter-offer at the agreed fare.
  /// Atomic: only succeeds while the request is still pending.
  Future<bool> acceptPassengerCounter(String requestId) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final result = await _client
        .from('ride_requests')
        .update({
          'driver_id': user.id,
          'status': 'accepted',
          'negotiation_status': 'accepted',
          'fare_locked_at': DateTime.now().toIso8601String(),
          'last_offer_by': null,
        })
        .eq('id', requestId)
        .eq('status', 'pending')
        .eq('negotiation_status', 'passenger_countered')
        .select('rider_id')
        .maybeSingle();
    if (result == null) return false;
    try {
      await _client.from('notifications').insert({
        'user_id': result['rider_id'],
        'title': 'Driver Found!',
        'body': 'A driver accepted your fare. Confirm payment to start the trip.',
        'is_read': false,
      });
    } catch (e) {
      debugPrint("transport_service: accept passenger counter notification failed: $e");
    }
    return true;
  }

  /// Passenger declines the counter-offer, resets to pending.
  Future<void> declineCounterOffer(String requestId) async {
    await _client.from('ride_requests').update({
      'negotiation_status': 'none',
      'negotiated_fare': null,
      'last_offer_by': null,
    }).eq('id', requestId).eq('negotiation_status', 'driver_countered');
  }

  /// Passenger cancels their own pending request.
  Future<void> cancelRide(String requestId) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    await _client.from('ride_requests').update({
      'status': 'cancelled',
      'cancelled_at': DateTime.now().toIso8601String(),
      'cancelled_by': user.id,
    }).eq('id', requestId).eq('status', 'pending');
  }

  /// Passenger paid — store the Lipila anchor + mark the ride paid.
  Future<void> confirmRidePayment(String requestId, String txId) async {
    await _client.from('ride_requests').update({
      'payment_ref': txId,
      'payment_status': 'paid',
      'paid_at': DateTime.now().toIso8601String(),
    }).eq('id', requestId);
    try {
      final res = await _client
          .from('ride_requests')
          .select('driver_id')
          .eq('id', requestId)
          .single();
      if (res['driver_id'] != null) {
        await _client.from('notifications').insert({
          'user_id': res['driver_id'],
          'title': 'Payment Confirmed',
          'body': 'The passenger has paid for the ride. Head to the pickup point!',
          'is_read': false,
        });
      }
    } catch (e) {
      debugPrint("transport_service: driver payment notification failed: $e");
    }
  }

  // ── Delivery negotiation + payment ──

  /// Driver counters a delivery fare (notifies the sender).
  Future<void> counterDeliveryFare(String deliveryId, double counter) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final res = await _client
        .from('delivery_requests')
        .select('sender_id')
        .eq('id', deliveryId)
        .single();
    final round = await _nextNegotiationRound('delivery_requests', deliveryId);
    await _client.from('delivery_requests').update({
      'negotiated_fare': counter,
      'negotiation_status': 'driver_countered',
      'negotiation_round': round,
      'last_offer_by': user.id,
      'proposal_expires_at': DateTime.now().add(_negotiationTimeout()).toIso8601String(),
    }).eq('id', deliveryId).eq('status', 'pending');
    try {
      await _client.from('notifications').insert({
        'user_id': res['sender_id'],
        'title': 'New Cargo Fare Offer',
        'body': 'The courier counter-offered K${counter.toStringAsFixed(0)}. Accept, decline or counter to continue.',
        'is_read': false,
      });
    } catch (e) {
      debugPrint("transport_service: delivery counter notification failed: $e");
    }
  }

  /// Sender counters the courier's offer (inDrive-style back-and-forth).
  Future<void> senderCounterFare(String deliveryId, double counter) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final round = await _nextNegotiationRound('delivery_requests', deliveryId);
    await _client.from('delivery_requests').update({
      'negotiated_fare': counter,
      'negotiation_status': 'passenger_countered',
      'negotiation_round': round,
      'last_offer_by': user.id,
      'proposal_expires_at': DateTime.now().add(_negotiationTimeout()).toIso8601String(),
    }).eq('id', deliveryId).eq('status', 'pending');
  }

  /// Sender accepts the courier's counter-offer → locks fare and accepts.
  Future<void> acceptDeliveryCounterOffer(String deliveryId) async {
    await _client.from('delivery_requests').update({
      'status': 'accepted',
      'negotiation_status': 'accepted',
      'fare_locked_at': DateTime.now().toIso8601String(),
      'last_offer_by': null,
    }).eq('id', deliveryId).eq('negotiation_status', 'driver_countered');
  }

  /// Courier accepts the sender's counter-offer at the agreed fare.
  /// Atomic: only succeeds while the delivery is still pending.
  Future<bool> acceptSenderCounter(String deliveryId) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final result = await _client
        .from('delivery_requests')
        .update({
          'driver_id': user.id,
          'status': 'accepted',
          'negotiation_status': 'accepted',
          'fare_locked_at': DateTime.now().toIso8601String(),
          'last_offer_by': null,
        })
        .eq('id', deliveryId)
        .eq('status', 'pending')
        .eq('negotiation_status', 'passenger_countered')
        .select('sender_id')
        .maybeSingle();
    if (result == null) return false;
    try {
      await _client.from('notifications').insert({
        'user_id': result['sender_id'],
        'title': 'Courier Found!',
        'body': 'A courier accepted your fare. Confirm payment to start.',
        'is_read': false,
      });
    } catch (e) {
      debugPrint("transport_service: accept sender counter notification failed: $e");
    }
    return true;
  }

  /// Sender declines the counter-offer, resets to pending.
  Future<void> declineDeliveryCounterOffer(String deliveryId) async {
    await _client.from('delivery_requests').update({
      'negotiation_status': 'none',
      'negotiated_fare': null,
      'last_offer_by': null,
    }).eq('id', deliveryId).eq('negotiation_status', 'driver_countered');
  }

  /// Sender cancels their own pending delivery request.
  Future<void> cancelDelivery(String deliveryId) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    await _client.from('delivery_requests').update({
      'status': 'cancelled',
      'cancelled_at': DateTime.now().toIso8601String(),
      'cancelled_by': user.id,
    }).eq('id', deliveryId).eq('status', 'pending');
  }

  /// Sender paid — store the Lipila anchor + mark the delivery paid.
  Future<void> confirmDeliveryPayment(String deliveryId, String txId) async {
    await _client.from('delivery_requests').update({
      'payment_ref': txId,
      'payment_status': 'paid',
      'paid_at': DateTime.now().toIso8601String(),
    }).eq('id', deliveryId);
    try {
      final res = await _client
          .from('delivery_requests')
          .select('driver_id')
          .eq('id', deliveryId)
          .single();
      if (res['driver_id'] != null) {
        await _client.from('notifications').insert({
          'user_id': res['driver_id'],
          'title': 'Payment Confirmed',
          'body': 'The sender has paid for the cargo mission. Head to the pickup point!',
          'is_read': false,
        });
      }
    } catch (e) {
      debugPrint("transport_service: courier payment notification failed: $e");
    }
  }

  /// Driver's accepted requests that the passenger has NOT paid yet.
  Stream<List<RideRequest>> getMyAcceptedRidesStream() {
    final user = _client.auth.currentUser;
    if (user == null) return const Stream.empty();
    return _client
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('driver_id', user.id)
        .map((data) => data
            .where((e) => e['status'] == 'accepted')
            .map((e) => RideRequest.fromMap(e))
            .toList());
  }

  /// Couriers' accepted deliveries that the sender has NOT paid yet.
  Stream<List<DeliveryRequest>> getMyAcceptedDeliveriesStream() {
    final user = _client.auth.currentUser;
    if (user == null) return const Stream.empty();
    return _client
        .from('delivery_requests')
        .stream(primaryKey: ['id'])
        .eq('driver_id', user.id)
        .map((data) => data
            .where((e) => e['status'] == 'accepted')
            .map((e) => DeliveryRequest.fromMap(e))
            .toList());
  }

  Future<void> updateRideStatus(String requestId, String status) async {
    await _client.from('ride_requests').update({'status': status}).eq('id', requestId);
    
    // Auto-settle if completed
    if (status == 'completed') {
      await _settleRide(requestId);
    }
  }

  /// Business commission cut percent — read from remote FeeConfig (10% default).
  double get _businessCutPercent =>
      _ref.read(feeConfigProvider).value?.businessCutPercent ?? 0.10;

  Future<void> _settleRide(String requestId) async {
    // 1. Fetch ride details
    final res = await _client
        .from('ride_requests')
        .select('rider_id, driver_id, offered_fare, negotiated_fare, payment_status')
        .eq('id', requestId)
        .single();
    final riderId = res['rider_id'];
    final driverId = res['driver_id'];
    final fare = ((res['negotiated_fare'] ?? res['offered_fare']) as num).toDouble();

    if (driverId == null) return;
    // Never settle a ride the passenger has not paid for.
    if ((res['payment_status'] ?? 'unpaid') != 'paid') {
      debugPrint("transport_service: ride $requestId not paid — skipping settlement");
      return;
    }

    final cutPercent = _businessCutPercent;
    final platformCut = fare * cutPercent;
    final netEarning = fare - platformCut;

    // Update ride request with platform fee
    await _client.from('ride_requests').update({
      'platform_fee': platformCut,
    }).eq('id', requestId);

    // 3. Log Transactions
    await _client.from('wallet_transactions').insert({
      'user_id': riderId,
      'amount': -fare,
      'type': 'ride_payment',
      'reference_id': requestId,
      'description': 'Payment for Ride (${(cutPercent * 100).toStringAsFixed(0)}% platform cut applied)',
      'platform_fee': platformCut,
    });

    await _client.from('wallet_transactions').insert({
      'user_id': driverId,
      'amount': netEarning,
      'type': 'ride_earning',
      'reference_id': requestId,
      'description': 'Earning from Ride (${(cutPercent * 100).toStringAsFixed(0)}% platform cut applied)',
      'platform_fee': platformCut,
    });

    await _client.from('wallet_transactions').insert({
      'user_id': Env.treasuryId,
      'amount': platformCut,
      'type': 'platform_cut_revenue',
      'reference_id': requestId,
      'description': 'Platform revenue cut from ride request $requestId',
      'platform_fee': 0.0,
    });

    // 4. Enqueue SERVER-SIDE settlement for the driver.
    // The settlement engine (webhook/lps-settle cron) pays the ride's recorded
    // driver from ride_requests.offered_fare, applying fees server-side. The
    // client can no longer move money directly.
    try {
      await _client.rpc('enqueue_payout_task', params: {
        'p_source': 'ride',
        'p_source_ref': requestId,
        'p_payment_ref': null,
        'p_recipient_user_id': null,
        'p_recipient_phone': '',
        'p_gross_amount': netEarning,
      });
    } catch (e) {
      debugPrint("transport_service: Driver settlement enqueue failed: $e");
    }

    // 5. Enqueue the PLATFORM cut payout. The settlement engine disburses it
    // to the number set by superadmin/coa_employee (platform_settings
    // ride_payout_mobile). Tenants never access ride money.
    try {
      await _client.rpc('enqueue_payout_task', params: {
        'p_source': 'ride_cut',
        'p_source_ref': requestId,
        'p_payment_ref': null,
        'p_recipient_user_id': null,
        'p_recipient_phone': '',
        'p_gross_amount': platformCut,
      });
    } catch (e) {
      debugPrint("transport_service: Platform ride cut enqueue failed: $e");
    }
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
    String? vendorPhone,
    String? vendorName,
    double? itemPrice,
    String? pickupLabel,
    String? destLabel,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final request = DeliveryRequest(
      id: '',
      senderId: user.id,
      itemDescription: desc,
      itemCategory: category,
      weight: weight,
      pickup: pickup,
      destination: dest,
      fare: fare,
      status: 'pending',
      createdAt: DateTime.now(),
      vendorPhone: vendorPhone,
      vendorName: vendorName,
      itemPrice: itemPrice,
      pickupLabel: pickupLabel,
      destLabel: destLabel,
    );

    final inserted = await _client
        .from('delivery_requests')
        .insert(request.toMap())
        .select('id')
        .single();
    return inserted['id'] as String?;
  }

  Stream<List<DeliveryRequest>> getPendingDeliveriesStream() {
    return _client
        .from('delivery_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .map((data) => data.map((e) => DeliveryRequest.fromMap(e)).toList());
  }

  Future<bool> acceptDelivery(String deliveryId) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Atomic accept: only succeed if delivery is still pending (prevents double-book)
    final res = await _client.from('delivery_requests')
        .update({
          'driver_id': user.id,
          'status': 'accepted',
          'negotiation_status': 'accepted',
          'fare_locked_at': DateTime.now().toIso8601String(),
          'last_offer_by': null,
        })
        .eq('id', deliveryId)
        .eq('status', 'pending')
        .select('sender_id')
        .maybeSingle();

    if (res == null) {
      debugPrint("transport_service: Delivery $deliveryId already taken by another courier");
      return false;
    }

    final senderId = res['sender_id'];

    // 3. Notify the sender via Push
    await _client.from('notifications').insert({
      'user_id': senderId,
      'title': 'Courier Found!',
      'body': 'A Courier has accepted your cargo mission. Confirm payment to start.',
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
          user.userMetadata?['full_name'] ?? 'a Courier'
        );
      }
    } catch (e) {
      debugPrint("transport_service: SMS Alert Failed: $e");
    }
    return true;
  }

  Future<void> updateDeliveryStatus(String deliveryId, String status) async {
    await _client.from('delivery_requests').update({'status': status}).eq('id', deliveryId);
    
    // Auto-settle if delivered
    if (status == 'delivered') {
      await _settleDelivery(deliveryId);
    }
  }

  Future<void> _settleDelivery(String deliveryId) async {
    final res = await _client
        .from('delivery_requests')
        .select('sender_id, driver_id, offered_fare, negotiated_fare, payment_status, item_description, vendor_phone, vendor_name, item_price')
        .eq('id', deliveryId)
        .single();
    final senderId = res['sender_id'];
    final driverId = res['driver_id'];
    final fare = ((res['negotiated_fare'] ?? res['offered_fare']) as num).toDouble();

    if (driverId == null) return;
    // Never settle a delivery the sender has not paid for.
    if ((res['payment_status'] ?? 'unpaid') != 'paid') {
      debugPrint("transport_service: delivery $deliveryId not paid — skipping settlement");
      return;
    }

    final cutPercent = _businessCutPercent;
    final platformCut = fare * cutPercent;
    final netEarning = fare - platformCut;

    // Update delivery request with platform fee
    await _client.from('delivery_requests').update({
      'platform_fee': platformCut,
    }).eq('id', deliveryId);

    // Log Transactions
    await _client.from('wallet_transactions').insert({
      'user_id': senderId,
      'amount': -fare,
      'type': 'delivery_payment',
      'reference_id': deliveryId,
      'description': 'Payment for Cargo: ${res['item_description']} (${(cutPercent * 100).toStringAsFixed(0)}% platform cut applied)',
      'platform_fee': platformCut,
    });

    await _client.from('wallet_transactions').insert({
      'user_id': driverId,
      'amount': netEarning,
      'type': 'delivery_earning',
      'reference_id': deliveryId,
      'description': 'Earning from Cargo mission (${(cutPercent * 100).toStringAsFixed(0)}% platform cut applied)',
      'platform_fee': platformCut,
    });

    await _client.from('wallet_transactions').insert({
      'user_id': Env.treasuryId,
      'amount': platformCut,
      'type': 'platform_cut_revenue',
      'reference_id': deliveryId,
      'description': 'Platform revenue cut from cargo request $deliveryId',
      'platform_fee': 0.0,
    });

    // 1. Enqueue SERVER-SIDE settlement for courier/driver.
    // The settlement engine resolves the courier + gross from delivery_requests
    // and disburses after delivery is confirmed. Client cannot move money.
    try {
      await _client.rpc('enqueue_payout_task', params: {
        'p_source': 'delivery',
        'p_source_ref': deliveryId,
        'p_payment_ref': null,
        'p_recipient_user_id': null,
        'p_recipient_phone': '',
        'p_gross_amount': netEarning,
      });
    } catch (e) {
      debugPrint("transport_service: Courier settlement enqueue failed: $e");
    }

    // 2. Enqueue SERVER-SIDE escrow settlement for the marketplace vendor.
    // The engine releases item_price * (1 - cut) to delivery_requests.vendor_phone
    // after delivery is confirmed.
    final vendorPhone = res['vendor_phone'];
    final itemPrice = res['item_price'] != null ? (res['item_price'] as num).toDouble() : 0.0;

    if (itemPrice > 0) {
      try {
        await _client.rpc('enqueue_payout_task', params: {
          'p_source': 'escrow',
          'p_source_ref': deliveryId,
          'p_payment_ref': null,
          'p_recipient_user_id': null,
          'p_recipient_phone': vendorPhone?.toString() ?? '',
          'p_gross_amount': itemPrice,
        });
      } catch (e) {
        debugPrint("transport_service: Vendor escrow settlement enqueue failed: $e");
      }
    }

    // 3. Enqueue the PLATFORM cut payout (ride_payout_mobile setting).
    try {
      await _client.rpc('enqueue_payout_task', params: {
        'p_source': 'delivery_cut',
        'p_source_ref': deliveryId,
        'p_payment_ref': null,
        'p_recipient_user_id': null,
        'p_recipient_phone': '',
        'p_gross_amount': platformCut,
      });
    } catch (e) {
      debugPrint("transport_service: Platform delivery cut enqueue failed: $e");
    }
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

final myAcceptedRidesStreamProvider = StreamProvider<List<RideRequest>>((ref) {
  return ref.watch(transportServiceProvider).getMyAcceptedRidesStream();
});

final myAcceptedDeliveriesStreamProvider = StreamProvider<List<DeliveryRequest>>((ref) {
  return ref.watch(transportServiceProvider).getMyAcceptedDeliveriesStream();
});

