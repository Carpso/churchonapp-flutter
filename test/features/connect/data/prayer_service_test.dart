
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/connect/data/prayer_service.dart';
import '../../../test_mocks.dart';

void main() {
  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late PrayerService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    service = PrayerService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');
    when(() => mockUser.userMetadata).thenReturn({'name': 'Test User'});
  });

  group('addPrayerRequest - submitPrayer', () {
    test('submits prayer request successfully', () async {
      when(() => mockClient.from('prayers')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.submitPrayer('Lord heal me', 'health', 'public', false);
      verify(() => mockQuery.insert(any(that: containsPair('content', 'Lord heal me')))).called(1);
    });

    test('sets anonymous name when isAnonymous is true', () async {
      when(() => mockClient.from('prayers')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.submitPrayer('Pray for me', 'other', 'public', true);
      verify(() => mockQuery.insert(any(that: containsPair('user_name', 'Anonymous')))).called(1);
    });

    test('does nothing when user is null', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      await service.submitPrayer('test', 'other', 'public', false);
    });
  });

  group('prayForRequest', () {
    test('adds user to prayed_by list', () async {
      when(() => mockClient.from('prayers')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.update(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('id', 'prayer_1')).thenAnswer((_) => mockFilter);

      await service.prayForRequest('prayer_1', []);
      verify(() => mockQuery.update(any(that: containsPair('prayed_by', ['user_1'])))).called(1);
    });

    test('does not add duplicate prayer', () async {
      await service.prayForRequest('prayer_1', ['user_1']);
        verifyNever(() => mockQuery.update(any()));
    });

    test('prevents double prayer using local dedup', () async {
      when(() => mockClient.from('prayers')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.update(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('id', 'prayer_2')).thenAnswer((_) => mockFilter);

      await service.prayForRequest('prayer_2', []);
      await service.prayForRequest('prayer_2', []);
      verify(() => mockQuery.update(any())).called(1);
    });
  });

  group('PrayerRequest model', () {
    test('fromMap parses all fields', () {
      final map = {
        'id': 'pr1',
        'user_id': 'u1',
        'user_name': 'John',
        'content': 'Pray for me',
        'category': 'health',
        'visibility': 'public',
        'prayer_count': 5,
        'prayed_by': ['u1', 'u2'],
        'is_anonymous': false,
        'created_at': DateTime.now().toIso8601String(),
      };
      final pr = PrayerRequest.fromMap(map);
      expect(pr.content, 'Pray for me');
      expect(pr.prayerCount, 5);
      expect(pr.prayedBy.length, 2);
    });
  });
}
