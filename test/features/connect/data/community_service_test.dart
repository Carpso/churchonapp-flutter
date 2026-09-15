import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/connect/data/community_service.dart';
import '../../../test_mocks.dart';

void main() {
  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;

  late MockQueryBuilder profileQuery;
  late MockFilterBuilder profileFilter;
  late MockMaybeSingleBuilder profileMaybeSingle;

  late MockQueryBuilder communityQuery;
  late MockFilterBuilder communityFilter;
  late MockMaybeSingleBuilder communityMaybeSingle;

  late MockQueryBuilder groupQuery;
  late MockFilterBuilder groupFilter;
  late MockMaybeSingleBuilder groupMaybeSingle;

  late MockQueryBuilder memberQuery;
  late MockFilterBuilder memberFilter;
  late MockMaybeSingleBuilder memberMaybeSingle;

  late CommunityService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();

    profileQuery = MockQueryBuilder();
    profileFilter = MockFilterBuilder();
    profileMaybeSingle = MockMaybeSingleBuilder();

    communityQuery = MockQueryBuilder();
    communityFilter = MockFilterBuilder();
    communityMaybeSingle = MockMaybeSingleBuilder();

    groupQuery = MockQueryBuilder();
    groupFilter = MockFilterBuilder();
    groupMaybeSingle = MockMaybeSingleBuilder();

    memberQuery = MockQueryBuilder();
    memberFilter = MockFilterBuilder();
    memberMaybeSingle = MockMaybeSingleBuilder();

    service = CommunityService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');

    when(() => mockClient.from('community_communities'))
        .thenAnswer((_) => communityQuery);
    when(() => mockClient.from('community_groups')).thenAnswer((_) => groupQuery);
    when(() => mockClient.from('profiles')).thenAnswer((_) => profileQuery);
    when(() => mockClient.from('community_group_members'))
        .thenAnswer((_) => memberQuery);
  });

  group('fetchCommunities', () {
    test('returns empty when the user has no tenant', () async {
      final result = await service.fetchCommunities(tenantId: null);
      expect(result, isEmpty);
    });

    test('nests groups under their community and adds ids', () async {
      when(() => communityQuery.select()).thenAnswer((_) => communityFilter);
      when(() => communityFilter.eq('tenant_id', 't1'))
          .thenAnswer((_) => communityFilter);
      when(() => communityFilter.order('sort_order'))
          .thenAnswer((_) => communityFilter);
      communityFilter.mockResult = [
        {'id': 'c1', 'name': 'Youth', 'tenant_id': 't1'},
      ];

      when(() => groupQuery.select()).thenAnswer((_) => groupFilter);
      when(() => groupFilter.eq('tenant_id', 't1'))
          .thenAnswer((_) => groupFilter);
      when(() => groupFilter.order('sort_order')).thenAnswer((_) => groupFilter);
      groupFilter.mockResult = [
        {'id': 'g1', 'community_id': 'c1', 'title': 'Prayer Warriors'},
        {'id': 'g2', 'community_id': 'other', 'title': 'Elsewhere'},
      ];

      final result = await service.fetchCommunities(tenantId: 't1');

      expect(result, hasLength(1));
      expect(result.first['id'], 'c1');
      final groups = (result.first['groups'] as List)
          .cast<Map<String, dynamic>>();
      expect(groups, hasLength(1));
      expect(groups.first['id'], 'g1');
      expect(groups.first['communityId'], 'c1');
      expect(groups.first['title'], 'Prayer Warriors');
    });
  });

  group('createCommunity', () {
    test('inserts with the caller tenant + created_by and returns the id',
        () async {
      // _myTenantId()
      when(() => profileQuery.select(any())).thenAnswer((_) => profileFilter);
      when(() => profileFilter.eq('id', 'user_1'))
          .thenAnswer((_) => profileFilter);
      when(() => profileFilter.maybeSingle())
          .thenAnswer((_) => profileMaybeSingle);
      profileMaybeSingle.result = {'tenant_id': 't1'};

      // insert
      when(() => communityQuery.insert(any()))
          .thenAnswer((_) => communityFilter);
      when(() => communityFilter.select(any()))
          .thenAnswer((_) => communityFilter);
      when(() => communityFilter.maybeSingle())
          .thenAnswer((_) => communityMaybeSingle);
      communityMaybeSingle.result = {'id': 'c9'};

      final id = await service.createCommunity(name: 'New Fellowship');

      expect(id, 'c9');
      verify(() => communityQuery.insert(any(that: allOf(
            containsPair('name', 'New Fellowship'),
            containsPair('tenant_id', 't1'),
            containsPair('created_by', 'user_1'),
          )))).called(1);
    });

    test('returns null when there is no signed-in user', () async {
      when(() => mockAuth.currentUser).thenReturn(null);
      final id = await service.createCommunity(name: 'X');
      expect(id, isNull);
      verifyNever(() => communityQuery.insert(any()));
    });
  });

  group('updateCommunity', () {
    test('no-ops when no fields are provided', () async {
      await service.updateCommunity('c1');
      verifyNever(() => communityQuery.update(any()));
    });

    test('updates name and is_public', () async {
      when(() => communityQuery.update(any()))
          .thenAnswer((_) => communityFilter);
      when(() => communityFilter.eq('id', 'c1'))
          .thenAnswer((_) => communityFilter);

      await service.updateCommunity('c1', name: 'Renamed', isPublic: false);

      verify(() => communityQuery.update(
          any(that: allOf(containsPair('name', 'Renamed'), containsPair('is_public', false)))))
          .called(1);
      verify(() => communityFilter.eq('id', 'c1')).called(1);
    });
  });

  group('deleteCommunity', () {
    test('deletes by id', () async {
      when(() => communityQuery.delete()).thenAnswer((_) => communityFilter);
      when(() => communityFilter.eq('id', 'c1'))
          .thenAnswer((_) => communityFilter);

      await service.deleteCommunity('c1');

      verify(() => communityFilter.eq('id', 'c1')).called(1);
    });
  });

  group('createGroup', () {
    test('inherits the community tenant and generates an identifier',
        () async {
      // _myTenantId()
      when(() => profileQuery.select(any())).thenAnswer((_) => profileFilter);
      when(() => profileFilter.eq('id', 'user_1'))
          .thenAnswer((_) => profileFilter);
      when(() => profileFilter.maybeSingle())
          .thenAnswer((_) => profileMaybeSingle);
      profileMaybeSingle.result = {'tenant_id': 't1'};

      // community tenant lookup
      when(() => communityQuery.select(any()))
          .thenAnswer((_) => communityFilter);
      when(() => communityFilter.eq('id', 'c1'))
          .thenAnswer((_) => communityFilter);
      when(() => communityFilter.maybeSingle())
          .thenAnswer((_) => communityMaybeSingle);
      communityMaybeSingle.result = {'tenant_id': 't1'};

      // insert
      when(() => groupQuery.insert(any())).thenAnswer((_) => groupFilter);
      when(() => groupFilter.select(any())).thenAnswer((_) => groupFilter);
      when(() => groupFilter.maybeSingle())
          .thenAnswer((_) => groupMaybeSingle);
      groupMaybeSingle.result = {'id': 'g9'};

      final id = await service.createGroup(communityId: 'c1', title: 'Choir');

      expect(id, 'g9');
      verify(() => groupQuery.insert(any(that: allOf(
            containsPair('community_id', 'c1'),
            containsPair('title', 'Choir'),
            containsPair('tenant_id', 't1'),
            containsPair('created_by', 'user_1'),
          )))).called(1);
    });
  });

  group('membership', () {
    test('isMember is true when a membership row exists', () async {
      when(() => memberQuery.select('id')).thenAnswer((_) => memberFilter);
      when(() => memberFilter.eq('group_id', 'g1'))
          .thenAnswer((_) => memberFilter);
      when(() => memberFilter.eq('user_id', 'user_1'))
          .thenAnswer((_) => memberFilter);
      when(() => memberFilter.maybeSingle())
          .thenAnswer((_) => memberMaybeSingle);
      memberMaybeSingle.result = {'id': 'm1'};

      expect(await service.isMember('g1'), isTrue);
    });

    test('isMember is false when there is no row', () async {
      when(() => memberQuery.select('id')).thenAnswer((_) => memberFilter);
      when(() => memberFilter.eq('group_id', 'g1'))
          .thenAnswer((_) => memberFilter);
      when(() => memberFilter.eq('user_id', 'user_1'))
          .thenAnswer((_) => memberFilter);
      when(() => memberFilter.maybeSingle())
          .thenAnswer((_) => memberMaybeSingle);
      memberMaybeSingle.result = null;

      expect(await service.isMember('g1'), isFalse);
    });

    test('joinGroup inserts a membership and bumps the count', () async {
      when(() => memberQuery.select('id')).thenAnswer((_) => memberFilter);
      when(() => memberFilter.eq('group_id', 'g1'))
          .thenAnswer((_) => memberFilter);
      when(() => memberFilter.eq('user_id', 'user_1'))
          .thenAnswer((_) => memberFilter);
      when(() => memberFilter.maybeSingle())
          .thenAnswer((_) => memberMaybeSingle);
      memberMaybeSingle.result = null;

      when(() => memberQuery.insert(any())).thenAnswer((_) => memberFilter);
      when(() => mockClient.rpc('bump_group_member_count',
          params: any(named: 'params'))).thenAnswer((_) => memberFilter);

      final ok = await service.joinGroup('g1');

      expect(ok, isTrue);
      verify(() => memberQuery.insert(any(that: containsPair('group_id', 'g1'))))
          .called(1);
      verify(() => mockClient.rpc('bump_group_member_count',
          params: {'p_group_id': 'g1', 'p_delta': 1})).called(1);
    });

    test('leaveGroup deletes the membership and decrements the count',
        () async {
      when(() => memberFilter.eq('group_id', 'g1'))
          .thenAnswer((_) => memberFilter);
      when(() => memberFilter.eq('user_id', 'user_1'))
          .thenAnswer((_) => memberFilter);
      when(() => memberQuery.delete()).thenAnswer((_) => memberFilter);
      when(() => mockClient.rpc('bump_group_member_count',
          params: any(named: 'params'))).thenAnswer((_) => memberFilter);

      final ok = await service.leaveGroup('g1');

      expect(ok, isTrue);
      verify(() => mockClient.rpc('bump_group_member_count',
          params: {'p_group_id': 'g1', 'p_delta': -1})).called(1);
    });
  });
}
