import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/transport/data/ride_history_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockAuth extends Mock implements GoTrueClient {}
class MockUser extends Mock implements User {}
class MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}
class MockFilterBuilder extends Mock
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  @override
  Future<R> then<R>(FutureOr<R> Function(List<Map<String, dynamic>>) onValue,
      {Function? onError}) {
    return Future.value(<Map<String, dynamic>>[]).then(onValue, onError: onError);
  }
}

void main() {
  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late RideHistoryService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    service = RideHistoryService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');
  });

  group('saveRide', () {
    test('saves ride to history table', () async {
      final ride = RideHistory(
        id: 'ride_1',
        rideType: RideType.ride,
        pickup: 'Church',
        destination: 'Home',
        fare: 25.0,
        status: 'completed',
        dateTime: DateTime.now(),
      );

      when(() => mockClient.from('ride_history')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.saveRide(ride);

      verify(() => mockQuery.insert(any(that: containsPair('user_id', 'user_1')))).called(1);
    });

    test('does nothing when user is null', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      final ride = RideHistory(
        id: 'ride_1',
        rideType: RideType.ride,
        pickup: 'A',
        destination: 'B',
        fare: 10.0,
        status: 'completed',
        dateTime: DateTime.now(),
      );

      await service.saveRide(ride);
    });
  });

  group('getRideHistory', () {
    test('returns empty list when user is null', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      final history = await service.getRideHistory();
      expect(history, isEmpty);
    });
  });

  group('RideHistory model', () {
    test('fromMap parses ride type correctly', () {
      final map = {
        'id': 'r1',
        'ride_type': 'ride',
        'pickup': 'A',
        'destination': 'B',
        'fare': 10.0,
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
      };
      final ride = RideHistory.fromMap(map);
      expect(ride.rideType, RideType.ride);
    });

    test('fromMap parses delivery type', () {
      final map = {
        'id': 'd1',
        'ride_type': 'delivery',
        'pickup': 'A',
        'destination': 'B',
        'fare': 15.0,
        'status': 'delivered',
        'created_at': DateTime.now().toIso8601String(),
      };
      final ride = RideHistory.fromMap(map);
      expect(ride.rideType, RideType.delivery);
    });

    test('toMap serializes correctly', () {
      final ride = RideHistory(
        id: 'r1',
        rideType: RideType.ride,
        pickup: 'A',
        destination: 'B',
        fare: 10.0,
        status: 'completed',
        dateTime: DateTime.now(),
      );
      final map = ride.toMap();
      expect(map['id'], 'r1');
      expect(map['ride_type'], 'ride');
      expect(map['fare'], 10.0);
    });
  });
}
