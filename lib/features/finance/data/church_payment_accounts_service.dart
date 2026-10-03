import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/services/tenant_service.dart';

// ===========================================================================
// Phone + network helpers
// ===========================================================================
// Convention reused from `momo_phone_input_widget.dart` (ZICTA mobile prefixes):
//   MTN    096 / 076
//   Airtel 097 / 077
//   Zamtel 095 / 075
// `+260`, `260`, a leading `0` and a bare 9-digit number are all accepted.

/// Validates a Zambian mobile-money number.
///
/// Returns `null` when the number is valid, otherwise a message suitable for
/// showing directly under a text field. The shape is `+260` (optional) then
/// `9[5-7]` or `7[5-7]` then 7 digits.
String? validateZambianPhone(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Phone number is required';
  }
  final clean = value.replaceAll(RegExp(r'\D'), '');
  var local = clean;
  if (clean.startsWith('260') && clean.length >= 11) {
    local = '0${clean.substring(3)}';
  }
  if (!local.startsWith('0') && local.length == 9) {
    local = '0$local';
  }
  if (!RegExp(r'^0(9[5-7]|7[5-7])\d{7}$').hasMatch(local)) {
    return 'Enter a valid Zambian mobile number';
  }
  return null;
}

/// Returns `mtn` / `airtel` / `zamtel`, or **null** when the prefix is unknown or
/// not yet typed.
///
/// Deliberately returns null instead of defaulting: a network guessed from two
/// digits ("09…" is not enough to tell MTN from Airtel) would silently point the
/// collection at the wrong operator, so callers keep the current selection until
/// the prefix is unambiguous (>= 3 digits).
String? detectNetworkFromPhone(String phone) {
  final clean = phone.replaceAll(RegExp(r'\D'), '');
  if (clean.length < 3) return null;

  String local;
  if (clean.startsWith('260') && clean.length >= 11) {
    local = '0${clean.substring(3)}';
  } else if (clean.startsWith('0')) {
    local = clean;
  } else if (clean.length == 9) {
    local = '0$clean';
  } else {
    local = '0${clean.substring(clean.length - 9)}';
  }

  if (local.startsWith('096') || local.startsWith('076')) return 'mtn';
  if (local.startsWith('097') || local.startsWith('077')) return 'airtel';
  if (local.startsWith('095') || local.startsWith('075')) return 'zamtel';
  return null;
}

/// Pretty network name for chips/labels, e.g. `mtn` -> `MTN`.
String networkLabel(String? network) {
  switch ((network ?? '').toLowerCase()) {
    case 'mtn':
      return 'MTN';
    case 'airtel':
      return 'Airtel';
    case 'zamtel':
      return 'Zamtel';
    default:
      return 'Other';
  }
}

// ===========================================================================
// Model
// ===========================================================================

/// One mobile-money number a church can receive donations on.
///
/// A church may hold several per [purpose]; exactly one active one is
/// [isPrimary] — the number money is actually sent to, which is the one mirrored
/// into the legacy `churches.treasurer_phone` / `pastor_phone` /
/// `bishop_phone` / `contact_phone` columns that `giving_screen.dart` reads.
class ChurchPaymentAccount {
  final String id;
  final String churchId;

  /// `treasurer` | `pastor` | `bishop` | `organization`
  final String purpose;

  final String? label;
  final String phone;

  /// `mtn` | `airtel` | `zamtel` | null when the prefix is not recognised.
  final String? network;

  final bool isPrimary;
  final bool isActive;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ChurchPaymentAccount({
    required this.id,
    required this.churchId,
    required this.purpose,
    this.label,
    required this.phone,
    this.network,
    this.isPrimary = false,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory ChurchPaymentAccount.fromMap(Map<String, dynamic> map) {
    return ChurchPaymentAccount(
      id: map['id'].toString(),
      churchId: (map['church_id'] ?? '').toString(),
      purpose: (map['purpose'] ?? 'treasurer').toString(),
      label: map['label']?.toString(),
      phone: (map['phone'] ?? '').toString(),
      network: map['network']?.toString(),
      isPrimary: map['is_primary'] == true,
      isActive: map['is_active'] != false,
      createdBy: map['created_by']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  /// Write payload. `id`/`created_by`/`created_at` are server-owned and omitted.
  Map<String, dynamic> toMap() => {
        'church_id': churchId,
        'purpose': purpose,
        'label': label,
        'phone': phone,
        'network': network,
        'is_primary': isPrimary,
        'is_active': isActive,
      };

  ChurchPaymentAccount copyWith({
    String? purpose,
    String? label,
    String? phone,
    String? network,
    bool? isPrimary,
    bool? isActive,
  }) {
    return ChurchPaymentAccount(
      id: id,
      churchId: churchId,
      purpose: purpose ?? this.purpose,
      label: label ?? this.label,
      phone: phone ?? this.phone,
      network: network ?? this.network,
      isPrimary: isPrimary ?? this.isPrimary,
      isActive: isActive ?? this.isActive,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Human name of the slot this number fills.
  String get purposeLabel => purposeTitle(purpose).title;

  /// `MTN · Treasurer`, for chips and summaries.
  String get subtitle {
    final parts = <String>[networkLabel(network)];
    if ((label ?? '').isNotEmpty) parts.add(label!);
    return parts.join(' · ');
  }

  @override
  String toString() =>
      'ChurchPaymentAccount($purpose, $phone, primary: $isPrimary, active: $isActive)';
}

/// Display title + description for a purpose slot.
({String title, String hint}) purposeTitle(String purpose) {
  switch (purpose) {
    case 'pastor':
      return (
        title: 'Pastor',
        hint: 'Where giving goes when there is no treasurer.',
      );
    case 'bishop':
      return (
        title: 'Bishop',
        hint: 'The overseeing bishop — useful for a church without a treasurer.',
      );
    case 'organization':
      return (
        title: 'Organisation / Church office',
        hint: 'The conference remittance number or the church office line.',
      );
    case 'treasurer':
    default:
      return (
        title: 'Treasurer',
        hint: 'The number tithes and offerings are sent to.',
      );
  }
}

/// The purpose slots, in giving_screen.dart's precedence order.
const kPaymentAccountPurposes = <String>[
  'treasurer',
  'organization',
  'pastor',
  'bishop',
];

/// The legacy `churches` column each purpose mirrors into.
///
/// This is the bridge that lets the existing giving chain
/// (`treasurerPhone ?? contactPhone ?? pastorPhone`) keep working unchanged.
String legacyColumnForPurpose(String purpose) {
  switch (purpose) {
    case 'pastor':
      return 'pastor_phone';
    case 'bishop':
      return 'bishop_phone';
    case 'organization':
      return 'contact_phone';
    case 'treasurer':
    default:
      return 'treasurer_phone';
  }
}

/// Mirrors `giving_screen.dart`'s resolution chain over the register.
///
/// Order: the active primary of each purpose in precedence order, then any other
/// active account. Returns null when the church has nothing configured, which is
/// exactly the state that shows "No payment recipient configured for this
/// church".
String? resolveGivingPhone(List<ChurchPaymentAccount> accounts) {
  final active = accounts.where((a) => a.isActive).toList();
  if (active.isEmpty) return null;

  for (final purpose in kPaymentAccountPurposes) {
    for (final account in active) {
      if (account.purpose == purpose && account.isPrimary) return account.phone;
    }
  }
  // No primaries at all — still better than nothing, if anything is active.
  return active.first.phone;
}

// ===========================================================================
// Service
// ===========================================================================

class ChurchPaymentAccountsService {
  final SupabaseClient _client;
  ChurchPaymentAccountsService(this._client);

  /// Resolves a `currentTenantProvider` id to a real `churches.id`.
  ///
  /// Seeded data shares ONE uuid between `tenants.id` and `churches.id`, but a
  /// church registered after that split stores the tenancy id on
  /// `churches.tenant_id`. `church_payment_accounts.church_id` is a FK to
  /// `churches(id)`, so writing with a tenancy id would fail with 23503. Accept
  /// either input.
  Future<String?> resolveChurchId(String? tenantOrChurchId) async {
    final id = (tenantOrChurchId ?? '').trim();
    if (id.isEmpty) return null;
    try {
      final rows = await _client
          .from('churches')
          .select('id, tenant_id')
          .or('id.eq.$id,tenant_id.eq.$id')
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return null;
      return (list.first as Map)['id'].toString();
    } catch (e) {
      debugPrint('resolveChurchId failed for $id: $e');
      return null;
    }
  }

  /// The church's register, primary-first then most recently updated.
  ///
  /// Scoped explicitly by `church_id` rather than trusting RLS alone: staff
  /// (superadmin / COA) bypass the tenant branch of the read policy, so without
  /// this filter a platform user would see every church's payout numbers.
  Future<List<ChurchPaymentAccount>> fetchAccounts(
    String? churchId, {
    bool activeOnly = false,
  }) async {
    final church = await resolveChurchId(churchId);
    if (church == null) return [];

    dynamic q = _client.from('church_payment_accounts').select();
    q = q.eq('church_id', church);
    if (activeOnly) q = q.eq('is_active', true);

    final rows = await q.order('is_primary', ascending: false).order('purpose');
    final list = (rows as List)
        .map((e) =>
            ChurchPaymentAccount.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    // Group by purpose in the giving precedence order rather than alphabetically.
    list.sort((a, b) {
      final pa = kPaymentAccountPurposes.indexOf(a.purpose);
      final pb = kPaymentAccountPurposes.indexOf(b.purpose);
      final c = (pa < 0 ? 99 : pa).compareTo(pb < 0 ? 99 : pb);
      if (c != 0) return c;
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      return (b.updatedAt ?? DateTime(0))
          .compareTo(a.updatedAt ?? DateTime(0));
    });
    return list;
  }

  /// Creates a new account, or updates an existing one when [id] is given.
  ///
  /// `is_primary` is deliberately NOT part of the plain write. The partial unique
  /// index on `(church_id, purpose) WHERE is_primary AND is_active` is enforced
  /// per row-statement, so demoting one primary and promoting another in a single
  /// UPDATE is impossible; and demoting without promoting would make the
  /// `sync_church_payment_account_to_churches` trigger briefly blank the legacy
  /// column. Moving a primary therefore goes through `set_church_primary_account`.
  Future<ChurchPaymentAccount> saveAccount({
    String? id,
    required String churchId,
    required String purpose,
    required String phone,
    String? label,
    String? network,
    bool isPrimary = false,
    bool isActive = true,
  }) async {
    final church = await resolveChurchId(churchId);
    if (church == null) {
      throw Exception('Could not resolve this church');
    }
    final error = validateZambianPhone(phone);
    if (error != null) throw Exception(error);

    final payload = <String, dynamic>{
      'church_id': church,
      'purpose': purpose,
      'label': (label ?? '').trim().isEmpty ? null : (label ?? '').trim(),
      'phone': phone.trim(),
      'network': network ?? detectNetworkFromPhone(phone),
      'is_active': isActive,
    };

    late ChurchPaymentAccount saved;
    if (id == null) {
      final row = await _client
          .from('church_payment_accounts')
          .insert({...payload, 'is_primary': false})
          .select()
          .single();
      saved =
          ChurchPaymentAccount.fromMap(Map<String, dynamic>.from(row as Map));
    } else {
      // Only write `is_primary` when this is an explicit DEMOTION of the current
      // primary; leaving it alone otherwise keeps the mirror stable.
      final current = await _fetchOne(id);
      if (current != null && current.isPrimary && !isPrimary) {
        payload['is_primary'] = false;
      }
      final row = await _client
          .from('church_payment_accounts')
          .update(payload)
          .eq('id', id)
          .select()
          .single();
      saved =
          ChurchPaymentAccount.fromMap(Map<String, dynamic>.from(row as Map));
    }

    if (isPrimary && !saved.isPrimary) {
      saved = await setPrimary(saved.id);
    }

    // The integration point: keep the legacy column the existing giving chain
    // reads in step with the register.
    await syncPrimaryToChurchesRow(church, saved);
    return saved;
  }

  Future<void> deleteAccount(String id) async {
    await _client.from('church_payment_accounts').delete().eq('id', id);
  }

  /// Promotes one account for its purpose, demoting its siblings and forcing it
  /// active. The demote-then-promote ordering lives in the RPC because a single
  /// client UPDATE cannot satisfy the partial unique index.
  Future<ChurchPaymentAccount> setPrimary(String id) async {
    final res = await _client.rpc('set_church_primary_account', params: {
      'p_account_id': id,
    });

    // PostgREST returns a composite (table row type) as a JSON object, but some
    // gateway versions hand composites back as a JSON string — accept both.
    Object? decoded = res;
    if (res is String) {
      try {
        decoded = jsonDecode(res);
      } catch (_) {
        decoded = null;
      }
    }
    if (decoded is Map) {
      return ChurchPaymentAccount.fromMap(Map<String, dynamic>.from(decoded));
    }

    // RPC returned nothing readable — re-read so the caller still gets a row.
    final rows = await _client
        .from('church_payment_accounts')
        .select()
        .eq('id', id)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) throw Exception('Could not set the primary account');
    return ChurchPaymentAccount.fromMap(
        Map<String, dynamic>.from(list.first as Map));
  }

  /// Flips [isActive]. An account that is deactivated must not stay primary, or
  /// the mirror keeps paying a number the church has retired.
  Future<ChurchPaymentAccount> setActive(String id, bool isActive) async {
    if (!isActive) {
      final current = await _fetchOne(id);
      if (current != null && current.isPrimary) {
        // Demote first so the partial unique index stays satisfied.
        await _client
            .from('church_payment_accounts')
            .update({'is_primary': false})
            .eq('id', id);
      }
    }
    final row = await _client
        .from('church_payment_accounts')
        .update({'is_active': isActive})
        .eq('id', id)
        .select()
        .single();
    return ChurchPaymentAccount.fromMap(Map<String, dynamic>.from(row as Map));
  }

  Future<ChurchPaymentAccount?> _fetchOne(String id) async {
    try {
      final rows =
          await _client.from('church_payment_accounts').select().eq('id', id);
      final list = rows as List;
      if (list.isEmpty) return null;
      return ChurchPaymentAccount.fromMap(
          Map<String, dynamic>.from(list.first as Map));
    } catch (e) {
      debugPrint('_fetchOne failed for $id: $e');
      return null;
    }
  }

  /// CRITICAL INTEGRATION POINT — writes the primary back to `churches` so the
  /// EXISTING resolution chain in `giving_screen.dart`
  /// (`treasurerPhone ?? contactPhone ?? pastorPhone`) keeps working with no
  /// change to that file.
  ///
  /// Mirrors per purpose into the matching legacy column. Passing a null
  /// [account] clears the column.
  ///
  /// Returns true when the column was written. A failure here is logged and
  /// swallowed rather than thrown: the account row is already saved, the DB
  /// trigger `sync_church_payment_account_to_churches` mirrors the same value
  /// independently, and reporting the save as failed would leave leadership
  /// thinking nothing happened.
  Future<bool> syncPrimaryToChurchesRow(
    String churchId,
    ChurchPaymentAccount? account,
  ) async {
    final church = await resolveChurchId(churchId);
    if (church == null) {
      debugPrint('syncPrimaryToChurchesRow: could not resolve $churchId');
      return false;
    }
    final column = legacyColumnForPurpose(account?.purpose ?? 'treasurer');
    try {
      await _client
          .from('churches')
          .update({column: account?.phone})
          .eq('id', church);
      return true;
    } catch (e) {
      debugPrint('syncPrimaryToChurchesRow failed ($column): $e');
      return false;
    }
  }
}

// ===========================================================================
// Providers
// ===========================================================================

final churchPaymentAccountsServiceProvider =
    Provider<ChurchPaymentAccountsService>(
        (ref) => ChurchPaymentAccountsService(Supabase.instance.client));

/// The register for an explicit church.
///
/// Keyed by a plain `String` church/tenant id — a value-equal key. A Map/List key
/// has no value equality and would rebuild (and refetch) on every frame; see the
/// RIVERPOD FAMILY KEYS rule in AGENTS.md.
final churchPaymentAccountsProvider =
    FutureProvider.family<List<ChurchPaymentAccount>, String>(
        (ref, churchId) => ref
            .watch(churchPaymentAccountsServiceProvider)
            .fetchAccounts(churchId));

/// The register for the church the user is currently signed in to.
final currentChurchPaymentAccountsProvider =
    FutureProvider<List<ChurchPaymentAccount>>((ref) async {
  final tenant = ref.watch(currentTenantProvider);
  if (tenant == null || tenant.id.isEmpty) return const [];
  return ref
      .watch(churchPaymentAccountsServiceProvider)
      .fetchAccounts(tenant.id);
});

/// The number a gift would actually be sent to, or null when the church has no
/// payment account configured. Mirrors `giving_screen.dart`'s precedence.
final churchGivingRecipientPhoneProvider = FutureProvider<String?>((ref) async {
  final accounts = await ref.watch(currentChurchPaymentAccountsProvider.future);
  return resolveGivingPhone(accounts);
});