import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

// ============================================================================
// Models
// ============================================================================

class MeetingEntitlement {
  final bool pro;
  final int maxParticipants;
  final bool recording;
  final bool recurring;
  final String? plan;
  final DateTime? expiresAt;
  final String status;

  const MeetingEntitlement({
    required this.pro,
    required this.maxParticipants,
    required this.recording,
    required this.recurring,
    this.plan,
    this.expiresAt,
    this.status = 'none',
  });

  /// Newer alias keys (is_pro / can_record / can_recur).
  bool get isPro => pro;
  bool get canRecord => recording;
  bool get canRecur => recurring;

  factory MeetingEntitlement.fromMap(Map<String, dynamic> map) {
    final isPro = map['is_pro'] == true || map['pro'] == true;
    return MeetingEntitlement(
      pro: isPro,
      maxParticipants: (map['max_participants'] as num?)?.toInt() ?? 5,
      recording: map['can_record'] == true || map['recording'] == true,
      recurring: map['can_recur'] == true || map['recurring'] == true,
      plan: map['plan']?.toString(),
      expiresAt: map['expires_at'] != null
          ? DateTime.tryParse(map['expires_at'].toString())
          : null,
      status: map['status']?.toString() ?? (isPro ? 'active' : 'none'),
    );
  }

  static const free = MeetingEntitlement(
    pro: false,
    maxParticipants: 5,
    recording: false,
    recurring: false,
  );
}

/// A server-issued payment request (reference + server-derived amount).
class MeetingPaymentRequest {
  final String paymentRef;
  final double amountKwacha;
  final String plan;

  const MeetingPaymentRequest({
    required this.paymentRef,
    required this.amountKwacha,
    required this.plan,
  });
}

class BusinessMeeting {
  final String id;
  final String? tenantId;
  final String hostId;
  final String title;
  final String? description;
  final String meetingCode;
  final String status; // scheduled | live | active | ended | cancelled
  final int maxParticipants;
  final bool isRecorded;
  final DateTime? scheduledAt;
  final int durationMinutes;
  final String timezone;
  final bool isRecurring;
  final String? recurrenceRule;
  final String? parentMeetingId;
  final String? recordingUrl;
  final String recordingStatus;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? createdAt;

  BusinessMeeting({
    required this.id,
    required this.tenantId,
    required this.hostId,
    required this.title,
    required this.description,
    required this.meetingCode,
    required this.status,
    required this.maxParticipants,
    required this.isRecorded,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.timezone,
    required this.isRecurring,
    required this.recurrenceRule,
    required this.parentMeetingId,
    required this.recordingUrl,
    required this.recordingStatus,
    required this.startedAt,
    required this.endedAt,
    required this.createdAt,
  });

  bool get isLive => status == 'live' || status == 'active';
  bool get isEnded => status == 'ended' || status == 'cancelled';

  factory BusinessMeeting.fromMap(Map<String, dynamic> map) {
    return BusinessMeeting(
      id: map['id'].toString(),
      tenantId: map['tenant_id']?.toString(),
      hostId: map['host_id'].toString(),
      title: (map['title'] ?? 'Business Meeting').toString(),
      description: map['description']?.toString(),
      meetingCode: (map['meeting_code'] ?? '').toString(),
      status: (map['status'] ?? 'scheduled').toString(),
      maxParticipants: (map['max_participants'] as num?)?.toInt() ?? 5,
      isRecorded: map['is_recorded'] == true,
      scheduledAt: _parse(map['scheduled_at']),
      durationMinutes: (map['duration_minutes'] as num?)?.toInt() ?? 60,
      timezone: (map['timezone'] ?? 'Africa/Lusaka').toString(),
      isRecurring: map['is_recurring'] == true,
      recurrenceRule: map['recurrence_rule']?.toString(),
      parentMeetingId: map['parent_meeting_id']?.toString(),
      recordingUrl: map['recording_url']?.toString(),
      recordingStatus: (map['recording_status'] ?? 'none').toString(),
      startedAt: _parse(map['started_at']),
      endedAt: _parse(map['ended_at']),
      createdAt: _parse(map['created_at']),
    );
  }

  static DateTime? _parse(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}

class MeetingParticipant {
  final String id;
  final String meetingId;
  final String userId;
  final String role;
  final bool isMuted;
  final bool isVideoOff;
  final DateTime? joinedAt;
  final DateTime? leftAt;

  // Enriched client-side from `profiles`.
  String? fullName;
  String? avatarUrl;

  bool get isActive => leftAt == null;
  bool get isHost => role == 'host';

  MeetingParticipant({
    required this.id,
    required this.meetingId,
    required this.userId,
    required this.role,
    required this.isMuted,
    required this.isVideoOff,
    required this.joinedAt,
    required this.leftAt,
    this.fullName,
    this.avatarUrl,
  });

  factory MeetingParticipant.fromMap(Map<String, dynamic> map) {
    return MeetingParticipant(
      id: map['id'].toString(),
      meetingId: map['meeting_id'].toString(),
      userId: map['user_id'].toString(),
      role: (map['role'] ?? 'participant').toString(),
      isMuted: map['is_muted'] == true,
      isVideoOff: map['is_video_off'] == true,
      joinedAt: BusinessMeeting._parse(map['joined_at']),
      leftAt: BusinessMeeting._parse(map['left_at']),
    );
  }
}

class MeetingAgendaItem {
  final String id;
  final String meetingId;
  final String title;
  final int position;
  final bool isDone;

  MeetingAgendaItem({
    required this.id,
    required this.meetingId,
    required this.title,
    required this.position,
    required this.isDone,
  });

  factory MeetingAgendaItem.fromMap(Map<String, dynamic> map) {
    return MeetingAgendaItem(
      id: map['id'].toString(),
      meetingId: map['meeting_id'].toString(),
      title: (map['title'] ?? '').toString(),
      position: (map['position'] as num?)?.toInt() ?? 0,
      isDone: map['is_done'] == true,
    );
  }
}

class MeetingRsvp {
  final String id;
  final String meetingId;
  final String userId;
  final String status; // invited | accepted | declined
  String? fullName;
  String? avatarUrl;

  MeetingRsvp({
    required this.id,
    required this.meetingId,
    required this.userId,
    required this.status,
    this.fullName,
    this.avatarUrl,
  });

  factory MeetingRsvp.fromMap(Map<String, dynamic> map) {
    return MeetingRsvp(
      id: map['id'].toString(),
      meetingId: map['meeting_id'].toString(),
      userId: map['user_id'].toString(),
      status: (map['status'] ?? 'invited').toString(),
    );
  }
}

class MeetingSignal {
  final String id;
  final String meetingId;
  final String senderId;
  final String? receiverId;
  final String signalType;
  final Map<String, dynamic>? payload;
  final DateTime? createdAt;

  MeetingSignal({
    required this.id,
    required this.meetingId,
    required this.senderId,
    required this.receiverId,
    required this.signalType,
    required this.payload,
    required this.createdAt,
  });

  factory MeetingSignal.fromMap(Map<String, dynamic> map) {
    return MeetingSignal(
      id: map['id'].toString(),
      meetingId: map['meeting_id'].toString(),
      senderId: map['sender_id'].toString(),
      receiverId: map['receiver_id']?.toString(),
      signalType: (map['signal_type'] ?? '').toString(),
      payload: map['payload'] is Map
          ? Map<String, dynamic>.from(map['payload'] as Map)
          : null,
      createdAt: BusinessMeeting._parse(map['created_at']),
    );
  }
}

class MeetingNote {
  final String id;
  final String meetingId;
  final String authorId;
  final String content;
  final bool isPrivate;
  final DateTime createdAt;

  MeetingNote({
    required this.id,
    required this.meetingId,
    required this.authorId,
    required this.content,
    this.isPrivate = false,
    required this.createdAt,
  });

  factory MeetingNote.fromMap(Map<String, dynamic> map) {
    return MeetingNote(
      id: map['id'].toString(),
      meetingId: map['meeting_id']?.toString() ?? '',
      authorId: map['author_id']?.toString() ?? '',
      content: (map['content'] ?? '').toString(),
      isPrivate: map['is_private'] == true,
      createdAt: BusinessMeeting._parse(map['created_at']) ?? DateTime.now(),
    );
  }
}

class MeetingVote {
  final String meetingId;
  final String voterId;
  final String option;

  MeetingVote({required this.meetingId, required this.voterId, required this.option});

  factory MeetingVote.fromMap(Map<String, dynamic> map) {
    return MeetingVote(
      meetingId: map['meeting_id'].toString(),
      voterId: map['voter_id'].toString(),
      option: (map['option_selected'] ?? '').toString(),
    );
  }
}

// ============================================================================
// Service
// ============================================================================

class MeetingService {
  final SupabaseClient _client;
  MeetingService(this._client);

  SupabaseClient get client => _client;
  String? get currentUserId => _client.auth.currentUser?.id;

  // ── Entitlement ───────────────────────────────────────────────────────────
  Future<MeetingEntitlement> getEntitlement({String? tenantId}) async {
    try {
      final res = await _client.rpc('meeting_entitlement', params: {
        'p_tenant_id': tenantId,
      });
      if (res is Map) return MeetingEntitlement.fromMap(Map<String, dynamic>.from(res));
      return MeetingEntitlement.free;
    } catch (e) {
      debugPrint('meeting_entitlement failed: $e');
      return MeetingEntitlement.free; // fail closed
    }
  }

  // ── Create / fetch ────────────────────────────────────────────────────────
  Future<BusinessMeeting> createMeeting({
    required String title,
    String? description,
    DateTime? scheduledAt,
    int durationMinutes = 60,
    String timezone = 'Africa/Lusaka',
    int? maxParticipants,
    bool isRecurring = false,
    String? recurrenceRule,
    List<String> agenda = const [],
  }) async {
    final res = await _client.rpc('create_business_meeting', params: {
      'p_title': title,
      'p_scheduled_at': (scheduledAt ?? DateTime.now()).toUtc().toIso8601String(),
      'p_duration_minutes': durationMinutes,
      'p_description': description,
      'p_timezone': timezone,
      'p_max_participants': maxParticipants,
      'p_is_recurring': isRecurring,
      'p_recurrence_rule': recurrenceRule,
      'p_agenda': agenda,
    });
    final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    if (map['success'] != true) {
      throw MeetingException(
        map['message']?.toString() ?? map['error']?.toString() ?? 'Could not create meeting',
      );
    }
    final created = await fetchMeeting(map['id'].toString());
    if (created == null) {
      throw MeetingException('Meeting was created but could not be loaded');
    }
    return created;
  }

  Future<BusinessMeeting?> fetchMeeting(String id) async {
    final row = await _client
        .from('business_meetings')
        .select('*')
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : BusinessMeeting.fromMap(row);
  }

  Future<BusinessMeeting?> fetchMeetingByCode(String code) async {
    final row = await _client
        .from('business_meetings')
        .select('*')
        .eq('meeting_code', code.trim().toUpperCase())
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : BusinessMeeting.fromMap(row);
  }

  Future<List<BusinessMeeting>> fetchMyMeetings() async {
    final uid = currentUserId;
    if (uid == null) return [];
    // Meetings I host or that I joined.
    final hosted = await _client
        .from('business_meetings')
        .select('*')
        .eq('host_id', uid)
        .order('scheduled_at', ascending: false)
        .limit(50);
    final joinedIds = await _client
        .from('meeting_participants')
        .select('meeting_id')
        .eq('user_id', uid)
        .limit(100);
    final ids = <String>{
      ...joinedIds.map((e) => e['meeting_id'].toString()),
    };
    final invited = await _client
        .from('meeting_rsvps')
        .select('meeting_id')
        .eq('user_id', uid)
        .limit(100);
    ids.addAll(invited.map((e) => e['meeting_id'].toString()));

    final List<dynamic> others = ids.isEmpty
        ? const []
        : await _client
            .from('business_meetings')
            .select('*')
            .inFilter('id', ids.toList())
            .order('scheduled_at', ascending: false)
            .limit(50);

    final all = <String, BusinessMeeting>{};
    for (final r in [...hosted, ...others]) {
      final m = BusinessMeeting.fromMap(Map<String, dynamic>.from(r));
      all[m.id] = m;
    }
    final list = all.values.toList()
      ..sort((a, b) {
        final at = a.scheduledAt ?? a.createdAt ?? DateTime(0);
        final bt = b.scheduledAt ?? b.createdAt ?? DateTime(0);
        return bt.compareTo(at);
      });
    return list;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _rpcOk(String fn, Map<String, dynamic> params) async {
    final res = await _client.rpc(fn, params: params);
    final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    if (map['success'] != true) {
      throw MeetingException(
        map['message']?.toString() ?? map['error']?.toString() ?? 'Request failed',
      );
    }
    return map;
  }

  Future<Map<String, dynamic>> joinMeeting(String meetingId) =>
      _rpcOk('join_business_meeting', {'p_meeting_id': meetingId});

  Future<Map<String, dynamic>> leaveMeeting(String meetingId) =>
      _rpcOk('leave_business_meeting', {'p_meeting_id': meetingId});

  Future<Map<String, dynamic>> startMeeting(String meetingId) =>
      _rpcOk('start_business_meeting', {'p_meeting_id': meetingId});

  Future<Map<String, dynamic>> endMeeting(String meetingId) =>
      _rpcOk('end_business_meeting', {'p_meeting_id': meetingId});

  Future<Map<String, dynamic>> cancelMeeting(String meetingId) =>
      _rpcOk('cancel_business_meeting', {'p_meeting_id': meetingId});

  Future<void> setMediaState(String meetingId, {required bool muted, required bool videoOff}) =>
      _rpcOk('set_meeting_media', {
        'p_meeting_id': meetingId,
        'p_is_muted': muted,
        'p_is_video_off': videoOff,
      }).then((_) {});

  Future<void> muteAll(String meetingId) =>
      _rpcOk('mute_all_meeting_participants', {'p_meeting_id': meetingId}).then((_) {});

  Future<void> setRecording(String meetingId, String? url, String status) =>
      _rpcOk('set_meeting_recording', {
        'p_meeting_id': meetingId,
        'p_url': url,
        'p_status': status,
      }).then((_) {});

  // ── Agenda ────────────────────────────────────────────────────────────────
  Future<void> addAgendaItem(String meetingId, String title) => _rpcOk(
        'add_meeting_agenda_item',
        {'p_meeting_id': meetingId, 'p_title': title},
      ).then((_) {});

  Future<void> updateAgendaItem(String itemId, {String? title, bool? isDone}) => _rpcOk(
        'update_meeting_agenda_item',
        {'p_item_id': itemId, 'p_title': title, 'p_is_done': isDone},
      ).then((_) {});

  Future<void> deleteAgendaItem(String itemId) =>
      _rpcOk('delete_meeting_agenda_item', {'p_item_id': itemId}).then((_) {});

  Future<void> reorderAgenda(String meetingId, List<String> itemIds) => _rpcOk(
        'reorder_meeting_agenda_items',
        {'p_meeting_id': meetingId, 'p_item_ids': itemIds},
      ).then((_) {});

  // ── Invites / RSVP ────────────────────────────────────────────────────────
  Future<int> inviteParticipants(String meetingId, List<String> userIds) async {
    final map = await _rpcOk(
      'invite_meeting_participants',
      {'p_meeting_id': meetingId, 'p_user_ids': userIds},
    );
    return (map['invited'] as num?)?.toInt() ?? 0;
  }

  Future<void> respondRsvp(String meetingId, String status) => _rpcOk(
        'respond_meeting_rsvp',
        {'p_meeting_id': meetingId, 'p_status': status},
      ).then((_) {});

  // ── Searchable user picker (tenant-scoped) ────────────────────────────────
  Future<List<Map<String, dynamic>>> searchUsers(String query, {String? tenantId}) async {
    var q = _client
        .from('profiles')
        .select('id, full_name, avatar_url, role, tenant_id');
    if (tenantId != null && tenantId.isNotEmpty) {
      q = q.eq('tenant_id', tenantId);
    }
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      q = q.ilike('full_name', '%$trimmed%');
    }
    return List<Map<String, dynamic>>.from(await q.limit(30));
  }

  // ── Notes / Votes ─────────────────────────────────────────────────────────
  Future<void> saveNote(String meetingId, String content, {bool isPrivate = false}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('meeting_notes').insert({
      'meeting_id': meetingId,
      'author_id': user.id,
      'content': content,
      'is_private': isPrivate,
    });
  }

  Future<void> deleteNote(String noteId) async {
    await _client.from('meeting_notes').delete().eq('id', noteId);
  }

  Future<void> castVote(String meetingId, String option) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('meeting_votes').upsert({
      'meeting_id': meetingId,
      'voter_id': user.id,
      'option_selected': option,
    });
  }

  // ── Signaling ─────────────────────────────────────────────────────────────
  Future<void> sendSignal({
    required String meetingId,
    String? receiverId,
    required String signalType,
    Map<String, dynamic>? payload,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _client.from('meeting_signaling').insert({
      'meeting_id': meetingId,
      'sender_id': uid,
      'receiver_id': receiverId,
      'signal_type': signalType,
      'payload': payload,
    });
  }

  Future<void> clearSignal(String signalId) async {
    try {
      await _client.from('meeting_signaling').delete().eq('id', signalId);
    } catch (e) {
      debugPrint('clearSignal failed: $e');
    }
  }

  // ── Pro subscription (SERVER-VERIFIED) ─────────────────────────────────────
  // The client NEVER decides price, plan or entitlement: the price is derived
  // server-side, a pending `coa_payments` anchor is pre-created, and activation
  // requires a CONFIRMED payment. See migration 20261221_pro_meeting_*.

  /// Re-derives the price SERVER-SIDE, pre-creates the pending payment anchor
  /// and returns the payment reference + amount to pay.
  Future<MeetingPaymentRequest> requestSubscription({
    required String tenantId,
    required String plan,
  }) async {
    final res = await _client.rpc(
      'request_meeting_subscription',
      params: {'p_tenant_id': tenantId, 'p_plan': plan},
    );
    final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    if (map['success'] != true) {
      throw MeetingException(
        map['error']?.toString() ?? 'Could not start subscription payment',
      );
    }
    return MeetingPaymentRequest(
      paymentRef: map['payment_ref'].toString(),
      amountKwacha: (map['amount_kwacha'] as num).toDouble(),
      plan: map['plan']?.toString() ?? plan,
    );
  }

  /// Flips to `active` ONLY against a confirmed payment; idempotent. A DB
  /// trigger also auto-activates on confirmation.
  Future<bool> activateSubscription(String paymentRef) async {
    final res = await _client.rpc(
      'activate_meeting_subscription',
      params: {'p_payment_ref': paymentRef},
    );
    final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    return map['success'] == true;
  }

  /// Owner/staff cancel.
  Future<bool> cancelSubscription(String subscriptionId) async {
    final res = await _client.rpc(
      'cancel_meeting_subscription',
      params: {'p_subscription_id': subscriptionId},
    );
    final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    return map['success'] == true;
  }

  /// Gate EVERY pro action on the server entitlement (fails closed).
  Future<bool> canCreateMeeting(
    String tenantId, {
    int? participants,
    bool record = false,
    bool recur = false,
  }) async {
    final ent = await getEntitlement(tenantId: tenantId);
    if (participants != null && participants > ent.maxParticipants) return false;
    if (record && !ent.canRecord) return false;
    if (recur && !ent.canRecur) return false;
    return true;
  }

  /// Back-compat shim for the old client-side "record" call. It NO LONGER
  /// inserts anything from client-declared plan/amount — it can only activate a
  /// subscription that is anchored to a confirmed, server-priced payment.
  Future<void> recordSubscription({
    required String planType,
    required double amountZmw,
    String? paymentRef,
    String? tenantId,
  }) async {
    if (paymentRef == null || paymentRef.isEmpty) {
      throw MeetingException('Missing payment reference');
    }
    final ok = await activateSubscription(paymentRef);
    if (!ok) {
      throw MeetingException('Payment not confirmed yet. Please try again shortly.');
    }
  }

  // ── Streams ───────────────────────────────────────────────────────────────
  Stream<BusinessMeeting> streamMeeting(String id) => _client
      .from('business_meetings')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .map((rows) => rows.isEmpty ? null : BusinessMeeting.fromMap(rows.first))
      .where((m) => m != null)
      .cast<BusinessMeeting>();

  Stream<List<MeetingParticipant>> streamParticipants(String meetingId) => _client
      .from('meeting_participants')
      .stream(primaryKey: ['id'])
      .eq('meeting_id', meetingId)
      .asyncMap(_enrichParticipants);

  Stream<List<MeetingAgendaItem>> streamAgenda(String meetingId) => _client
      .from('meeting_agenda_items')
      .stream(primaryKey: ['id'])
      .eq('meeting_id', meetingId)
      .map((rows) {
        final list = rows.map(MeetingAgendaItem.fromMap).toList();
        list.sort((a, b) => a.position.compareTo(b.position));
        return list;
      });

  Stream<List<MeetingRsvp>> streamRsvps(String meetingId) => _client
      .from('meeting_rsvps')
      .stream(primaryKey: ['id'])
      .eq('meeting_id', meetingId)
      .asyncMap(_enrichRsvps);

  Stream<List<MeetingSignal>> streamSignals(String meetingId) => _client
      .from('meeting_signaling')
      .stream(primaryKey: ['id'])
      .eq('meeting_id', meetingId)
      .map((rows) => rows.map(MeetingSignal.fromMap).toList());

  Stream<List<MeetingNote>> streamNotes(String meetingId) => _client
      .from('meeting_notes')
      .stream(primaryKey: ['id'])
      .eq('meeting_id', meetingId)
      .asyncMap((data) async {
        final list = data.map(MeetingNote.fromMap).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  Stream<Map<String, int>> streamVoteResults(String meetingId) => _client
      .from('meeting_votes')
      .stream(primaryKey: ['meeting_id', 'voter_id'])
      .eq('meeting_id', meetingId)
      .map((data) {
        final results = <String, int>{};
        for (final item in data) {
          final opt = (item['option_selected'] ?? '').toString();
          if (opt.isEmpty) continue;
          results[opt] = (results[opt] ?? 0) + 1;
        }
        return results;
      });

  // ── Enrichment helpers ────────────────────────────────────────────────────
  Future<List<MeetingParticipant>> _enrichParticipants(List<Map<String, dynamic>> rows) async {
    final list = rows.map(MeetingParticipant.fromMap).toList();
    await _enrichPeople(list.map((e) => e.userId).toSet(), (id, name, avatar) {
      for (final p in list.where((p) => p.userId == id)) {
        p.fullName = name;
        p.avatarUrl = avatar;
      }
    });
    list.sort((a, b) {
      if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
      return (a.joinedAt ?? DateTime(0)).compareTo(b.joinedAt ?? DateTime(0));
    });
    return list;
  }

  Future<List<MeetingRsvp>> _enrichRsvps(List<Map<String, dynamic>> rows) async {
    final list = rows.map(MeetingRsvp.fromMap).toList();
    await _enrichPeople(list.map((e) => e.userId).toSet(), (id, name, avatar) {
      for (final r in list.where((r) => r.userId == id)) {
        r.fullName = name;
        r.avatarUrl = avatar;
      }
    });
    return list;
  }

  Future<void> _enrichPeople(
    Set<String> ids,
    void Function(String id, String? name, String? avatar) apply,
  ) async {
    if (ids.isEmpty) return;
    try {
      final profiles = await _client
          .from('profiles')
          .select('id, full_name, avatar_url')
          .inFilter('id', ids.toList());
      for (final p in profiles) {
        apply(
          p['id'].toString(),
          p['full_name']?.toString(),
          p['avatar_url']?.toString(),
        );
      }
    } catch (e) {
      debugPrint('profile enrichment failed: $e');
    }
  }
}

class MeetingException implements Exception {
  final String message;
  MeetingException(this.message);
  @override
  String toString() => message;
}

// ============================================================================
// Providers
// ============================================================================

final meetingServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return MeetingService(client);
});

final meetingEntitlementProvider = FutureProvider<MeetingEntitlement>((ref) async {
  return ref.watch(meetingServiceProvider).getEntitlement();
});

final myMeetingsProvider = FutureProvider<List<BusinessMeeting>>((ref) async {
  return ref.watch(meetingServiceProvider).fetchMyMeetings();
});

final meetingByIdProvider =
    FutureProvider.family<BusinessMeeting?, String>((ref, id) async {
  return ref.watch(meetingServiceProvider).fetchMeeting(id);
});

final meetingProvider = StreamProvider.family<BusinessMeeting, String>((
  ref,
  id,
) {
  return ref.watch(meetingServiceProvider).streamMeeting(id);
});

final meetingParticipantsProvider =
    StreamProvider.family<List<MeetingParticipant>, String>((ref, meetingId) {
  return ref.watch(meetingServiceProvider).streamParticipants(meetingId);
});

final meetingAgendaProvider =
    StreamProvider.family<List<MeetingAgendaItem>, String>((ref, meetingId) {
  return ref.watch(meetingServiceProvider).streamAgenda(meetingId);
});

final meetingRsvpsProvider =
    StreamProvider.family<List<MeetingRsvp>, String>((ref, meetingId) {
  return ref.watch(meetingServiceProvider).streamRsvps(meetingId);
});

final meetingNotesProvider =
    StreamProvider.family<List<MeetingNote>, String>((ref, meetingId) {
  return ref.watch(meetingServiceProvider).streamNotes(meetingId);
});

final meetingVotesProvider =
    StreamProvider.family<Map<String, int>, String>((ref, meetingId) {
  return ref.watch(meetingServiceProvider).streamVoteResults(meetingId);
});
