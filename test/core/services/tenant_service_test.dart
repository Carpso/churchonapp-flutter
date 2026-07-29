import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  late MockSupabaseClient mockClient;
  late TenantService tenantService;

  setUp(() {
    mockClient = MockSupabaseClient();
    tenantService = TenantService(mockClient);
  });

  /* group('getTenantContent', () {
    test('returns a function that filters by tenant_id', () {
      final filterFn = tenantService.getTenantContent('zm_1');
      expect(filterFn, isA<Function>());
    });
  });

  group('getInterchurchContent', () {
    test('returns a function that filters non-null tenant_id', () {
      final filterFn = tenantService.getInterchurchContent();
      expect(filterFn, isA<Function>());
    });
  });

  group('applyTenantFilter', () {
    test('returns a function reference for filtering', () {
      final filterFn = tenantService.getTenantContent('zm_1');
      expect(filterFn, isA<Function>());
    });
  }); */

  group('resolveTenant with fallback', () {
    test('returns Tenant for known slug from fallback', () async {
      final tenant = await tenantService.resolveTenant('st-peters-lusaka');
      expect(tenant, isNotNull);
      expect(tenant!.id, 'zm_1');
      expect(tenant.name, 'St. Peters Anglican Church');
    });

    test('returns null for unknown slug', () async {
      final tenant = await tenantService.resolveTenant('non-existent-church');
      expect(tenant, isNull);
    });
  });

  group('getTenantById with fallback', () {
    test('returns Tenant for known id from fallback', () async {
      final tenant = await tenantService.getTenantById('zm_1');
      expect(tenant, isNotNull);
      expect(tenant!.slug, 'st-peters-lusaka');
    });

    test('returns null for unknown id', () async {
      final tenant = await tenantService.getTenantById('fake_id');
      expect(tenant, isNull);
    });
  });
}
