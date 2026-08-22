import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/features/events/data/event_service.dart';
import '../../../test_mocks.dart';

final _mockClientProvider = Provider<SupabaseClient>((_) => throw UnimplementedError());

final _eventServiceProvider = Provider<EventService>((ref) {
  return EventService(ref.read(_mockClientProvider), ref);
});

void main() {
  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late MockSingleBuilder mockSingle;
  late MockMaybeSingleBuilder mockMaybeSingle;
  late MockSupabaseStreamBuilder mockStream;
  late ProviderContainer container;
  late EventService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    mockSingle = MockSingleBuilder();
    mockMaybeSingle = MockMaybeSingleBuilder();
    mockStream = MockSupabaseStreamBuilder();
    container = ProviderContainer(overrides: [
      _mockClientProvider.overrideWithValue(mockClient),
    ]);
    service = container.read(_eventServiceProvider);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');
  });

  tearDown(() {
    container.dispose();
  });

  group('createEvent', () {
    test('creates event successfully and returns result', () async {
      when(() => mockClient.from('events')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.single()).thenAnswer((_) => mockSingle);
      mockSingle.result = {'id': 'new_event_1'};

      final result = await service.createEvent({
        'title': 'Test Event',
        'description': 'A test event',
        'location': 'Main Hall',
        'date': DateTime.now().add(const Duration(days: 7)).toIso8601String(),
        'price': 0.0,
      });
      expect(result['id'], 'new_event_1');
    });

    test('throws when user is not authenticated', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      expect(
        () => service.createEvent({'title': 'Test'}),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('login'))),
      );
    });
  });

  group('registerForEvent', () {
    test('registers user successfully', () async {
      when(() => mockClient.from('event_registrations')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select('id')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('event_id', 'event_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = null;
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      when(() => mockClient.from('events')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('id', 'event_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.single()).thenAnswer((_) => mockSingle);
      mockSingle.result = {
        'attendee_count': 10,
        'title': 'Test Event',
        'tenant_id': 'church_1',
      };
      when(() => mockQuery.update(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('id', 'event_1')).thenAnswer((_) => mockFilter);

      when(() => mockClient.from('notifications')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.registerForEvent('event_1');
    });

    test('throws when user is not authenticated', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      expect(
        () => service.registerForEvent('event_1'),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when already registered', () async {
      when(() => mockClient.from('event_registrations')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select('id')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('event_id', 'event_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = {'id': 'reg_1'};

      expect(
        () => service.registerForEvent('event_1'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('already registered'))),
      );
    });
  });

  group('getEventsStream', () {
    test('returns stream from supabase', () {
      when(() => mockClient.from('events')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.stream(primaryKey: ['id'])).thenAnswer((_) => mockStream);
      mockStream.streamResult = Stream.value([]);

      final stream = service.getEventsStream();
      expect(stream, isA<Stream<List<ChurchEvent>>>());
    });
  });

  group('getMyTicketsStream', () {
    test('returns empty stream when user is null', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      final stream = service.getMyTicketsStream();
      final events = await stream.first;
      expect(events, isEmpty);
    });
  });

  group('getEventById', () {
    test('returns null when event not found', () async {
      when(() => mockClient.from('events')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('id', 'nonexistent')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = null;

      final result = await service.getEventById('nonexistent');
      expect(result, isNull);
    });
  });

  group('ChurchEvent model', () {
    test('fromMap parses all fields correctly', () {
      final map = {
        'id': 'e1',
        'title': 'Test Event',
        'description': 'Desc',
        'location': 'Lusaka',
        'date': DateTime.now().toIso8601String(),
        'image_url': 'https://example.com/img.jpg',
        'ticket_price': 50.0,
        'attendee_count': 100,
        'category': 'Conference',
        'speakers': 'John Doe',
        'organizer_momo_phone': '0976847775',
        'organizer_momo_name': 'John',
      };
      final event = ChurchEvent.fromMap(map);
      expect(event.title, 'Test Event');
      expect(event.ticketPrice, 50.0);
      expect(event.location, 'Lusaka');
    });
  });
}
