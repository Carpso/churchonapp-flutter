import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/features/transport/data/transport_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockAuth extends Mock implements GoTrueClient {}
class MockUser extends Mock implements User {}
class MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}
class MockFilterBuilder extends Mock implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {}

class MockSupabaseService extends Mock implements SupabaseService {}

void main() {
  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late MockSupabaseService mockSupabaseService;
  late TransportService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    mockSupabaseService = MockSupabaseService();

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');
    when(() => mockSupabaseService.client).thenReturn(mockClient);

    final container = ProviderContainer(
      overrides: [
        supabaseServiceProvider.overrideWith((ref) => mockSupabaseService),
      ],
    );
    service = container.read(transportServiceProvider);
  });

  group('requestRide', () {
    test('returns null when user is not authenticated', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      final id = await service.requestRide(
        const LatLng(-15.385, 28.320),
        const LatLng(-15.420, 28.350),
        50.0,
      );

      expect(id, isNull);
    });
  });

  group('updateRideStatus', () {
    test('calls update on ride_requests table', () async {
      when(() => mockClient.from('ride_requests')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.update({'status': 'cancelled'})).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('id', 'ride_1')).thenAnswer((_) => mockFilter);
    });
  });

  group('RideRegistration model', () {
    test('fromMap parses all fields', () {
      final map = {
        'id': 'reg1',
        'user_id': 'u1',
        'type': 'driver',
        'status': 'available',
        'lat': -15.385,
        'lng': 28.320,
        'vehicle_info': 'Toyota',
        'updated_at': DateTime.now().toIso8601String(),
      };
      final reg = RideRegistration.fromMap(map);
      expect(reg.id, 'reg1');
      expect(reg.type, 'driver');
      expect(reg.status, 'available');
    });

    test('fromMap handles null vehicle_info', () {
      final map = {
        'id': 'reg2',
        'user_id': 'u2',
        'type': 'rider',
        'status': 'active',
        'lat': -15.4,
        'lng': 28.33,
        'updated_at': DateTime.now().toIso8601String(),
      };
      final reg = RideRegistration.fromMap(map);
      expect(reg.vehicleInfo, isNull);
    });
  });
}
