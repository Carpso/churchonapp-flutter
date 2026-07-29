import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

enum RideType { ride, delivery }

class RideHistory {
  final String id;
  final RideType rideType;
  final String pickup;
  final String destination;
  final double fare;
  final String status;
  final String? driverName;
  final double? driverRating;
  final DateTime dateTime;

  RideHistory({
    required this.id,
    required this.rideType,
    required this.pickup,
    required this.destination,
    required this.fare,
    required this.status,
    this.driverName,
    this.driverRating,
    required this.dateTime,
  });

  factory RideHistory.fromMap(Map<String, dynamic> map) {
    return RideHistory(
      id: map['id']?.toString() ?? '',
      rideType: map['ride_type'] == 'delivery' ? RideType.delivery : RideType.ride,
      pickup: map['pickup']?.toString() ?? '',
      destination: map['destination']?.toString() ?? '',
      fare: (map['fare'] as num?)?.toDouble() ?? 0.0,
      status: map['status']?.toString() ?? 'completed',
      driverName: map['driver_name']?.toString(),
      driverRating: (map['driver_rating'] as num?)?.toDouble(),
      dateTime: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ride_type': rideType == RideType.delivery ? 'delivery' : 'ride',
      'pickup': pickup,
      'destination': destination,
      'fare': fare,
      'status': status,
      'driver_name': driverName,
      'driver_rating': driverRating,
      'created_at': dateTime.toIso8601String(),
    };
  }
}

class RideHistoryService {
  final SupabaseClient _client;

  RideHistoryService(this._client);

  Future<void> saveRide(RideHistory ride) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('ride_history').insert({
      ...ride.toMap(),
      'user_id': user.id,
    });
  }

  Future<List<RideHistory>> getRideHistory() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    final res = await _client
        .from('ride_history')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    return res.map((e) => RideHistory.fromMap(e)).toList();
  }

  Stream<List<RideHistory>> streamRideHistory() {
    final user = _client.auth.currentUser;
    if (user == null) return Stream.value([]);
    return _client
        .from('ride_history')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .map((data) => data.map((e) => RideHistory.fromMap(e)).toList());
  }
}

final rideHistoryServiceProvider = Provider<RideHistoryService>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return RideHistoryService(client);
});

final rideHistoryStreamProvider = StreamProvider<List<RideHistory>>((ref) {
  return ref.watch(rideHistoryServiceProvider).streamRideHistory();
});

final rideHistoryListProvider = FutureProvider<List<RideHistory>>((ref) {
  return ref.watch(rideHistoryServiceProvider).getRideHistory();
});
