import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import 'ride_request_model.dart';
import 'delivery_model.dart';
import '../../../core/services/sms_service.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/services/tenant_service.dart';
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

  Future<void> updateLocation(double lat, double lng, {double? speed}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    // Keep legacy ride_registrations for backwards compat
    try {
      await _client.from('ride_registrations').upsert({
        'user_id': user.id,
        'lat': lat,
        'lng': lng,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('updateLocation ride_registrations upsert failed: $e');
    }
    // Canonical live-location store — read by findNearestWeightedDriver
    // and watchDriverLocation. Must stay in sync with ride_registrations.
    // `speed` (km/h) feeds the crowd-sourced traffic overlay; null when the
    // device reports no valid speed so stale/absent data is never guessed.
    try {
      await _client.from('driver_locations').upsert({
        'driver_id': user.id,
        'lat': lat,
        'lng': lng,
        'is_online': true,
        if (speed != null && speed.isFinite && speed >= 0) 'speed': speed,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'driver_id');
    } catch (e) {
      debugPrint('updateLocation driver_locations upsert failed: $e');
    }
    // Also mirror to profiles.lat/lng so ActiveRideTracking fallback works
    // and any legacy watcher on profiles sees the driver move.
    try {
      await _client.from('profiles').update({'lat': lat, 'lng': lng}).eq('id', user.id);
    } catch (_) {}
  }

  Future<String?> requestRide(LatLng start, LatLng dest, double price,
      {String? pickupLabel, String? destLabel}) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    // Prevent double-booking: passenger can have only one active ride at a time.
    try {
      final active = await _client
          .from('ride_requests')
          .select('id')
          .eq('rider_id', user.id)
          .inFilter('status', ['pending', 'accepted'])
          .limit(1)
          .maybeSingle();
      if (active != null) {
        throw Exception('You already have an active ride. Complete or cancel it before requesting another.');
      }
    } catch (e) {
      if (e.toString().contains('already have an active ride')) rethrow;
      debugPrint('requestRide active check failed (proceeding): $e');
    }

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

    final tenantId = _ref.read(currentTenantProvider)?.id;
    final payload = request.toMap();
    if (tenantId != null && tenantId.isNotEmpty) payload['tenant_id'] = tenantId;
    final inserted = await _client
        .from('ride_requests')
        .insert(payload)
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

    // Prevent driver double-booking: one active ride at a time.
    try {
      final active = await _client
          .from('ride_requests')
          .select('id')
          .eq('driver_id', user.id)
          .eq('status', 'accepted')
          .limit(1)
          .maybeSingle();
      if (active != null) {
        // Check if the current ride is already in progress and allow queuing only when near completion.
        // For now, block and inform — a queued ride would require explicit passenger consent.
        debugPrint('transport_service: driver $user already has active ride ${active['id']} — blocking second accept');
        // Notify the requesting passenger that driver is busy (best-effort)
        try {
          final req = await _client.from('ride_requests').select('rider_id').eq('id', requestId).maybeSingle();
          if (req != null && req['rider_id'] != null) {
            await _sendRidePush(userId: req['rider_id'], title: 'Driver Busy', body: 'The driver is completing another trip and will be available shortly. Your request is queued — you will be notified when they accept.', type: 'ride', referenceId: requestId);
          }
        } catch (_) {}
        return false;
      }
    } catch (e) {
      if (e.toString().contains('Driver Busy')) return false;
      debugPrint('acceptRide active check failed (proceeding): $e');
    }

    Map<String, dynamic>? result;
    try {
      final rpcResult = await _client.rpc('accept_ride_request', params: {
        'p_request_id': requestId,
      });
      if (rpcResult is Map) result = Map<String, dynamic>.from(rpcResult);
    } catch (e) {
      debugPrint('transport_service: server ride acceptance failed: $e');
    }

    if (result == null || result['rider_id'] == null) {
      debugPrint("transport_service: Ride $requestId was not accepted");
      return false;
    }

    final riderId = result['rider_id'];

    // Notify the rider via Push (DB + FCM)
    final fareLabel = await _rideFareLabel(requestId);
    final ridePushTitle = 'Driver Found!';
    final ridePushBody = 'A driver accepted your request at K$fareLabel. Confirm payment to start the trip.';
    await _client.from('notifications').insert({
      'user_id': riderId,
      'title': ridePushTitle,
      'body': ridePushBody,
      'is_read': false,
    });
    // Fire FCM heads-up push (wakes phone even if killed — DB alone is silent in background)
    await _sendRidePush(userId: riderId, title: ridePushTitle, body: ridePushBody, type: 'ride', referenceId: requestId);

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

  Future<void> _sendRidePush({
    required String userId,
    required String title,
    required String body,
    String type = 'ride',
    String? referenceId,
  }) async {
    try {
      await _client.functions.invoke('push-notifications', body: {
        'userId': userId,
        'title': title,
        'body': body,
        'data': {'type': type, 'reference_id': referenceId ?? '', 'ride_id': referenceId ?? ''},
      });
    } catch (e) {
      debugPrint('transport_service: push-notifications invoke failed: $e');
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
    if (counter < 30 || counter > 10000) throw Exception('Fare must be between K30 and K10000');
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
    final counterTitle = 'New Fare Offer';
    final counterBody = 'The driver counter-offered K${counter.toStringAsFixed(0)}. Accept, decline or counter to continue.';
    try {
      await _client.from('notifications').insert({
        'user_id': res['rider_id'],
        'title': counterTitle,
        'body': counterBody,
        'is_read': false,
      });
    } catch (e) {
      debugPrint("transport_service: counter notification failed: $e");
    }
    await _sendRidePush(userId: res['rider_id'], title: counterTitle, body: counterBody, type: 'ride', referenceId: requestId);
  }

  /// Passenger counters the driver's offer (inDrive-style back-and-forth).
  /// Drivers see the counter in their portal as 'passenger_countered'.
  Future<void> passengerCounterFare(String requestId, double counter) async {
    if (counter < 30 || counter > 10000) throw Exception('Fare must be between K30 and K10000');
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
    const apcTitle = 'Driver Found!';
    const apcBody = 'A driver accepted your fare. Confirm payment to start the trip.';
    try {
      await _client.from('notifications').insert({
        'user_id': result['rider_id'],
        'title': apcTitle,
        'body': apcBody,
        'is_read': false,
      });
    } catch (e) {
      debugPrint("transport_service: accept passenger counter notification failed: $e");
    }
    await _sendRidePush(userId: result['rider_id'], title: apcTitle, body: apcBody, type: 'ride', referenceId: requestId);
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
    await _client.rpc('confirm_ride_payment', params: {
      'p_request_id': requestId,
      'p_payment_ref': txId,
    });
    try {
      final res = await _client
          .from('ride_requests')
          .select('driver_id')
          .eq('id', requestId)
          .single();
      if (res['driver_id'] != null) {
        const payTitle = 'Payment Confirmed';
        const payBody = 'The passenger has paid for the ride. Head to the pickup point!';
        await _client.from('notifications').insert({
          'user_id': res['driver_id'],
          'title': payTitle,
          'body': payBody,
          'is_read': false,
        });
        await _sendRidePush(userId: res['driver_id'], title: payTitle, body: payBody, type: 'ride', referenceId: requestId);
      }
    } catch (e) {
      debugPrint("transport_service: driver payment notification failed: $e");
    }
  }

  // ── Delivery negotiation + payment ──

  /// Driver counters a delivery fare (notifies the sender).
  Future<void> counterDeliveryFare(String deliveryId, double counter) async {
    if (counter < 30 || counter > 10000) throw Exception('Fare must be between K30 and K10000');
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
    final cargoCounterTitle = 'New Cargo Fare Offer';
    final cargoCounterBody = 'The courier counter-offered K${counter.toStringAsFixed(0)}. Accept, decline or counter to continue.';
    try {
      await _client.from('notifications').insert({
        'user_id': res['sender_id'],
        'title': cargoCounterTitle,
        'body': cargoCounterBody,
        'is_read': false,
      });
    } catch (e) {
      debugPrint("transport_service: delivery counter notification failed: $e");
    }
    await _sendRidePush(userId: res['sender_id'], title: cargoCounterTitle, body: cargoCounterBody, type: 'ride', referenceId: deliveryId);
  }

  /// Sender counters the courier's offer (inDrive-style back-and-forth).
  Future<void> senderCounterFare(String deliveryId, double counter) async {
    if (counter < 30 || counter > 10000) throw Exception('Fare must be between K30 and K10000');
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
    const ascTitle = 'Courier Found!';
    const ascBody = 'A courier accepted your fare. Confirm payment to start.';
    try {
      await _client.from('notifications').insert({
        'user_id': result['sender_id'],
        'title': ascTitle,
        'body': ascBody,
        'is_read': false,
      });
    } catch (e) {
      debugPrint("transport_service: accept sender counter notification failed: $e");
    }
    await _sendRidePush(userId: result['sender_id'], title: ascTitle, body: ascBody, type: 'ride', referenceId: deliveryId);
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
    await _client.rpc('confirm_delivery_payment', params: {
      'p_delivery_id': deliveryId,
      'p_payment_ref': txId,
    });
    try {
      final res = await _client
          .from('delivery_requests')
          .select('driver_id')
          .eq('id', deliveryId)
          .single();
      if (res['driver_id'] != null) {
        const cdpTitle = 'Payment Confirmed';
        const cdpBody = 'The sender has paid for the cargo mission. Head to the pickup point!';
        await _client.from('notifications').insert({
          'user_id': res['driver_id'],
          'title': cdpTitle,
          'body': cdpBody,
          'is_read': false,
        });
        await _sendRidePush(userId: res['driver_id'], title: cdpTitle, body: cdpBody, type: 'ride', referenceId: deliveryId);
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
    await _client.rpc('transition_ride_status', params: {
      'p_request_id': requestId,
      'p_status': status,
    });

    if (status == 'completed') await _settleRide(requestId);
  }

  Future<void> _settleRide(String requestId) async {
    try {
      await _client.rpc('enqueue_ride_settlements', params: {
        'p_request_id': requestId,
      });
    } catch (e) {
      debugPrint('transport_service: server ride settlement enqueue failed: $e');
    }
  }

  Stream<LatLng?> watchDriverLocation(String driverId) {
    // Canonical store is driver_locations (populated by updateLocation).
    // Fallback to profiles for legacy rows that never wrote driver_locations.
    return _client
        .from('driver_locations')
        .stream(primaryKey: ['driver_id'])
        .eq('driver_id', driverId)
        .map((data) {
          if (data.isNotEmpty) {
            final d = data.first;
            final lat = (d['lat'] as num?)?.toDouble();
            final lng = (d['lng'] as num?)?.toDouble();
            if (lat != null && lng != null) return LatLng(lat, lng);
          }
          return null;
        });
  }

  /// Fallback: profiles lat/lng stream for legacy watchers.
  Stream<LatLng?> watchDriverLocationFallback(String driverId) {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', driverId)
        .map((data) {
          if (data.isEmpty) return null;
          final p = data.first;
          if (p['lat'] != null && p['lng'] != null) {
            return LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
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

    try {
      final active = await _client
          .from('delivery_requests')
          .select('id')
          .eq('sender_id', user.id)
          .inFilter('status', ['pending', 'accepted'])
          .limit(1)
          .maybeSingle();
      if (active != null) {
        throw Exception('You already have an active delivery. Complete or cancel it before requesting another.');
      }
    } catch (e) {
      if (e.toString().contains('already have an active delivery')) rethrow;
      debugPrint('requestDelivery active check failed (proceeding): $e');
    }

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

    try {
      final active = await _client
          .from('delivery_requests')
          .select('id')
          .eq('driver_id', user.id)
          .eq('status', 'accepted')
          .limit(1)
          .maybeSingle();
      if (active != null) {
        debugPrint('transport_service: courier already has active delivery ${active['id']} — blocking second accept');
        try {
          final req = await _client.from('delivery_requests').select('sender_id').eq('id', deliveryId).maybeSingle();
          if (req != null && req['sender_id'] != null) {
            await _sendRidePush(userId: req['sender_id'], title: 'Courier Busy', body: 'The courier is completing another delivery and will be available shortly.', type: 'ride', referenceId: deliveryId);
          }
        } catch (_) {}
        return false;
      }
    } catch (e) {
      debugPrint('acceptDelivery active check failed (proceeding): $e');
    }

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

    // 3. Notify the sender via Push (DB + FCM)
    const courierTitle = 'Courier Found!';
    const courierBody = 'A Courier has accepted your cargo mission. Confirm payment to start.';
    await _client.from('notifications').insert({
      'user_id': senderId,
      'title': courierTitle,
      'body': courierBody,
      'is_read': false,
    });
    await _sendRidePush(userId: senderId, title: courierTitle, body: courierBody, type: 'ride', referenceId: deliveryId);

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
    await _client.rpc('transition_delivery_status', params: {
      'p_delivery_id': deliveryId,
      'p_status': status,
    });

    if (status == 'delivered') await _settleDelivery(deliveryId);
  }

  Future<void> _settleDelivery(String deliveryId) async {
    try {
      await _client.rpc('enqueue_delivery_settlements', params: {
        'p_delivery_id': deliveryId,
      });
    } catch (e) {
      debugPrint('transport_service: server delivery settlement enqueue failed: $e');
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

