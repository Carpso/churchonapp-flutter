import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Which way a member is moving.
enum TransferDirection {
  outbound('outbound', 'Leaving this church', Icons.logout),
  inbound('inbound', 'Joining this church', Icons.login),
  internal('internal', 'Moving between cells', Icons.swap_horiz);

  const TransferDirection(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;

  static TransferDirection parse(String? v) => TransferDirection.values
      .firstWhere((d) => d.id == v, orElse: () => TransferDirection.outbound);
}

enum TransferStatus {
  requested('requested', 'Awaiting decision'),
  completed('completed', 'Completed'),
  declined('declined', 'Declined'),
  cancelled('cancelled', 'Cancelled');

  const TransferStatus(this.id, this.label);
  final String id;
  final String label;

  static TransferStatus parse(String? v) => TransferStatus.values
      .firstWhere((s) => s.id == v, orElse: () => TransferStatus.requested);
}

@immutable
class MemberTransfer {
  final String id;
  final String memberId;
  final String? memberName;
  final String? memberPhone;
  final int? membershipYears;
  final String? fromChurchName;
  final String? toChurchName;
  final String? letterNo;
  final String? reason;
  final String? notes;
  final TransferDirection direction;
  final TransferStatus status;
  final DateTime requestedAt;
  final DateTime? decidedAt;

  const MemberTransfer({
    required this.id,
    required this.memberId,
    this.memberName,
    this.memberPhone,
    this.membershipYears,
    this.fromChurchName,
    this.toChurchName,
    this.letterNo,
    this.reason,
    this.notes,
    required this.direction,
    required this.status,
    required this.requestedAt,
    this.decidedAt,
  });

  factory MemberTransfer.fromMap(Map<String, dynamic> m) => MemberTransfer(
        id: m['id'].toString(),
        memberId: m['member_id']?.toString() ?? '',
        memberName: m['member_name']?.toString(),
        memberPhone: m['member_phone']?.toString(),
        membershipYears: (m['membership_years'] as num?)?.toInt(),
        fromChurchName: m['from_church_name']?.toString(),
        toChurchName: m['to_church_name']?.toString(),
        letterNo: m['letter_no']?.toString(),
        reason: m['reason']?.toString(),
        notes: m['notes']?.toString(),
        direction: TransferDirection.parse(m['direction']?.toString()),
        status: TransferStatus.parse(m['status']?.toString()),
        requestedAt:
            DateTime.tryParse(m['requested_at']?.toString() ?? '') ??
                DateTime.now(),
        decidedAt: DateTime.tryParse(m['decided_at']?.toString() ?? ''),
      );

  bool get isPending => status == TransferStatus.requested;

  /// The line a pastor actually reads on the letter.
  String get memberLine {
    final name = memberName ?? 'Unnamed member';
    final years = membershipYears;
    if (years == null || years <= 0) return name;
    return '$name  ·  $years ${years == 1 ? 'year' : 'years'} in the church';
  }
}

class TransferException implements Exception {
  final String message;
  const TransferException(this.message);
  @override
  String toString() => message;
}

/// Reads and writes transfers.
///
/// All writes go through server RPCs: `request_member_transfer` and
/// `decide_member_transfer`. The second one is what actually reassigns the
/// member to the new church, so it must never be attempted client-side.
class MemberTransferService {
  final SupabaseClient _client;
  MemberTransferService(this._client);

  /// Transfers involving this church, newest first. RLS limits this to the two
  /// parties.
  Future<List<MemberTransfer>> fetchForChurch(String tenantId) async {
    final rows = await _client
        .from('member_transfers')
        .select(
          'id, member_id, member_name, member_phone, membership_years, '
          'from_tenant_id, from_church_name, to_tenant_id, to_church_name, '
          'letter_no, reason, notes, direction, status, requested_at, decided_at',
        )
        .or('from_tenant_id.eq.$tenantId,to_tenant_id.eq.$tenantId')
        .order('requested_at', ascending: false)
        .limit(200);

    return rows
        .map((r) => MemberTransfer.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Churches eligible as a destination: anything the user is not already in.
  Future<List<Map<String, String>>> destinationChurches(String excludeTenantId) async {
    final rows = await _client
        .from('tenants')
        .select('id, name')
        .neq('id', excludeTenantId)
        .order('name')
        .limit(300);
    return [
      for (final r in rows)
        {
          'id': r['id'].toString(),
          'name': r['name']?.toString() ?? '',
        }
    ];
  }

  /// Churches that can be named as the origin of an inbound transfer
  /// (any church except this one).
  Future<List<Map<String, String>>> originChurches(String excludeTenantId) async {
    return destinationChurches(excludeTenantId);
  }

  Future<MemberTransfer> request({
    required String memberId,
    required TransferDirection direction,
    String? toTenantId,
    String? toChurchName,
    String? reason,
    String? notes,
  }) async {
    try {
      final row = await _client.rpc('request_member_transfer', params: {
        'p_member_id': memberId,
        'p_direction': direction.id,
        'p_to_tenant': toTenantId,
        'p_to_church_name': toChurchName,
        'p_reason': reason,
        'p_notes': notes,
      });
      return MemberTransfer.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw TransferException(_readable(e));
    }
  }

  /// Approve or decline. Approving an outbound transfer moves the member.
  Future<MemberTransfer> decide({
    required String transferId,
    required bool approve,
    String? notes,
  }) async {
    try {
      final row = await _client.rpc('decide_member_transfer', params: {
        'p_transfer_id': transferId,
        'p_approve': approve,
        'p_notes': notes,
      });
      return MemberTransfer.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw TransferException(_readable(e));
    }
  }

  /// Turns a raw Postgres/RPC error into something a pastor can act on.
  String _readable(Object e) {
    final s = e.toString();
    if (s.contains('does not exist')) {
      return 'That church could not be found. Pick another one.';
    }
    if (s.contains('only church leadership')) {
      return 'Only church leadership can do this.';
    }
    if (s.contains('already')) {
      return 'This transfer has already been decided.';
    }
    if (s.contains('not authenticated')) {
      return 'Your session expired. Sign in and try again.';
    }
    return 'Could not complete the transfer. Please try again.';
  }
}