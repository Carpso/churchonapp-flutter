import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/services/tenant_service.dart';

/// The three offices a church appoints locally.
///
/// IMPORTANT: an appointment here is NOT an ordination. A pastor can appoint an
/// elder; only a bishop or conference officer can ordain one. Both registers live
/// side by side in the database precisely so the distinction cannot be lost - see
/// `canIssueOrdinationRole`.
enum OfficerRole {
  elder('elder', 'Elder'),
  deacon('deacon', 'Deacon'),
  deaconess('deaconess', 'Deaconess');

  const OfficerRole(this.id, this.label);

  final String id;
  final String label;

  static OfficerRole parse(String? v) => OfficerRole.values
      .firstWhere((r) => r.id == v, orElse: () => OfficerRole.elder);
}

/// How an appointment ended. `transferred` is deliberately distinct from
/// `inactive`: the person moved to another church (see member transfers), and this
/// church's roll is closed behind them rather than merely paused.
enum OfficerStatus {
  active('active', 'Serving'),
  inactive('inactive', 'Inactive'),
  deceased('deceased', 'Deceased'),
  transferred('transferred', 'Transferred');

  const OfficerStatus(this.id, this.label);

  final String id;
  final String label;

  static OfficerStatus parse(String? v) => OfficerStatus.values
      .firstWhere((s) => s.id == v, orElse: () => OfficerStatus.inactive);
}

/// Ordained = full ordination. Licensed = recognised to preach/teach.
/// Accredited = in training. Separate from the office, because a conference
/// grades the same three titles differently.
enum CredentialType {
  ordained('ordained', 'Ordained'),
  licensed('licensed', 'Licensed'),
  accredited('accredited', 'Accredited (in training)');

  const CredentialType(this.id, this.label);

  final String id;
  final String label;

  static CredentialType parse(String? v) => CredentialType.values
      .firstWhere((t) => t.id == v, orElse: () => CredentialType.ordained);
}

/// The office or function a credential confers.
enum MinistryRole {
  deacon('deacon', 'Deacon'),
  deaconess('deaconess', 'Deaconess'),
  elder('elder', 'Elder'),
  pastor('pastor', 'Pastor'),
  bishop('bishop', 'Bishop'),
  localPreacher('local_preacher', 'Local Preacher'),
  evangelist('evangelist', 'Evangelist'),
  teacher('teacher', 'Teacher');

  const MinistryRole(this.id, this.label);

  final String id;
  final String label;

  /// What a certificate would actually print.
  String get titleLabel => label;

  static MinistryRole parse(String? v) => MinistryRole.values
      .firstWhere((r) => r.id == v, orElse: () => MinistryRole.localPreacher);

  static List<MinistryRole> forType(CredentialType type) => switch (type) {
        CredentialType.ordained => const [
            MinistryRole.deacon,
            MinistryRole.deaconess,
            MinistryRole.elder,
            MinistryRole.pastor,
            MinistryRole.bishop,
          ],
        CredentialType.licensed => const [
            MinistryRole.localPreacher,
            MinistryRole.evangelist,
            MinistryRole.teacher,
          ],
        // Someone in training is accredited at the office they are training for.
        CredentialType.accredited => MinistryRole.values,
      };
}

enum CredentialStatus {
  active('active', 'Valid'),
  suspended('suspended', 'Suspended'),
  revoked('revoked', 'Revoked'),
  expired('expired', 'Expired');

  const CredentialStatus(this.id, this.label);

  final String id;
  final String label;

  static CredentialStatus parse(String? v) => CredentialStatus.values
      .firstWhere((s) => s.id == v, orElse: () => CredentialStatus.active);
}

/// One line of the append-only credential trail.
enum CredentialEventType {
  granted('granted', 'Granted'),
  renewed('renewed', 'Renewed'),
  revoked('revoked', 'Revoked'),
  suspended('suspended', 'Suspended'),
  expired('expired', 'Expired'),
  reinstated('reinstated', 'Reinstated');

  const CredentialEventType(this.id, this.label);

  final String id;
  final String label;

  static CredentialEventType parse(String? v) => CredentialEventType.values
      .firstWhere((e) => e.id == v, orElse: () => CredentialEventType.granted);
}

enum BranchLicenseStatus {
  unlicensed('unlicensed', 'Not licensed'),
  applicationSubmitted('application_submitted', 'Application submitted'),
  underReview('under_review', 'Under review'),
  licensed('licensed', 'Licensed'),
  suspended('suspended', 'Suspended'),
  revoked('revoked', 'Revoked');

  const BranchLicenseStatus(this.id, this.label);

  final String id;
  final String label;

  bool get isOpen => this == applicationSubmitted || this == underReview;

  static BranchLicenseStatus parse(String? v) => BranchLicenseStatus.values
      .firstWhere((s) => s.id == v, orElse: () => BranchLicenseStatus.unlicensed);
}

// ===========================================================================
// Models
// ===========================================================================

/// One row of `church_officers` — a signed appointment on the elders / deacons /
/// deaconesses page of the church register book.
@immutable
class ChurchOfficer {
  final String id;
  final String churchId;
  final String memberId;
  final String? memberName;
  final String? memberPhone;
  final OfficerRole role;
  final OfficerStatus status;
  final String? appointedBy;
  final DateTime? appointedAt;
  final DateTime? termStart;
  final DateTime? termEnd;
  final bool isExcoMember;
  final String? notes;

  const ChurchOfficer({
    required this.id,
    required this.churchId,
    required this.memberId,
    this.memberName,
    this.memberPhone,
    required this.role,
    required this.status,
    this.appointedBy,
    this.appointedAt,
    this.termStart,
    this.termEnd,
    this.isExcoMember = false,
    this.notes,
  });

  factory ChurchOfficer.fromMap(Map<String, dynamic> m) => ChurchOfficer(
        id: m['id'].toString(),
        churchId: m['church_id']?.toString() ?? '',
        memberId: m['member_id']?.toString() ?? '',
        memberName: m['member_name']?.toString(),
        memberPhone: m['member_phone']?.toString(),
        role: OfficerRole.parse(m['role']?.toString()),
        status: OfficerStatus.parse(m['status']?.toString()),
        appointedBy: m['appointed_by']?.toString(),
        appointedAt: _dateTime(m['appointed_at']),
        termStart: _dateTime(m['term_start']),
        termEnd: _dateTime(m['term_end']),
        isExcoMember: m['is_exco_member'] == true,
        notes: m['notes']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'church_id': churchId,
        'member_id': memberId,
        'role': role.id,
        'status': status.id,
        'appointed_by': appointedBy,
        'appointed_at': appointedAt?.toIso8601String(),
        'term_start': termStart?.toIso8601String(),
        'term_end': termEnd?.toIso8601String(),
        'is_exco_member': isExcoMember,
        'notes': notes,
      };

  bool get isActive => status == OfficerStatus.active;

  /// Terms lapse quietly on a Zambian church's officers board. Anything expiring
  /// within 90 days is worth raising at the next officers' meeting.
  bool get termEndingSoon {
    final end = termEnd;
    if (!isActive || end == null) return false;
    return end.isBefore(DateTime.now().add(const Duration(days: 90)));
  }

  bool get termLapsed {
    final end = termEnd;
    return isActive && end != null && end.isBefore(DateTime.now());
  }

  String get displayName => memberName ?? 'Unnamed';
}

/// One row of `ministerial_credentials`.
///
/// A credential can be revoked AFTER the person has served for years, so this row
/// is never deleted and its number is never reused. Revocation is a state, with the
/// reason attached — see [CredentialEvent].
@immutable
class MinisterialCredential {
  final String id;
  final String holderUserId;
  final String? holderName;
  final String? holderPhone;
  final CredentialType credentialType;
  final MinistryRole ministryRole;
  final String? credentialNumber;
  final CredentialStatus status;
  final String issuingAuthority;
  final String? churchId;
  final String? churchName;
  final DateTime? issuedOn;
  final DateTime? expiresOn;
  final DateTime? revokedAt;
  final String? revokedBy;
  final String? revocationReason;
  final String? notes;

  const MinisterialCredential({
    required this.id,
    required this.holderUserId,
    this.holderName,
    this.holderPhone,
    required this.credentialType,
    required this.ministryRole,
    this.credentialNumber,
    required this.status,
    required this.issuingAuthority,
    this.churchId,
    this.churchName,
    this.issuedOn,
    this.expiresOn,
    this.revokedAt,
    this.revokedBy,
    this.revocationReason,
    this.notes,
  });

  factory MinisterialCredential.fromMap(Map<String, dynamic> m) =>
      MinisterialCredential(
        id: m['id'].toString(),
        holderUserId: m['holder_user_id']?.toString() ?? '',
        holderName: m['holder_name']?.toString(),
        holderPhone: m['holder_phone']?.toString(),
        credentialType: CredentialType.parse(m['credential_type']?.toString()),
        ministryRole: MinistryRole.parse(m['ministry_role']?.toString()),
        credentialNumber: m['credential_number']?.toString(),
        status: CredentialStatus.parse(m['status']?.toString()),
        issuingAuthority: m['issuing_authority']?.toString() ?? '',
        churchId: m['church_id']?.toString(),
        churchName: m['church_name']?.toString(),
        issuedOn: _dateOnly(m['issued_on']),
        expiresOn: _dateOnly(m['expires_on']),
        revokedAt: _dateTime(m['revoked_at']),
        revokedBy: m['revoked_by']?.toString(),
        revocationReason: m['revocation_reason']?.toString(),
        notes: m['notes']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'holder_user_id': holderUserId,
        'credential_type': credentialType.id,
        'ministry_role': ministryRole.id,
        'credential_number': credentialNumber,
        'status': status.id,
        'issuing_authority': issuingAuthority,
        'church_id': churchId,
        'issued_on': issuedOn?.toIso8601String(),
        'expires_on': expiresOn?.toIso8601String(),
        'revoked_at': revokedAt?.toIso8601String(),
        'revoked_by': revokedBy,
        'revocation_reason': revocationReason,
        'notes': notes,
      };

  bool get isActive => status == CredentialStatus.active;

  /// NULL church_id = conference-wide: ordained to the denomination, not to one
  /// local church. That is the normal case for a bishop ordaining a pastor.
  bool get isConferenceWide => (churchId ?? '').isEmpty;

  /// The expiry is DERIVED, never written by a trigger (see the migration header),
  /// so a credential whose date has simply passed reads as expired here.
  bool get hasLapsed {
    final end = expiresOn;
    return end != null && end.isBefore(DateTime.now());
  }

  bool get expiringSoon {
    final end = expiresOn;
    return isActive &&
        end != null &&
        end.isBefore(DateTime.now().add(const Duration(days: 90)));
  }

  String get displayName => holderName ?? 'Unnamed';

  /// What a certificate reads at the top.
  String get certificateTitle =>
      '${credentialType.label} ${ministryRole.titleLabel}';
}

/// One immutable line of `ministerial_credential_events`.
@immutable
class CredentialEvent {
  final String id;
  final String credentialId;
  final CredentialEventType eventType;
  final CredentialStatus? fromStatus;
  final CredentialStatus? toStatus;
  final String? actorName;
  final String? reason;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const CredentialEvent({
    required this.id,
    required this.credentialId,
    required this.eventType,
    this.fromStatus,
    this.toStatus,
    this.actorName,
    this.reason,
    this.metadata = const {},
    required this.createdAt,
  });

  factory CredentialEvent.fromMap(Map<String, dynamic> m) => CredentialEvent(
        id: m['id'].toString(),
        credentialId: m['credential_id']?.toString() ?? '',
        eventType: CredentialEventType.parse(m['event_type']?.toString()),
        fromStatus: m['from_status'] == null
            ? null
            : CredentialStatus.parse(m['from_status'].toString()),
        toStatus: m['to_status'] == null
            ? null
            : CredentialStatus.parse(m['to_status'].toString()),
        actorName: m['actor_name']?.toString(),
        reason: m['reason']?.toString(),
        metadata: Map<String, dynamic>.from(
          (m['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        createdAt: _dateTime(m['created_at']) ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'credential_id': credentialId,
        'event_type': eventType.id,
        'from_status': fromStatus?.id,
        'to_status': toStatus?.id,
        'reason': reason,
        'metadata': metadata,
        'created_at': createdAt.toIso8601String(),
      };
}

/// One row of `branch_licenses` — the certificate a parent organisation issues to
/// a branch it supervises.
@immutable
class BranchLicense {
  final String id;
  final String churchId;
  final String? churchName;
  final String? organizationId;
  final String? organizationName;
  final BranchLicenseStatus status;
  final String? applicationReference;
  final Map<String, bool> requirements;
  final String? licenseNumber;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final DateTime? issuedAt;
  final DateTime? expiresAt;
  final DateTime? renewalDueAt;
  final String? suspendedReason;
  final String? revocationReason;
  final String? decisionNotes;

  const BranchLicense({
    required this.id,
    required this.churchId,
    this.churchName,
    this.organizationId,
    this.organizationName,
    required this.status,
    this.applicationReference,
    this.requirements = const {},
    this.licenseNumber,
    this.submittedAt,
    this.reviewedAt,
    this.issuedAt,
    this.expiresAt,
    this.renewalDueAt,
    this.suspendedReason,
    this.revocationReason,
    this.decisionNotes,
  });

  factory BranchLicense.fromMap(Map<String, dynamic> m) => BranchLicense(
        id: m['id'].toString(),
        churchId: m['church_id']?.toString() ?? '',
        churchName: m['church_name']?.toString(),
        organizationId: m['organization_id']?.toString(),
        organizationName: m['organization_name']?.toString(),
        status: BranchLicenseStatus.parse(m['status']?.toString()),
        applicationReference: m['application_reference']?.toString(),
        requirements: _requirementMap(m['requirements']),
        licenseNumber: m['license_number']?.toString(),
        submittedAt: _dateTime(m['submitted_at']),
        reviewedAt: _dateTime(m['reviewed_at']),
        issuedAt: _dateTime(m['issued_at']),
        expiresAt: _dateOnly(m['expires_at']),
        renewalDueAt: _dateOnly(m['renewal_due_at']),
        suspendedReason: m['suspension_reason']?.toString(),
        revocationReason: m['revocation_reason']?.toString(),
        decisionNotes: m['decision_notes']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'church_id': churchId,
        'organization_id': organizationId,
        'status': status.id,
        'application_reference': applicationReference,
        'requirements': requirements,
        'license_number': licenseNumber,
        'submitted_at': submittedAt?.toIso8601String(),
        'reviewed_at': reviewedAt?.toIso8601String(),
        'issued_at': issuedAt?.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'renewal_due_at': renewalDueAt?.toIso8601String(),
        'suspension_reason': suspendedReason,
        'revocation_reason': revocationReason,
        'decision_notes': decisionNotes,
      };

  bool get isLicensed => status == BranchLicenseStatus.licensed;

  /// Nothing is written by a trigger: a licence whose date has passed still reads as
  /// licensed, and the reader treats it as lapsed until somebody renews it.
  bool get hasLapsed {
    final end = expiresAt;
    return isLicensed && end != null && end.isBefore(DateTime.now());
  }

  bool get renewalDue {
    final due = renewalDueAt;
    return isLicensed && due != null && due.isBefore(DateTime.now());
  }

  /// The server BLOCKS a licence while any checklist item is false — this is what
  /// makes the checklist a control rather than decoration.
  List<String> get unmetRequirements => requirements.entries
      .where((e) => !e.value)
      .map((e) => e.key)
      .toList(growable: false);
}

// ===========================================================================
// Service
// ===========================================================================

class GovernanceException implements Exception {
  final String message;
  const GovernanceException(this.message);
  @override
  String toString() => message;
}

/// Reads and writes the three governance registers.
///
/// Every state transition goes through a server RPC. That is not ceremony: the
/// server is where the ordination authority is enforced (a pastor CANNOT ordain),
/// where the branch-licence gate is narrowed to the parent organisation (a branch
/// pastor CANNOT licence their own branch), and where the audit row is written. A
/// client that tried to UPDATE these rows directly would be refused by Postgres —
/// `authenticated` holds no INSERT/UPDATE/DELETE privilege on any of them.
class ChurchGovernanceService {
  final SupabaseClient _client;
  ChurchGovernanceService(this._client);

  // ------------------------------------------------------------------ officers

  /// Resolves either kind of id to `churches.id`.
  ///
  /// `currentTenantProvider.id` is a TENANCY id, while all three registers store
  /// `churches.id`. Seeded data shares ONE uuid between the two, but a church
  /// registered after the tenancy/church split does not — so a read filtered on the
  /// tenancy id would silently return nothing. The server resolves it too
  /// (`resolve_church_id`); doing it here keeps the READS honest as well.
  ///
  /// Best effort: if `churches` cannot be read (RLS, or a member who may only see
  /// their own row) we fall back to the id we were given, which is correct for the
  /// shared-uuid shape that covers the seeded network.
  Future<String> resolveChurchId(String id) async {
    if (id.isEmpty) return id;
    try {
      final rows = await _client
          .from('churches')
          .select('id')
          .or('id.eq.$id,tenant_id.eq.$id')
          .limit(1);
      for (final r in rows) {
        final resolved = r['id']?.toString();
        if (resolved != null && resolved.isNotEmpty) return resolved;
      }
    } catch (e) {
      debugPrint('[governance] church id resolution fell back to $id: $e');
    }
    return id;
  }

  /// Officers of one church. RLS limits this to that church's members and to
  /// platform staff.
  Future<List<ChurchOfficer>> fetchOfficers(String churchId) async {
    final church = await resolveChurchId(churchId);
    final rows = await _client
        .from('church_officers')
        .select(
          'id, church_id, member_id, role, status, appointed_by, appointed_at, '
          'term_start, term_end, is_exco_member, notes',
        )
        .eq('church_id', church)
        .order('role', ascending: true)
        .order('term_end', ascending: true)
        .limit(400);

    return _withPeople(
      rows,
      (m) => ChurchOfficer.fromMap(m),
      (m) => m['member_id']?.toString() ?? '',
    );
  }

  /// Headcount per office — the number a Zambian church is actually asked for
  /// ("how many elders does this church have?").
  Future<Map<OfficerRole, int>> officerCounts(String churchId) async {
    final church = await resolveChurchId(churchId);
    final rows = await _client
        .from('church_officers')
        .select('role, status')
        .eq('church_id', church)
        .limit(2000);

    final out = <OfficerRole, int>{};
    for (final r in rows) {
      if (OfficerStatus.parse(r['status']?.toString()) != OfficerStatus.active) {
        continue;
      }
      final role = OfficerRole.parse(r['role']?.toString());
      out[role] = (out[role] ?? 0) + 1;
    }
    return out;
  }

  /// Appoints an elder / deacon / deaconess. Requires church leadership, and the
  /// person must already be a member of that church.
  Future<ChurchOfficer> appoint({
    required String churchId,
    required String memberId,
    required OfficerRole role,
    DateTime? termStart,
    DateTime? termEnd,
    bool isExcoMember = false,
    String? notes,
  }) async {
    try {
      final row = await _client.rpc('appoint_officer', params: {
        'p_church_id': churchId,
        'p_member_id': memberId,
        'p_role': role.id,
        'p_term_start': _dateParam(termStart),
        'p_term_end': _dateParam(termEnd),
        'p_is_exco_member': isExcoMember,
        'p_notes': notes,
      });
      return ChurchOfficer.fromMap(_asMap(row));
    } catch (e) {
      throw GovernanceException(_readable(e, 'appointment'));
    }
  }

  /// Ends an appointment. The row is kept — a roll that silently loses a deceased
  /// elder cannot answer "who served here and when".
  Future<ChurchOfficer> endAppointment({
    required String officerId,
    OfficerStatus status = OfficerStatus.inactive,
    String? notes,
  }) async {
    try {
      final row = await _client.rpc('end_officer_appointment', params: {
        'p_officer_id': officerId,
        'p_status': status.id,
        'p_notes': notes,
      });
      return ChurchOfficer.fromMap(_asMap(row));
    } catch (e) {
      throw GovernanceException(_readable(e, 'appointment'));
    }
  }

  // -------------------------------------------------------------- credentials

  /// Credentials attached to this church. RLS also surfaces the holder's own
  /// conference-wide credentials, so a member can see their own certificate.
  Future<List<MinisterialCredential>> fetchCredentials(String churchId) async {
    final church = await resolveChurchId(churchId);
    final rows = await _client
        .from('ministerial_credentials')
        .select(
          'id, holder_user_id, credential_type, ministry_role, credential_number, '
          'status, issuing_authority, church_id, issued_on, expires_on, '
          'revoked_at, revoked_by, revocation_reason, notes',
        )
        .eq('church_id', church)
        .order('issued_on', ascending: false)
        .limit(400);

    final list = rows.map((r) => _asMap(r)).toList();
    final enriched = await _attachPeople(
      list,
      peopleKey: 'holder_user_id',
      nameKey: 'holder_name',
      phoneKey: 'holder_phone',
    );
    return enriched.map(MinisterialCredential.fromMap).toList();
  }

  /// The append-only trail for this church's credentials, newest first so it reads
  /// like a chronology. Actor names are joined in: WHO made the change is the whole
  /// point of an audit trail, so an unattributed line is not much use.
  Future<List<CredentialEvent>> fetchCredentialEvents(
      String churchId) async {
    final credentials = await fetchCredentials(churchId);
    if (credentials.isEmpty) return const [];

    final rows = await _client
        .from('ministerial_credential_events')
        .select(
          'id, credential_id, event_type, from_status, to_status, actor_id, '
          'reason, metadata, created_at',
        )
        .inFilter('credential_id', credentials.map((c) => c.id).toList())
        .order('created_at', ascending: false)
        .limit(300);

    final maps = rows.map((r) => _asMap(r)).toList();
    final actorIds = {for (final m in maps) m['actor_id']?.toString() ?? ''}
        .where((id) => id.isNotEmpty)
        .toList();

    final actors = <String, String?>{};
    if (actorIds.isNotEmpty) {
      try {
        final people = await _client
            .from('profiles')
            .select('id, full_name')
            .inFilter('id', actorIds);
        for (final p in people) {
          actors[p['id'].toString()] = p['full_name']?.toString();
        }
      } catch (e) {
        // The trail must render even if the names cannot be resolved.
        debugPrint('[governance] credential actor names unavailable: $e');
      }
    }

    return [
      for (final m in maps)
        CredentialEvent.fromMap({
          ...m,
          'actor_name': actors[m['actor_id']?.toString()],
        }),
    ];
  }

  /// Grants a credential. ONLY a bishop, apostle, prophet, conference secretary or
  /// treasurer (or COA staff) can do this — the server refuses everyone else,
  /// including the local pastor.
  Future<MinisterialCredential> grantCredential({
    required String holderUserId,
    required CredentialType credentialType,
    required MinistryRole ministryRole,
    String? churchId,
    String? credentialNumber,
    DateTime? issuedOn,
    DateTime? expiresOn,
    String? issuingAuthority,
    String? notes,
  }) async {
    try {
      final row = await _client.rpc('grant_ministerial_credential', params: {
        'p_holder_user_id': holderUserId,
        'p_credential_type': credentialType.id,
        'p_ministry_role': ministryRole.id,
        'p_church_id': churchId,
        'p_credential_number': credentialNumber,
        'p_issued_on': _dateParam(issuedOn),
        'p_expires_on': _dateParam(expiresOn),
        'p_issuing_authority': issuingAuthority,
        'p_notes': notes,
      });
      return MinisterialCredential.fromMap(_asMap(row));
    } catch (e) {
      throw GovernanceException(_readable(e, 'credential'));
    }
  }

  Future<MinisterialCredential> renewCredential({
    required String credentialId,
    required DateTime expiresOn,
    String? notes,
  }) async {
    try {
      final row = await _client.rpc('renew_ministerial_credential', params: {
        'p_credential_id': credentialId,
        'p_expires_on': _dateParam(expiresOn),
        'p_notes': notes,
      });
      return MinisterialCredential.fromMap(_asMap(row));
    } catch (e) {
      throw GovernanceException(_readable(e, 'credential'));
    }
  }

  /// Revokes, suspends, or records an expiry. A reason is REQUIRED by the server:
  /// a withdrawal with no stated cause is not a record.
  ///
  /// This is safe to do years after the person served — the row survives with its
  /// number and its full event trail, and the holder stays on the church's officers
  /// roll until the church ends that appointment itself.
  Future<MinisterialCredential> revokeCredential({
    required String credentialId,
    CredentialStatus status = CredentialStatus.revoked,
    required String reason,
  }) async {
    try {
      final row = await _client.rpc('revoke_ministerial_credential', params: {
        'p_credential_id': credentialId,
        'p_status': status.id,
        'p_reason': reason,
      });
      return MinisterialCredential.fromMap(_asMap(row));
    } catch (e) {
      throw GovernanceException(_readable(e, 'credential'));
    }
  }

  /// Lifts a suspension. A revocation is final — restoring one means granting a NEW
  /// credential, which keeps both rows.
  Future<MinisterialCredential> reinstateCredential({
    required String credentialId,
    required String reason,
  }) async {
    try {
      final row = await _client.rpc('reinstate_ministerial_credential', params: {
        'p_credential_id': credentialId,
        'p_reason': reason,
      });
      return MinisterialCredential.fromMap(_asMap(row));
    } catch (e) {
      throw GovernanceException(_readable(e, 'credential'));
    }
  }

  // ---------------------------------------------------------- branch licensing

  /// This church's licence record — the most recent application, or the live
  /// licence if there is one. Returns null when the church has never applied.
  Future<BranchLicense?> fetchBranchLicense(String churchId) async {
    final church = await resolveChurchId(churchId);
    final rows = await _client
        .from('branch_licenses')
        .select(
          'id, church_id, organization_id, status, application_reference, '
          'requirements, license_number, submitted_at, reviewed_at, issued_at, '
          'expires_at, renewal_due_at, suspension_reason, revocation_reason, '
          'decision_notes',
        )
        .eq('church_id', church)
        .order('submitted_at', ascending: false)
        .limit(20);

    if (rows.isEmpty) return null;

    final maps = rows.map((r) => _asMap(r)).toList();
    // Prefer a live licence over an older application so the screen opens on the
    // thing that actually matters, then fall back to the newest application.
    final live = maps.where((m) =>
            m['status'] == BranchLicenseStatus.licensed.id ||
            m['status'] == BranchLicenseStatus.suspended.id ||
            m['status'] == BranchLicenseStatus.revoked.id)
        .toList();
    final chosen = live.isNotEmpty ? live.first : maps.first;

    final orgs = await _fetchOrganizationNames(
      [for (final m in maps) m['organization_id']?.toString()]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet(),
    );
    final churchName = await _fetchChurchNames({church});

    return BranchLicense.fromMap({
      ...chosen,
      'organization_name': orgs[chosen['organization_id']?.toString()],
      'church_name': churchName[church],
    });
  }

  /// A church ASKS its parent organisation for a licence. Requires leadership of
  /// this church, and the church must be linked to an organisation.
  Future<BranchLicense> applyForLicense({
    required String churchId,
    String? applicationReference,
    Map<String, bool>? requirements,
  }) async {
    try {
      final row = await _client.rpc('apply_for_branch_license', params: {
        'p_church_id': churchId,
        'p_application_reference': applicationReference,
        'p_requirements': requirements ?? const <String, bool>{},
      });
      return BranchLicense.fromMap(_asMap(row));
    } catch (e) {
      throw GovernanceException(_readable(e, 'licence'));
    }
  }

  /// Marks an application as received. Parent-organisation officers only.
  Future<BranchLicense> reviewLicense(String licenseId) async {
    try {
      final row = await _client.rpc('review_branch_license', params: {
        'p_license_id': licenseId,
      });
      return BranchLicense.fromMap(_asMap(row));
    } catch (e) {
      throw GovernanceException(_readable(e, 'licence'));
    }
  }

  /// Grants or refuses. The server refuses a grant while any checklist item is
  /// false, and names the outstanding ones. Omit [expiresOn] to use the conference's
  /// configured validity window.
  Future<BranchLicense> decideLicense({
    required String licenseId,
    required bool grant,
    String? notes,
    DateTime? expiresOn,
  }) async {
    try {
      final row = await _client.rpc('decide_branch_license', params: {
        'p_license_id': licenseId,
        'p_decision': grant ? 'licensed' : 'rejected',
        'p_notes': notes,
        'p_expires_on': _dateParam(expiresOn),
      });
      return BranchLicense.fromMap(_asMap(row));
    } catch (e) {
      throw GovernanceException(_readable(e, 'licence'));
    }
  }

  /// Renews an existing licence, keeping the SAME licence number — real licences
  /// renew, they do not mint a new identity every year.
  Future<BranchLicense> renewLicense({
    required String licenseId,
    String? notes,
  }) async {
    try {
      final row = await _client.rpc('renew_branch_license', params: {
        'p_license_id': licenseId,
        'p_notes': notes,
      });
      return BranchLicense.fromMap(_asMap(row));
    } catch (e) {
      throw GovernanceException(_readable(e, 'licence'));
    }
  }

  /// Suspends, revokes, or lifts a suspension of a live licence.
  Future<BranchLicense> setLicenseStatus({
    required String licenseId,
    required BranchLicenseStatus status,
    required String reason,
  }) async {
    try {
      final row = await _client.rpc('set_branch_license_status', params: {
        'p_license_id': licenseId,
        'p_status': status.id,
        'p_reason': reason,
      });
      return BranchLicense.fromMap(_asMap(row));
    } catch (e) {
      throw GovernanceException(_readable(e, 'licence'));
    }
  }

  // ------------------------------------------------------------------ pickers

  /// Members of this church, for the officer and credential pickers. An officer is a
  /// member of the church that appoints them, so the server refuses anybody else.
  Future<List<Map<String, dynamic>>> fetchMembers(String churchId) async {
    // Deliberately NOT resolved to `churches.id`: `profiles.tenant_id` is the
    // TENANCY id, so this filter has to use the id we were given.
    final rows = await _client
        .from('profiles')
        .select('id, full_name, phone_number, role')
        .eq('tenant_id', churchId)
        .order('full_name')
        .limit(400);
    return rows.map((r) => _asMap(r)).toList();
  }

  // ------------------------------------------------------------------ helpers

  Map<String, dynamic> _asMap(dynamic row) =>
      row is Map ? Map<String, dynamic>.from(row) : <String, dynamic>{};

  /// The registers carry only ids; names are joined in afterwards so a person who
  /// was never a member still renders as "Unnamed" rather than blowing up.
  Future<List<T>> _withPeople<T>(
    List<dynamic> rows,
    T Function(Map<String, dynamic>) build,
    String Function(Map<String, dynamic>) personIdOf,
  ) async {
    if (rows.isEmpty) return [];
    final maps = rows.map(_asMap).toList();
    final ids = {for (final m in maps) personIdOf(m)}
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return [for (final m in maps) build(m)];

    final people = await _client
        .from('profiles')
        .select('id, full_name, phone_number')
        .inFilter('id', ids);
    final names = <String, String?>{
      for (final p in people) p['id'].toString(): p['full_name']?.toString(),
    };
    final phones = <String, String?>{
      for (final p in people) p['id'].toString(): p['phone_number']?.toString(),
    };

    return [
      for (final m in maps)
        () {
          final id = personIdOf(m);
          return build({
            ...m,
            'member_name': names[id],
            'member_phone': phones[id],
          });
        }(),
    ];
  }

  Future<List<Map<String, dynamic>>> _attachPeople(
    List<Map<String, dynamic>> rows, {
    required String peopleKey,
    required String nameKey,
    required String phoneKey,
  }) async {
    final ids = {for (final r in rows) r[peopleKey]?.toString() ?? ''}
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return rows;

    final people = await _client
        .from('profiles')
        .select('id, full_name, phone_number')
        .inFilter('id', ids);
    final names = <String, String?>{
      for (final p in people) p['id'].toString(): p['full_name']?.toString(),
    };
    final phones = <String, String?>{
      for (final p in people) p['id'].toString(): p['phone_number']?.toString(),
    };

    return [
      for (final r in rows)
        {
          ...r,
          nameKey: names[r[peopleKey]?.toString()],
          phoneKey: phones[r[peopleKey]?.toString()],
        },
    ];
  }

  /// Branch / parent names. Guarded: a church without an organisation still has to
  /// render, so a missing `organizations` table or a blocked read must not take the
  /// whole screen down.
  Future<Map<String, String?>> _fetchOrganizationNames(Set<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      final rows = await _client
          .from('organizations')
          .select('id, name')
          .inFilter('id', ids.toList())
          .limit(20);
      return {
        for (final r in rows) r['id'].toString(): r['name']?.toString(),
      };
    } catch (e) {
      debugPrint('[governance] organisation names unavailable: $e');
      return {};
    }
  }

  Future<Map<String, String?>> _fetchChurchNames(Set<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      final rows = await _client
          .from('churches')
          .select('id, name')
          .inFilter('id', ids.toList())
          .limit(20);
      return {
        for (final r in rows) r['id'].toString(): r['name']?.toString(),
      };
    } catch (e) {
      debugPrint('[governance] church names unavailable: $e');
      return {};
    }
  }

  /// Turns a raw Postgres/RPC error into something a pastor or a bishop can act on.
  String _readable(Object e, String what) {
    final s = e.toString();
    debugPrint('[governance] $what failed: $s');

    if (s.contains('not authenticated')) {
      return 'Your session expired. Sign in and try again.';
    }
    if (s.contains('only a bishop or conference officer')) {
      return 'Only a bishop or conference officer can issue, renew or revoke a '
          'credential. Ordination is conferred by the conference, not by a local '
          'pastor.';
    }
    if (s.contains('only an officer of the parent organisation')) {
      return 'Only the bishop, secretary or treasurer of the parent organisation '
          'can do this. A branch cannot licence itself.';
    }
    if (s.contains('only church leadership')) {
      return 'Only church leadership can do this.';
    }
    if (s.contains('not met these requirements')) {
      return s
          .split('the branch has not met these requirements:')
          .last
          .trim()
          .replaceAll('"', '');
    }
    if (s.contains('link this church to its organisation')) {
      return 'This church is not linked to an organisation yet, so there is nobody '
          'who could licence it.';
    }
    if (s.contains('already holds an active')) {
      return 'This person already holds that credential. Revoke the old one first '
          'if it has changed.';
    }
    if (s.contains('already holds an active appointment')) {
      return 'This person already holds that office. End the current appointment '
          'before appointing them again.';
    }
    if (s.contains('not a member of this church')) {
      return 'This person is not a member of your church.';
    }
    if (s.contains('a reason is required')) {
      return 'Write the reason first — a record without a reason explains nothing '
          'later.';
    }
    if (s.contains('a revoked credential cannot be renewed')) {
      return 'A revoked credential cannot be renewed. Grant a new one instead.';
    }
    if (s.contains('is already open for this branch')) {
      return 'An application is already open for this branch.';
    }
    if (s.contains('the term cannot end before it starts')) {
      return 'The end date must be after the start date.';
    }
    if (s.contains('does not exist') || s.contains('violates foreign key')) {
      return 'That record could not be found. Pull to refresh and try again.';
    }
    return 'Could not save. Please try again.';
  }
}

Map<String, bool> _requirementMap(dynamic raw) {
  if (raw is! Map) return const {};
  final out = <String, bool>{};
  for (final e in raw.entries) {
    final v = e.value;
    if (v is bool) {
      out[e.key.toString()] = v;
    } else {
      final s = v?.toString().toLowerCase().trim();
      out[e.key.toString()] = s == 'true' || s == '1' || s == 'yes';
    }
  }
  return out;
}

DateTime? _dateTime(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString());

DateTime? _dateOnly(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}

/// Postgres `date` comes back as `2026-01-31` — send it back in the same shape or
/// the parameter will not cast.
String? _dateParam(DateTime? d) {
  if (d == null) return null;
  final normalised = _dateOnly(d);
  return normalised?.toIso8601String().substring(0, 10);
}

// ===========================================================================
// Role gates (mirror the SQL; the server is the authority)
// ===========================================================================

/// The role sets used to decide which controls a screen shows. These mirror the
/// migration exactly — they only decide what is VISIBLE, never what is ALLOWED.
class GovernanceRoles {
  const GovernanceRoles._();

  static const Set<String> staff = {
    'superadmin',
    'super_admin',
    'coa_employee',
    'employee',
  };

  /// Leadership of a church, matching `is_tenant_leadership`.
  static const Set<String> churchLeadership = {
    'pastor',
    'bishop',
    'apostle',
    'prophet',
    'admin',
    'leader',
    'department_leader',
    'general_secretary',
    'general_treasurer',
    'treasurer',
  };

  /// Denominational authority, matching `can_issue_ordination`. A pastor is NOT in
  /// this set, on purpose: a local pastor appoints deacons, they do not ordain them.
  static const Set<String> ordinationAuthority = {
    'bishop',
    'apostle',
    'prophet',
    'general_secretary',
    'general_treasurer',
  };

  /// Officers of an organisation who can license a branch, matching
  /// `is_branch_license_authority`. The church link is checked separately, because
  /// any branch pastor of the same organisation would otherwise pass.
  static const Set<String> organisationOfficers = {
    'bishop',
    'general_secretary',
    'general_treasurer',
    'treasurer',
  };

  static bool canAppointOfficers(String role) =>
      staff.contains(role) || churchLeadership.contains(role);

  static bool canIssueCredentials(String role) =>
      staff.contains(role) || ordinationAuthority.contains(role);

  /// [hasOrganization] means the caller's church is linked to a parent, so an
  /// organisation officer of that parent can act on it.
  static bool canLicenseBranches(String role, {required bool hasOrganization}) =>
      staff.contains(role) ||
      (hasOrganization && organisationOfficers.contains(role));

  static bool canApplyForLicense(String role) =>
      staff.contains(role) || churchLeadership.contains(role);
}

// ===========================================================================
// Providers
// ===========================================================================

final churchGovernanceServiceProvider = Provider<ChurchGovernanceService>(
  (ref) => ChurchGovernanceService(Supabase.instance.client),
);

/// Officers of an explicit church, keyed by a plain `String` church/tenant id — a
/// value-equal key. A Map/List key has no value equality and would refetch on every
/// rebuild (see the RIVERPOD FAMILY KEYS rule in AGENTS.md).
final churchOfficersProvider =
    FutureProvider.family<List<ChurchOfficer>, String>((ref, churchId) {
  if (churchId.isEmpty) return const [];
  return ref.watch(churchGovernanceServiceProvider).fetchOfficers(churchId);
});

/// Officers of the church the user is currently signed in to.
final currentChurchOfficersProvider = FutureProvider<List<ChurchOfficer>>((ref) {
  final tenantId = ref.watch(currentTenantProvider)?.id ?? '';
  return ref.watch(churchOfficersProvider(tenantId).future);
});

/// Active headcount per office for an explicit church. Plain `String` key for the
/// same reason as `churchOfficersProvider`.
final officerCountsProvider =
    FutureProvider.family<Map<OfficerRole, int>, String>((ref, churchId) {
  if (churchId.isEmpty) return const {};
  return ref.watch(churchGovernanceServiceProvider).officerCounts(churchId);
});

/// The same headcount for the church the user is currently signed in to.
final currentOfficerCountsProvider = FutureProvider<Map<OfficerRole, int>>((ref) {
  final tenantId = ref.watch(currentTenantProvider)?.id ?? '';
  return ref.watch(officerCountsProvider(tenantId).future);
});

/// Credentials for an explicit church. Plain `String` key for the same reason as
/// `churchOfficersProvider`.
final churchCredentialsProvider =
    FutureProvider.family<List<MinisterialCredential>, String>((ref, churchId) {
  if (churchId.isEmpty) return const [];
  return ref.watch(churchGovernanceServiceProvider).fetchCredentials(churchId);
});

/// The credential register of the church the user is currently signed in to.
final currentChurchCredentialsProvider =
    FutureProvider<List<MinisterialCredential>>((ref) {
  final tenantId = ref.watch(currentTenantProvider)?.id ?? '';
  return ref.watch(churchCredentialsProvider(tenantId).future);
});

/// The append-only credential trail for an explicit church.
final churchCredentialEventsProvider =
    FutureProvider.family<List<CredentialEvent>, String>((ref, churchId) {
  if (churchId.isEmpty) return const [];
  return ref
      .watch(churchGovernanceServiceProvider)
      .fetchCredentialEvents(churchId);
});

/// The credential trail of the church the user is currently signed in to.
final currentCredentialEventsProvider = FutureProvider<List<CredentialEvent>>((ref) {
  final tenantId = ref.watch(currentTenantProvider)?.id ?? '';
  return ref.watch(churchCredentialEventsProvider(tenantId).future);
});

/// The branch licence for the church the user is currently signed in to, or null
/// when it has never applied.
final currentBranchLicenseProvider = FutureProvider<BranchLicense?>((ref) {
  final tenantId = ref.watch(currentTenantProvider)?.id ?? '';
  if (tenantId.isEmpty) return null;
  return ref.watch(churchGovernanceServiceProvider).fetchBranchLicense(tenantId);
});

/// Members of a church, for the officer and credential pickers.
final currentChurchMembersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, churchId) {
  if (churchId.isEmpty) return const [];
  return ref.watch(churchGovernanceServiceProvider).fetchMembers(churchId);
});