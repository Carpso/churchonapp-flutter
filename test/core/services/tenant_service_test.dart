import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import '../../test_mocks.dart';

// NOTE: `TenantService.fallbackChurches` is now EMPTY BY DESIGN — tenants are
// database-only (no hardcoded seed data for users). These tests verify the
// DB-first resolution contract and graceful degradation instead of the old
// hardcoded zm_1 seed expectations.

void main() {
  late MockSupabaseClient mockClient;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late MockMaybeSingleBuilder mockMaybeSingle;
  late TenantService tenantService;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    mockMaybeSingle = MockMaybeSingleBuilder();
    tenantService = TenantService(mockClient);

    when(() => mockClient.from(any())).thenAnswer((_) => mockQuery);
    when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
    when(() => mockFilter.eq(any(), any())).thenAnswer((_) => mockFilter);
    when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
  });

  group('resolveTenant', () {
    test('resolves from tenants table by id', () async {
      mockMaybeSingle.result = {'id': 'tenant-1', 'name': 'Grace Chapel', 'type': 'church'};

      final t = await tenantService.resolveTenant('tenant-1');
      expect(t, isNotNull);
      expect(t!.name, 'Grace Chapel');
      expect(t.isChurch, isTrue);
    });

    test('returns null when nothing matches', () async {
      mockMaybeSingle.result = null;

      final t = await tenantService.resolveTenant('non-existent-church');
      expect(t, isNull);
    });
  });

  group('getTenantById', () {
    test('resolves church type with joined fields', () async {
      // First maybeSingle = tenants row; second = churches join.
      final tenantsRow = MockMaybeSingleBuilder()
        ..result = {'id': 'tenant-9', 'name': 'Grace Chapel', 'type': 'church'};
      final churchesRow = MockMaybeSingleBuilder()
        ..result = {
          'id': 'tenant-9',
          'slug': 'grace-chapel',
          'name': 'Grace Chapel',
          'primary_color': '#FFD700',
        };
      var call = 0;
      when(() => mockFilter.maybeSingle()).thenAnswer((_) {
        call++;
        return call == 1 ? tenantsRow : churchesRow;
      });

      final t = await tenantService.getTenantById('tenant-9');
      expect(t, isNotNull);
      expect(t!.isChurch, isTrue);
    });

    test('returns null for unknown id', () async {
      mockMaybeSingle.result = null;

      final t = await tenantService.getTenantById('fake_id');
      expect(t, isNull);
    });
  });

  group('getAllTenants', () {
    test('churches load even when bookshops query throws (web/anon RLS)', () async {
      // Churches succeed; bookshops fail → non-fatal (website tenant fix).
      when(() => mockClient.from('churches')).thenAnswer((_) => mockQuery);
      when(() => mockClient.from('bookshops')).thenThrow(Exception('RLS blocked'));
      when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order(any(), ascending: any(named: 'ascending')))
          .thenAnswer((_) => mockFilter);

      mockFilter.mockResult = [
        {'id': 'c1', 'slug': 'grace', 'name': 'Grace Chapel', 'is_verified': true},
      ];

      final tenants = await tenantService.getAllTenants();
      expect(tenants.length, 1, reason: 'bookshop failure must not wipe churches');
      expect(tenants.first['type'], 'church');
      expect(tenants.first['_registered'], isTrue);
    });
  });
}
