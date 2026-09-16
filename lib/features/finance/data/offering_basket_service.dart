import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/services/tenant_service.dart';

/// A church offering basket type (Tithe, Sunday Offering, Missions…).
///
/// `tenantId == null` means the basket is ORGANISATION-wide: every church in
/// that organisation sees it. Tenant baskets belong to one church only.
class OfferingBasket {
  final String id;
  final String? tenantId;
  final String? organizationId;
  final String name;
  final String? code;
  final String? description;
  final String icon;
  final String color;
  final bool isActive;
  final int sortOrder;

  const OfferingBasket({
    required this.id,
    this.tenantId,
    this.organizationId,
    required this.name,
    this.code,
    this.description,
    this.icon = 'hand-heart',
    this.color = '#FFDA03',
    this.isActive = true,
    this.sortOrder = 0,
  });

  bool get isOrgWide => tenantId == null;

  factory OfferingBasket.fromMap(Map<String, dynamic> map) {
    return OfferingBasket(
      id: map['id'].toString(),
      tenantId: map['tenant_id']?.toString(),
      organizationId: map['organization_id']?.toString(),
      name: (map['name'] ?? 'Offering').toString(),
      code: map['code']?.toString(),
      description: map['description']?.toString(),
      icon: (map['icon'] ?? 'hand-heart').toString(),
      color: (map['color'] ?? '#FFDA03').toString(),
      isActive: map['is_active'] != false,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A timed "offering time" session a leader opens. Members give into the
/// basket while it is open; totals accumulate server-side.
class OfferingSession {
  final String id;
  final String tenantId;
  final String? basketTypeId;
  final String? basketName;
  final String? title;
  final String status;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double totalAmount;
  final int contributionCount;
  final String? notes;

  const OfferingSession({
    required this.id,
    required this.tenantId,
    this.basketTypeId,
    this.basketName,
    this.title,
    required this.status,
    required this.openedAt,
    this.closedAt,
    this.totalAmount = 0,
    this.contributionCount = 0,
    this.notes,
  });

  bool get isOpen => status == 'open';

  factory OfferingSession.fromMap(Map<String, dynamic> map) {
    return OfferingSession(
      id: map['id'].toString(),
      tenantId: map['tenant_id'].toString(),
      basketTypeId: map['basket_type_id']?.toString(),
      basketName: map['basket_name']?.toString(),
      title: map['title']?.toString(),
      status: (map['status'] ?? 'open').toString(),
      openedAt: DateTime.tryParse(map['opened_at']?.toString() ?? '') ??
          DateTime.now(),
      closedAt: map['closed_at'] != null
          ? DateTime.tryParse(map['closed_at'].toString())
          : null,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      contributionCount:
          (map['contribution_count'] as num?)?.toInt() ?? 0,
      notes: map['notes']?.toString(),
    );
  }
}

/// One row of `get_basket_summary` — totals for a basket over a window.
class BasketSummaryRow {
  final String? basketTypeId;
  final String basketName;
  final String? basketCode;
  final String scope; // tenant | organisation
  final int sessions;
  final double totalAmount;
  final DateTime? lastTakenAt;

  const BasketSummaryRow({
    this.basketTypeId,
    required this.basketName,
    this.basketCode,
    required this.scope,
    required this.sessions,
    required this.totalAmount,
    this.lastTakenAt,
  });

  factory BasketSummaryRow.fromMap(Map<String, dynamic> map) {
    return BasketSummaryRow(
      basketTypeId: map['basket_type_id']?.toString(),
      basketName: (map['basket_name'] ?? 'Offering').toString(),
      basketCode: map['basket_code']?.toString(),
      scope: (map['scope'] ?? 'tenant').toString(),
      sessions: (map['sessions'] as num?)?.toInt() ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      lastTakenAt: map['last_taken_at'] != null
          ? DateTime.tryParse(map['last_taken_at'].toString())
          : null,
    );
  }
}

class OfferingBasketService {
  final SupabaseClient _client;
  OfferingBasketService(this._client);

  /// Baskets visible to the signed-in user — their church's baskets plus any
  /// organisation-wide baskets.
  ///
  /// IMPORTANT: this is scoped explicitly by [tenantId]/[organizationId] and
  /// does NOT rely on RLS alone. Staff (superadmin / COA) bypass the tenant
  /// branch of the read policy, so without this filter the Give tab would list
  /// every church's baskets (e.g. 33× "Tithe").
  Future<List<OfferingBasket>> fetchBaskets({
    String? tenantId,
    String? organizationId,
    bool activeOnly = true,
  }) async {
    Future<List<OfferingBasket>> run({
      String? eqTenant,
      bool nullTenant = false,
      String? eqOrg,
    }) async {
      dynamic q = _client.from('offering_basket_types').select();
      if (activeOnly) q = q.eq('is_active', true);
      if (eqTenant != null && eqTenant.isNotEmpty) q = q.eq('tenant_id', eqTenant);
      if (nullTenant) q = q.isFilter('tenant_id', null);
      if (eqOrg != null && eqOrg.isNotEmpty) q = q.eq('organization_id', eqOrg);
      final rows = await q
          .order('sort_order', ascending: true)
          .order('name', ascending: true);
      return (rows as List)
          .map((e) =>
              OfferingBasket.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    if (tenantId == null || tenantId.isEmpty) {
      // No church context — only organisation-wide baskets are meaningful.
      return run(nullTenant: true, eqOrg: organizationId);
    }

    final own = await run(eqTenant: tenantId);
    if (organizationId == null || organizationId.isEmpty) return own;

    final org = await run(nullTenant: true, eqOrg: organizationId);
    final merged = <String, OfferingBasket>{
      for (final b in own) b.id: b,
      for (final b in org) b.id: b,
    }.values.toList()
      ..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    return merged;
  }

  Future<List<OfferingSession>> fetchSessions({
    String? tenantId,
    int days = 60,
  }) async {
    final since = DateTime.now().subtract(Duration(days: days));
    dynamic q = _client
        .from('offering_sessions')
        .select()
        .gte('opened_at', since.toIso8601String());
    if (tenantId != null && tenantId.isNotEmpty) {
      q = q.eq('tenant_id', tenantId);
    }
    final rows = await q.order('opened_at', ascending: false).limit(200);
    return (rows as List)
        .map((e) => OfferingSession.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// The currently-live offering session for the church, if any.
  Future<OfferingSession?> fetchActiveSession({String? tenantId}) async {
    dynamic q = _client.from('offering_sessions').select().eq('status', 'open');
    if (tenantId != null && tenantId.isNotEmpty) {
      q = q.eq('tenant_id', tenantId);
    }
    final rows = await q.order('opened_at', ascending: false).limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return OfferingSession.fromMap(Map<String, dynamic>.from(list.first as Map));
  }

  Future<OfferingBasket> createBasket({
    required String name,
    String? code,
    String? description,
    String icon = 'hand-heart',
    String color = '#FFDA03',
    int sortOrder = 0,
    bool orgWide = false,
  }) async {
    final res = await _client.rpc('create_offering_basket', params: {
      'p_name': name,
      'p_code': code,
      'p_description': description,
      'p_icon': icon,
      'p_color': color,
      'p_sort_order': sortOrder,
      'p_org_wide': orgWide,
    });
    final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    final id = map['basket_id']?.toString();
    if (id == null) throw Exception('Basket was not created');
    // Return the freshly-created basket if we can read it back; otherwise a
    // local stand-in keeps the UI responsive.
    final all = await fetchBaskets(activeOnly: false);
    return all.firstWhere(
      (b) => b.id == id,
      orElse: () => OfferingBasket(
        id: id,
        name: name,
        code: code,
        description: description,
        icon: icon,
        color: color,
        sortOrder: sortOrder,
      ),
    );
  }

  Future<void> updateBasket({
    required String basketId,
    String? name,
    String? code,
    bool? isActive,
    int? sortOrder,
  }) async {
    await _client.rpc('update_offering_basket', params: {
      'p_basket_id': basketId,
      'p_name': name,
      'p_code': code,
      'p_is_active': isActive,
      'p_sort_order': sortOrder,
    });
  }

  Future<OfferingSession> openSession({
    required String basketTypeId,
    String? title,
  }) async {
    final res = await _client.rpc('open_offering_session', params: {
      'p_basket_type_id': basketTypeId,
      'p_title': title,
    });
    final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    final id = map['session_id']?.toString();
    if (id == null) throw Exception('Could not open the offering');
    return OfferingSession(
      id: id,
      tenantId: '',
      basketTypeId: basketTypeId,
      basketName: map['basket']?.toString(),
      title: title,
      status: 'open',
      openedAt: DateTime.now(),
    );
  }

  Future<void> closeSession(String sessionId, {String? notes}) async {
    await _client.rpc('close_offering_session', params: {
      'p_session_id': sessionId,
      'p_notes': notes,
    });
  }

  /// Record a confirmed gift into an open session. Idempotent by payment ref.
  Future<bool> recordContribution({
    required String sessionId,
    required double amount,
    String? paymentRef,
    String method = 'momo',
  }) async {
    try {
      final res =
          await _client.rpc('record_offering_contribution', params: {
        'p_session_id': sessionId,
        'p_amount': amount,
        'p_payment_ref': paymentRef,
        'p_method': method,
      });
      final map =
          res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      return map['recorded'] == true;
    } catch (e) {
      // Never let basket bookkeeping break a confirmed gift.
      debugPrint('recordContribution failed: $e');
      return false;
    }
  }

  /// Basket totals for a church (`orgId == null`) or a whole organisation.
  Future<List<BasketSummaryRow>> fetchSummary({
    String? tenantId,
    String? orgId,
    int days = 30,
  }) async {
    final res = await _client.rpc('get_basket_summary', params: {
      'p_tenant_id': tenantId,
      'p_org_id': orgId,
      'p_days': days,
    });
    final list = res is List ? res : const [];
    return list
        .map((e) => BasketSummaryRow.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

final offeringBasketServiceProvider =
    Provider<OfferingBasketService>((ref) => OfferingBasketService(
          Supabase.instance.client,
        ));

/// Baskets visible to the current user (church + organisation-wide).
final offeringBasketsProvider =
    FutureProvider<List<OfferingBasket>>((ref) async {
  final tenant = ref.watch(currentTenantProvider);
  return ref.watch(offeringBasketServiceProvider).fetchBaskets(
        tenantId: tenant?.id,
        organizationId: tenant?.organizationId,
      );
});

/// The live offering session (if any) — polled so the Give tab reflects a
/// leader opening/closing the offering without an app restart.
final activeOfferingSessionProvider =
    FutureProvider<OfferingSession?>((ref) async {
  final tenant = ref.watch(currentTenantProvider);
  return ref
      .watch(offeringBasketServiceProvider)
      .fetchActiveSession(tenantId: tenant?.id);
});

/// Recent offering sessions (history / totals).
final offeringSessionsProvider =
    FutureProvider<List<OfferingSession>>((ref) async {
  final tenant = ref.watch(currentTenantProvider);
  return ref
      .watch(offeringBasketServiceProvider)
      .fetchSessions(tenantId: tenant?.id);
});

/// Basket summary keyed by `(tenantId|orgId, days)`. A Dart record key gives
/// value equality (a Map/List key would loop — see AGENTS.md RIVERPOD rule).
typedef BasketSummaryKey = ({String? tenantId, String? orgId, int days});

final basketSummaryProvider = FutureProvider.family<List<BasketSummaryRow>,
    BasketSummaryKey>((ref, key) async {
  return ref.watch(offeringBasketServiceProvider).fetchSummary(
        tenantId: key.tenantId,
        orgId: key.orgId,
        days: key.days,
      );
});
