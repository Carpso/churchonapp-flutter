import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One care signal for the "People to see today" queue.
class CareReason {
  const CareReason({
    required this.priority,
    required this.label,
  });

  final int priority;
  final String label;
}

class CarePerson {
  const CarePerson({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.visitorStatus,
    this.role,
    this.householdId,
    this.lastSeen,
    this.services = 0,
    this.baptized = false,
    this.followupId,
    this.followupType,
    this.followUpAt,
    this.followupNotes,
    this.priority = 9,
    this.reason = '',
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String? visitorStatus;
  final String? role;
  final String? householdId;
  final DateTime? lastSeen;
  final int services;
  final bool baptized;
  final String? followupId;
  final String? followupType;
  final DateTime? followUpAt;
  final String? followupNotes;
  final int priority;
  final String reason;

  bool get isDueNow => priority == 0;
  bool get isNewVisitor => priority == 2;
  bool get isAbsent => priority == 3;
  bool get isUnbaptised => priority == 4;

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory CarePerson.fromJson(Map<String, dynamic> j) => CarePerson(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'Unnamed',
        avatarUrl: j['avatar_url']?.toString(),
        visitorStatus: j['visitor_status']?.toString(),
        role: j['role']?.toString(),
        householdId: j['household_id']?.toString(),
        lastSeen: _date(j['last_seen']),
        services: (j['services'] as num?)?.toInt() ?? 0,
        baptized: j['baptized'] == true,
        followupId: j['followup_id']?.toString(),
        followupType: j['followup_type']?.toString(),
        followUpAt: _date(j['follow_up_at']),
        followupNotes: j['followup_notes']?.toString(),
        priority: (j['priority'] as num?)?.toInt() ?? 9,
        reason: j['reason']?.toString() ?? '',
      );
}

/// Result of `get_people_to_see_today` — the list plus per-signal counts.
class CareQueue {
  const CareQueue({
    this.people = const [],
    this.dueFollowups = 0,
    this.newVisitors = 0,
    this.absent = 0,
    this.unbaptised = 0,
  });

  final List<CarePerson> people;
  final int dueFollowups;
  final int newVisitors;
  final int absent;
  final int unbaptised;

  int get total => people.length;
  bool get isEmpty => people.isEmpty;

  factory CareQueue.fromJson(Map<String, dynamic> j) => CareQueue(
        people: ((j['people'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(CarePerson.fromJson)
            .toList(),
        dueFollowups: (j['due_followups'] as num?)?.toInt() ?? 0,
        newVisitors: (j['new_visitors'] as num?)?.toInt() ?? 0,
        absent: (j['absent'] as num?)?.toInt() ?? 0,
        unbaptised: (j['unbaptised'] as num?)?.toInt() ?? 0,
      );
}

class RetentionReport {
  const RetentionReport({
    this.months = const [],
    this.firstTime = 0,
    this.returning = 0,
    this.regular = 0,
    this.member = 0,
    this.inactive = 0,
  });

  final List<RetentionMonth> months;
  final int firstTime;
  final int returning;
  final int regular;
  final int member;
  final int inactive;

  factory RetentionReport.fromJson(Map<String, dynamic> j) {
    final t = (j['totals'] as Map<String, dynamic>?) ?? const {};
    return RetentionReport(
      months: ((j['months'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map((m) => RetentionMonth(
                month: m['month']?.toString() ?? '',
                firstTime: (m['first_time'] as num?)?.toInt() ?? 0,
                attended: (m['attended'] as num?)?.toInt() ?? 0,
              ))
          .toList(),
      firstTime: (t['first_time'] as num?)?.toInt() ?? 0,
      returning: (t['returning'] as num?)?.toInt() ?? 0,
      regular: (t['regular'] as num?)?.toInt() ?? 0,
      member: (t['member'] as num?)?.toInt() ?? 0,
      inactive: (t['inactive'] as num?)?.toInt() ?? 0,
    );
  }
}

class RetentionMonth {
  const RetentionMonth({
    required this.month,
    required this.firstTime,
    required this.attended,
  });

  final String month;
  final int firstTime;
  final int attended;
}

class Household {
  const Household({
    required this.id,
    required this.name,
    this.address,
    this.phoneNumber,
    this.envelopeCode,
    this.notes,
    this.headMemberId,
    this.isActive = true,
    this.memberCount = 0,
    this.members = const [],
  });

  final String id;
  final String name;
  final String? address;
  final String? phoneNumber;
  final String? envelopeCode;
  final String? notes;
  final String? headMemberId;
  final bool isActive;
  final int memberCount;
  final List<Map<String, dynamic>> members;

  factory Household.fromJson(Map<String, dynamic> j) {
    final members = ((j['household_members'] as List?) ??
            (j['members'] as List?) ??
            const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return Household(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? 'Household',
      address: j['address']?.toString(),
      phoneNumber: j['phone_number']?.toString(),
      envelopeCode: j['envelope_code']?.toString(),
      notes: j['notes']?.toString(),
      headMemberId: j['head_member_id']?.toString(),
      isActive: j['is_active'] != false,
      memberCount: (j['member_count'] as num?)?.toInt() ?? members.length,
      members: members,
    );
  }

  Household copyWith({String? name, String? address, String? phoneNumber, String? envelopeCode, String? notes}) =>
      Household(
        id: id,
        name: name ?? this.name,
        address: address ?? this.address,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        envelopeCode: envelopeCode ?? this.envelopeCode,
        notes: notes ?? this.notes,
        headMemberId: headMemberId,
        isActive: isActive,
        memberCount: memberCount,
        members: members,
      );
}

class ServicePlan {
  const ServicePlan({
    required this.id,
    required this.serviceDate,
    required this.title,
    this.setlistId,
    this.setlistTitle,
    this.speakers = const [],
    this.ushers = const [],
    this.musicians = const [],
    this.notes,
    this.isPublished = false,
  });

  final String id;
  final DateTime serviceDate;
  final String title;
  final String? setlistId;
  final String? setlistTitle;
  final List<String> speakers;
  final List<String> ushers;
  final List<String> musicians;
  final String? notes;
  final bool isPublished;

  factory ServicePlan.fromJson(Map<String, dynamic> j) => ServicePlan(
        id: j['id']?.toString() ?? '',
        serviceDate:
            DateTime.tryParse(j['service_date']?.toString() ?? '') ??
                DateTime.now(),
        title: j['title']?.toString() ?? 'Service',
        setlistId: j['setlist_id']?.toString(),
        setlistTitle: j['setlist_title']?.toString(),
        speakers: ((j['speakers'] as List?) ?? const []).map((e) => e.toString()).toList(),
        ushers: ((j['ushers'] as List?) ?? const []).map((e) => e.toString()).toList(),
        musicians: ((j['musicians'] as List?) ?? const []).map((e) => e.toString()).toList(),
        notes: j['notes']?.toString(),
        isPublished: j['is_published'] == true,
      );

  ServicePlan copyWith({
    String? title,
    String? setlistId,
    List<String>? speakers,
    List<String>? ushers,
    List<String>? musicians,
    String? notes,
    bool? isPublished,
  }) =>
      ServicePlan(
        id: id,
        serviceDate: serviceDate,
        title: title ?? this.title,
        setlistId: setlistId ?? this.setlistId,
        setlistTitle: setlistTitle,
        speakers: speakers ?? this.speakers,
        ushers: ushers ?? this.ushers,
        musicians: musicians ?? this.musicians,
        notes: notes ?? this.notes,
        isPublished: isPublished ?? this.isPublished,
      );
}

class VolunteerSlot {
  const VolunteerSlot({
    required this.id,
    required this.userId,
    required this.roleLabel,
    required this.serviceDate,
    this.userName,
    this.phoneNumber,
    this.notes,
    this.notifiedAt,
  });

  final String id;
  final String userId;
  final String roleLabel;
  final DateTime serviceDate;
  final String? userName;
  final String? phoneNumber;
  final String? notes;
  final DateTime? notifiedAt;

  bool get isNotified => notifiedAt != null;
  /// A manual slot has no member id — the WhatsApp nudge then needs the number
  /// captured at the time the slot was created.
  bool get isManual => userId.isEmpty;

  factory VolunteerSlot.fromJson(Map<String, dynamic> j) => VolunteerSlot(
        id: j['id']?.toString() ?? '',
        userId: j['user_id']?.toString() ?? '',
        roleLabel: j['role_label']?.toString() ?? 'Volunteer',
        serviceDate:
            DateTime.tryParse(j['service_date']?.toString() ?? '') ??
                DateTime.now(),
        userName: (j['user_name'] ?? j['volunteer_name'])?.toString() ??
            j['full_name']?.toString(),
        phoneNumber: j['phone_number']?.toString(),
        notes: j['notes']?.toString(),
        notifiedAt: DateTime.tryParse(j['notified_at']?.toString() ?? ''),
      );
}

/// Scoped permissions a pastor can hand to an usher/deacon (item 12).
class Delegation {
  const Delegation({
    required this.id,
    required this.userId,
    required this.scope,
    this.userName,
  });

  final String id;
  final String userId;
  final String scope;
  final String? userName;

  factory Delegation.fromJson(Map<String, dynamic> j) => Delegation(
        id: j['id']?.toString() ?? '',
        userId: j['user_id']?.toString() ?? '',
        scope: j['scope']?.toString() ?? '',
        userName: j['user_name']?.toString() ?? j['full_name']?.toString(),
      );
}

/// A person row from the unified people search (item 10).
class PersonHit {
  const PersonHit({
    required this.id,
    required this.name,
    this.phone,
    this.role,
    this.visitorStatus,
    this.householdName,
    this.avatarUrl,
    this.servicesAttended = 0,
  });

  final String id;
  final String name;
  final String? phone;
  final String? role;
  final String? visitorStatus;
  final String? householdName;
  final String? avatarUrl;
  final int servicesAttended;

  factory PersonHit.fromJson(Map<String, dynamic> j) => PersonHit(
        id: j['id']?.toString() ?? '',
        name: j['full_name']?.toString() ?? 'Unnamed',
        phone: j['phone_number']?.toString(),
        role: j['role']?.toString(),
        visitorStatus: j['visitor_status']?.toString(),
        householdName: j['household_name']?.toString(),
        avatarUrl: j['avatar_url']?.toString(),
        servicesAttended: (j['services_attended'] as num?)?.toInt() ?? 0,
      );
}

/// Single entry point for the pastoral-care ChMS features (items 1,2,4,5,
/// 6,8,9,10,11,12). Every write goes through a SECURITY DEFINER RPC so a
/// usher/deacon never needs direct table write rights.
class CareService {
  CareService(this._client);

  final SupabaseClient _client;


  // ── 4. People to see today ──────────────────────────────────────────────
  Future<CareQueue> fetchCareQueue(String tenantId) async {
    final res = await _client.rpc('get_people_to_see_today', params: {
      'p_tenant_id': tenantId,
    });
    final map = (res as Map<String, dynamic>?) ?? const {};
    return CareQueue.fromJson(map);
  }



  // ── 1. Visitor status (auto-creates the first-visit follow-up) ─────────
  Future<bool> setVisitorStatus(
    String userId,
    String status, {
    String? actorId,
  }) async {
    final res = await _client.rpc('set_visitor_status', params: {
      'p_user_id': userId,
      'p_visitor_status': status,
      if (actorId != null) 'p_actor': actorId,
    });
    // The RPC returns { first_visit: bool, followup_id: uuid } — surface the
    // auto-created follow-up so the UI can confirm it.
    final map = (res as Map<String, dynamic>?) ?? const {};
    return map['first_visit'] == true && map['followup_id'] != null;
  }

  // ── 2. Households ──────────────────────────────────────────────────────
  Future<List<Household>> fetchHouseholds(String tenantId) async {
    final res = await _client
        .from('households')
        .select('id, name, address, phone_number, envelope_code, notes,'
            ' head_member_id, is_active, created_at')
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('name');
    if (res.isEmpty) return const [];
    final ids = (res as List).map((e) => e['id'] as String).toList();
    final members = await _client
        .from('profiles')
        .select('id, full_name, role, phone_number, household_id')
        .inFilter('household_id', ids);
    final byHouse = <String, List<Map<String, dynamic>>>{};
    for (final m in (members as List)) {
      final map = Map<String, dynamic>.from(m);
      final hid = map['household_id']?.toString();
      if (hid == null) continue;
      byHouse.putIfAbsent(hid, () => []).add(map);
    }
    return (res as List)
        .map((e) {
      final map = Map<String, dynamic>.from(e);
      final hid = map['id']?.toString() ?? '';
      final mem = byHouse[hid] ?? const <Map<String, dynamic>>[];
      return Household.fromJson({
        ...map,
        'members': mem,
        'member_count': mem.length,
      });
    }).toList();
  }



  Future<void> createHousehold({
    void Function()? onChanged,
    required String tenantId,
    required String name,
    String? address,
    String? phoneNumber,
    String? envelopeCode,
    String? notes,
  }) async {
    await _client.from('households').insert({
      'tenant_id': tenantId,
      'name': name,
      if (address != null && address.isNotEmpty) 'address': address,
      if (phoneNumber != null && phoneNumber.isNotEmpty)
        'phone_number': phoneNumber,
      if (envelopeCode != null && envelopeCode.isNotEmpty)
        'envelope_code': envelopeCode,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'created_by': _client.auth.currentUser?.id,
    });
    _invalidateHouseholds(onChanged);
  }

  Future<void> updateHousehold(
    String id,
    Map<String, dynamic> patch, {
    void Function()? onChanged,
  }) async {
    await _client.from('households').update(patch).eq('id', id);
    _invalidateHouseholds(onChanged);
  }

  Future<void> deleteHousehold(String id, {void Function()? onChanged}) async {
    await _client.from('households').update({'is_active': false}).eq('id', id);
    _invalidateHouseholds(onChanged);
  }

  /// Households are cached per-tenant by a `householdsProvider` family. Widgets
  /// hold a `WidgetRef` (not a `Ref`) in Riverpod 3, so the caller passes an
  /// `onChanged` callback instead of a Ref and the widget decides what to
  /// invalidate.
  void _invalidateHouseholds(void Function()? onChanged) {
    onChanged?.call();
  }

  Future<void> addMemberToHousehold(String userId, String householdId,
      {void Function()? onChanged}) async {
    await _client
        .from('profiles')
        .update({'household_id': householdId})
        .eq('id', userId);
    _invalidateHouseholds(onChanged);
  }

  Future<void> removeMemberFromHousehold(String userId, {void Function()? onChanged}) async {
    await _client
        .from('profiles')
        .update({'household_id': null})
        .eq('id', userId);
    _invalidateHouseholds(onChanged);
  }

  /// 2 (cont). Household giving statement (server-derived from transactions).
  Future<Map<String, dynamic>> householdGivingStatement(
    String householdId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final now = DateTime.now();
    final start = from ?? DateTime(now.year, 1, 1);
    final end = to ?? now;
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final res = await _client.rpc('get_household_giving_statement', params: {
      'p_household_id': householdId,
      'p_from': fmt(start),
      'p_to': fmt(end),
    });
    return (res as Map<String, dynamic>?) ?? const {};
  }

  // ── 5. Order of service ────────────────────────────────────────────────
  Future<List<ServicePlan>> fetchServicePlans(String tenantId,
      {int limit = 30}) async {
    final res = await _client
        .from('service_plans')
        .select('id, service_date, title, setlist_id, speakers, ushers,'
            ' musicians, notes, is_published,'
            ' worship_setlists!inner(title)')
        .eq('tenant_id', tenantId)
        .order('service_date', ascending: false)
        .limit(limit);
    return (res as List).map((e) {
      final map = Map<String, dynamic>.from(e);
      final set = map['worship_setlists'];
      if (set is Map) map['setlist_title'] = set['title'];
      return ServicePlan.fromJson(map);
    }).toList();
  }



  Future<String> upsertServicePlan({
    String? id,
    required String tenantId,
    required DateTime serviceDate,
    required String title,
    String? setlistId,
    List<String> speakers = const [],
    List<String> ushers = const [],
    List<String> musicians = const [],
    String? notes,
  }) async {
    String day(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final row = {
      'tenant_id': tenantId,
      'service_date': day(serviceDate),
      'title': title,
      'setlist_id': setlistId,
      'speakers': speakers,
      'ushers': ushers,
      'musicians': musicians,
      'notes': notes,
      if (id == null) 'created_by': _client.auth.currentUser?.id,
    };
    if (id == null) {
      final res = await _client.from('service_plans').insert(row).select('id').single();
      return res['id'] as String;
    }
    await _client.from('service_plans').update(row).eq('id', id);
    return id;
  }

  Future<void> publishServicePlan(String planId, bool publish) async {
    await _client.rpc('publish_service_plan', params: {
      'p_plan_id': planId,
      'p_publish': publish,
    });
  }

  Future<void> deleteServicePlan(String id) async {
    await _client.from('service_plans').delete().eq('id', id);
  }

  // ── 8. Visitor retention ───────────────────────────────────────────────
  Future<RetentionReport> fetchRetention(String tenantId,
      {int months = 6}) async {
    final res = await _client.rpc('get_visitor_retention', params: {
      'p_tenant_id': tenantId,
      'p_months': months,
    });
    return RetentionReport.fromJson(
        (res as Map<String, dynamic>?) ?? const {});
  }



  // ── 11. Auto-tag regular attenders ──────────────────────────────────────
  Future<Map<String, dynamic>> refreshAttendanceTags(
    String tenantId, {
    int threshold = 6,
    int windowMonths = 4,
  }) async {
    final res = await _client.rpc('refresh_attendance_tags', params: {
      'p_tenant_id': tenantId,
      'p_regular_threshold': threshold,
      'p_window_months': windowMonths,
    });
    return (res as Map<String, dynamic>?) ?? const {};
  }

  // ── 9. Volunteer rota ──────────────────────────────────────────────────
  Future<List<VolunteerSlot>> fetchRota(String tenantId,
      {DateTime? from, DateTime? to}) async {
    final start = from ?? DateTime.now();
    final end = to ?? start.add(const Duration(days: 60));
    final res = await _client
        .from('volunteer_roster')
        .select('id, user_id, volunteer_name, role_label, service_date, notes,'
            ' notified_at, profiles!left(full_name)')
        .eq('tenant_id', tenantId)
        .gte('service_date', _day(start))
        .lte('service_date', _day(end))
        .order('service_date', ascending: true);
    return (res as List).map((e) {
      final map = Map<String, dynamic>.from(e);
      // LEFT join: manual slots (no user_id) have no profile row, so the
      // embedded object is null and we fall back to volunteer_name.
      final p = map['profiles'];
      if (p is Map) {
        map['user_name'] = p['full_name'];
      } else {
        map['user_name'] = map['volunteer_name'];
      }
      return VolunteerSlot.fromJson(map);
    }).toList();
  }



  Future<void> assignVolunteer({
    required String tenantId,
    String? userId,
    String? volunteerName,
    String? phoneNumber,
    required String roleLabel,
    required DateTime serviceDate,
    String? notes,
  }) async {
    // A slot references either a known member or a manual name — the table's
    // CHECK constraint requires exactly one of them.
    await _client.from('volunteer_roster').insert({
      'tenant_id': tenantId,
      if (userId != null && userId.isNotEmpty) 'user_id': userId,
      if (userId == null || userId.isEmpty)
        'volunteer_name': (volunteerName ?? '').trim().isEmpty
            ? 'Volunteer'
            : (volunteerName ?? '').trim(),
      'role_label': roleLabel,
      'service_date': _day(serviceDate),
      if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
        'phone_number': phoneNumber.trim(),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'created_by': _client.auth.currentUser?.id,
    });
  }

  Future<void> removeVolunteer(String id) async {
    await _client.from('volunteer_roster').delete().eq('id', id);
  }

  Future<void> markNotified(String id) async {
    await _client
        .from('volunteer_roster')
        .update({'notified_at': DateTime.now().toIso8601String()})
        .eq('id', id);
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ── 10. Unified people search ──────────────────────────────────────────
  Future<List<PersonHit>> searchPeople(
    String tenantId,
    String query, {
    int limit = 40,
  }) async {
    final q = query.trim();
    var sel = _client
        .from('profiles')
        .select('id, full_name, role, phone_number, visitor_status,'
            ' avatar_url, services_attended, household_id')
        .eq('tenant_id', tenantId)
        .filter('deleted_at', 'is', 'null');
    if (q.isNotEmpty) {
      sel = sel.or(
        'full_name.ilike.%$q%,phone_number.ilike.%$q%,role.ilike.%$q%',
      );
    }
    final res = await sel.order('full_name').limit(limit);
    final rows = (res as List)
        .map((e) => PersonHit.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (rows.isEmpty) return rows;

    // Attach household names in one follow-up (avoid N+1).
    final hids = rows
        .map((r) => r.id)
        .toList();
    final withHouse = await _client
        .from('profiles')
        .select('id, household_id, households!inner(name)')
        .inFilter('id', hids);
    final houseName = <String, String>{};
    for (final r in (withHouse as List)) {
      final h = r['households'];
      if (h is Map) houseName[r['id'].toString()] = h['name'].toString();
    }
    return rows
        .map((r) => PersonHit(
              id: r.id,
              name: r.name,
              phone: r.phone,
              role: r.role,
              visitorStatus: r.visitorStatus,
              householdName: houseName[r.id],
              avatarUrl: r.avatarUrl,
              servicesAttended: r.servicesAttended,
            ))
        .toList();
  }

  // ── 12. Delegations ────────────────────────────────────────────────────
  Future<List<Delegation>> fetchDelegations(String tenantId) async {
    final res = await _client
        .from('role_delegations')
        .select('id, user_id, scope, profiles!inner(full_name)')
        .eq('tenant_id', tenantId);
    return (res as List).map((e) {
      final map = Map<String, dynamic>.from(e);
      final p = map['profiles'];
      if (p is Map) map['user_name'] = p['full_name'];
      return Delegation.fromJson(map);
    }).toList();
  }



  Future<void> grantScope({
    required String tenantId,
    required String userId,
    required String scope,
  }) async {
    await _client.from('role_delegations').upsert({
      'tenant_id': tenantId,
      'user_id': userId,
      'scope': scope,
      'granted_by': _client.auth.currentUser?.id,
    }, onConflict: 'tenant_id,user_id,scope');
  }

  Future<void> revokeScope(String id) async {
    await _client.from('role_delegations').delete().eq('id', id);
  }

  Future<bool> hasScope(String scope) async {
    final res = await _client.rpc('has_delegated_scope', params: {
      'p_scope': scope,
    });
    return res == true;
  }

  /// Mark a pastoral follow-up done (item 4 action).
  Future<void> completeFollowup(String followupId) async {
    await _client.from('pastoral_followups').update({
      'status': 'done',
      'completed_at': DateTime.now().toIso8601String(),
    }).eq('id', followupId);
  }

  /// Debug helper — parse raw json for tests.
  static Map<String, dynamic> decode(String s) =>
      jsonDecode(s) as Map<String, dynamic>;
}

// ═══════════════════════════════════════════════════════════════════════════
// Providers (top-level so any screen can watch/invalidate them directly)
// ═══════════════════════════════════════════════════════════════════════════

final careServiceProvider =
    Provider<CareService>((ref) => CareService(Supabase.instance.client));

/// Item 4 — the pastoral care queue for one tenant.
final careQueueProvider =
    FutureProvider.autoDispose.family<CareQueue, String>((ref, tenantId) async {
  return ref.watch(careServiceProvider).fetchCareQueue(tenantId);
});

/// Item 2 — households for one tenant.
final householdsProvider =
    FutureProvider.autoDispose.family<List<Household>, String>(
        (ref, tenantId) async {
  return ref.watch(careServiceProvider).fetchHouseholds(tenantId);
});

/// Item 5 — order-of-service plans.
final servicePlansProvider =
    FutureProvider.autoDispose.family<List<ServicePlan>, String>(
        (ref, tenantId) async {
  return ref.watch(careServiceProvider).fetchServicePlans(tenantId);
});

/// Item 8 — visitor retention report.
final retentionProvider =
    FutureProvider.autoDispose.family<RetentionReport, String>(
        (ref, tenantId) async {
  return ref.watch(careServiceProvider).fetchRetention(tenantId);
});

/// Item 9 — volunteer rota.
final volunteerRotaProvider =
    FutureProvider.autoDispose.family<List<VolunteerSlot>, String>(
        (ref, tenantId) async {
  return ref.watch(careServiceProvider).fetchRota(tenantId);
});

/// Item 12 — scoped delegations granted by leadership.
final delegationsProvider =
    FutureProvider.autoDispose.family<List<Delegation>, String>(
        (ref, tenantId) async {
  return ref.watch(careServiceProvider).fetchDelegations(tenantId);
});

