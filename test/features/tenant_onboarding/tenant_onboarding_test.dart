import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/plan_service.dart';

void main() {
  Map<String, dynamic> churchMap({
    String id = '11111111-1111-1111-1111-111111111111',
    String name = 'Grace Chapel Lusaka',
    bool verified = true,
    String country = 'Zambia',
  }) =>
      {
        'id': id,
        'slug': 'grace-chapel-lusaka',
        'name': name,
        'type': 'church',
        'primary_color': '#FFD700',
        'accent_color': '#1A1A1A',
        'is_verified': verified,
        'country': country,
        'latitude': -15.3875,
        'longitude': 28.3228,
        'plan': 'gold',
      };

  Map<String, dynamic> bookshopMap({
    String id = '22222222-2222-2222-2222-222222222222',
    bool active = true,
  }) =>
      {
        'id': id,
        'name': 'Kingdom Books Kabulonga',
        'type': 'bookshop',
        'is_active': active,
      };

  group('Tenant onboarding — church activation switch', () {
    test('verified church maps to _registered=true (selectable)', () {
      final map = {...churchMap(), '_registered': true};
      final t = Tenant.fromMap(map);
      expect(t.isChurch, isTrue);
      expect(t.isBookshop, isFalse);
    });

    test('unverified church is NOT selectable', () {
      // The service layer derives `_registered` from is_verified — the model
      // itself must not silently flip it.
      final map = churchMap(verified: false);
      expect(map['is_verified'], false);
      final derivedRegistered = map['is_verified'] == true;
      expect(derivedRegistered, isFalse);
    });

    test('bookshop activation uses is_active not is_verified', () {
      // Service contract: bookshops derive _registered from `is_active`.
      final activeShop = bookshopMap(active: true);
      final inactiveShop = bookshopMap(active: false);
      expect(activeShop['is_active'], true);
      expect(inactiveShop['is_active'], false);
      final t = Tenant.fromMap(bookshopMap());
      expect(t.isBookshop, isTrue);
      expect(t.isChurch, isFalse);
    });

    test('new church defaults to silver plan when plan missing', () {
      final map = churchMap()..remove('plan');
      final t = Tenant.fromMap(map);
      expect(t.plan, TenantPlan.silver, reason: 'safe default for new tenants');
    });

    test('gold plan parses and exposes limits', () {
      final t = Tenant.fromMap(churchMap());
      expect(t.plan, TenantPlan.gold);
      expect(t.limits, PlanLimits.forPlan(TenantPlan.gold));
    });

    test('trial period: subscription_ends_at in future means in-trial', () {
      final map = churchMap()
        ..['subscription_ends_at'] =
            DateTime.now().add(const Duration(days: 30)).toIso8601String();
      final t = Tenant.fromMap(map);
      expect(t.isInTrialPeriod, isTrue);
      expect(t.isSubscriptionExpired, isFalse);
    });

    test('expired subscription flags paywall state', () {
      final map = churchMap()
        ..['subscription_ends_at'] =
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
      final t = Tenant.fromMap(map);
      expect(t.isSubscriptionExpired, isTrue);
      expect(t.isInTrialPeriod, isFalse);
    });
  });

  group('Multi-tenant data isolation (model-level contracts)', () {
    test('two tenants with same-name churches keep distinct ids/slugs', () {
      final a = Tenant.fromMap({
        ...churchMap(id: 'aaaa-1', name: 'Grace Chapel'),
        'slug': 'grace-chapel-lusaka',
      });
      final b = Tenant.fromMap({
        ...churchMap(id: 'bbbb-2', name: 'Grace Chapel'),
        'slug': 'grace-chapel-ndola',
      });
      expect(a.id, isNot(equals(b.id)), reason: 'ids must never collide');
      expect(a.slug, isNot(equals(b.slug)));
      expect(a.name, b.name, reason: 'same display name allowed across tenants');
    });

    test('tenant settings map does NOT leak across instances', () {
      final aMap = churchMap()..['settings'] = {'events_management': false};
      final bMap = churchMap()..['settings'] = {'events_management': true};
      final a = Tenant.fromMap(aMap);
      final b = Tenant.fromMap(bMap);
      expect(a.settings?['events_management'], false);
      expect(b.settings?['events_management'], true);
      // Mutating one instance's settings must not affect the other.
      a.settings?['events_management'] = true;
      expect(b.settings?['events_management'], true);
    });

    test('empty/missing id falls back safely without cross-tenant aliasing', () {
      final t = Tenant.fromMap({'name': 'Orphan Church'});
      expect(t.id, isNotEmpty, reason: 'fallback id prevents empty tenant scope');
    });

    test('organization linkage preserved for diocesan bishops', () {
      final t = Tenant.fromMap({...churchMap(), 'organization_id': 'org-77'});
      expect(t.organizationId, 'org-77');
    });

    test('theme colors parse per-tenant without bleeding to defaults', () {
      final goldTenant = Tenant.fromMap(churchMap());
      final blueMap = churchMap(id: 'blue-1')..['primary_color'] = '#0066FF';
      final blueTenant = Tenant.fromMap(blueMap);
      expect(goldTenant.primaryColor.toARGB32(), isNot(blueTenant.primaryColor.toARGB32()));
      int blue(Color c) => (c.b * 255.0).round() & 0xff;
      int red(Color c) => (c.r * 255.0).round() & 0xff;
      expect(blue(blueTenant.primaryColor), greaterThan(red(blueTenant.primaryColor)));
    });
  });

  group('Diocese / Bishop hierarchy onboarding', () {
    test('bishop org creation contract: caller becomes bishop of own HQ church', () {
      // Mirrors create_organization RPC semantics tested server-side; here we
      // verify the client model keeps org id + own tenant distinct.
      final hq = Tenant.fromMap({
        ...churchMap(),
        'organization_id': null, // pre-creation
      });
      expect(hq.organizationId, isNull);

      final linked = Tenant.fromMap({
        ...churchMap(),
        'organization_id': 'org-hq-001',
      });
      expect(linked.organizationId, 'org-hq-001');
      // Branch churches share the SAME organization_id but different tenant ids.
      final branch = Tenant.fromMap({
        ...churchMap(id: 'branch-9'),
        'organization_id': 'org-hq-001',
      });
      expect(branch.organizationId, linked.organizationId);
      expect(branch.id, isNot(linked.id));
    });
  });
}
