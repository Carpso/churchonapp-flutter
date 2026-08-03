import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CodeGeneratorService {
  final SupabaseClient _client;

  CodeGeneratorService(this._client);

  static const String brandPrefix = 'COA';

  static String countryToISO(String country) {
    final map = <String, String>{
      'zambia': 'ZM',
      'zimbabwe': 'ZW',
      'south africa': 'ZA',
      'botswana': 'BW',
      'namibia': 'NA',
      'lesotho': 'LS',
      'eswatini': 'SZ',
      'swaziland': 'SZ',
      'mozambique': 'MZ',
      'angola': 'AO',
      'malawi': 'MW',
      'kenya': 'KE',
      'tanzania': 'TZ',
      'uganda': 'UG',
      'rwanda': 'RW',
      'burundi': 'BI',
      'ethiopia': 'ET',
      'eritrea': 'ER',
      'somalia': 'SO',
      'somaliland': 'SO',
      'djibouti': 'DJ',
      'south sudan': 'SS',
      'democratic republic of the congo': 'CD',
      'dr congo': 'CD',
      'drc': 'CD',
      'congo': 'CG',
      'republic of the congo': 'CG',
      'congo brazzaville': 'CG',
      'gabon': 'GA',
      'equatorial guinea': 'GQ',
      'cameroon': 'CM',
      'central african republic': 'CF',
      'chad': 'TD',
      'sao tome and principe': 'ST',
      'nigeria': 'NG',
      'ghana': 'GH',
      "cote d'ivoire": 'CI',
      'ivory coast': 'CI',
      'senegal': 'SN',
      'mali': 'ML',
      'burkina faso': 'BF',
      'niger': 'NE',
      'benin': 'BJ',
      'togo': 'TG',
      'guinea': 'GN',
      'guinea bissau': 'GW',
      'liberia': 'LR',
      'sierra leone': 'SL',
      'gambia': 'GM',
      'the gambia': 'GM',
      'cape verde': 'CV',
      'caboverde': 'CV',
      'mauritania': 'MR',
      'morocco': 'MA',
      'algeria': 'DZ',
      'tunisia': 'TN',
      'libya': 'LY',
      'egypt': 'EG',
      'sudan': 'SD',
      'madagascar': 'MG',
      'mauritius': 'MU',
      'seychelles': 'SC',
      'comoros': 'KM',
      'reunion': 'RE',
      'mayotte': 'YT',
      'united kingdom': 'GB',
      'united states': 'US',
      'india': 'IN',
    };
    return map[country.trim().toLowerCase()] ?? country.substring(0, 2).toUpperCase();
  }

  // ─── Tenant / Church / Bookshop ─────────────────────────────

  Future<String> generateTenantCode(String country) async {
    final iso = countryToISO(country);
    final next = await _nextSequence('tenant_code');
    return '$brandPrefix-${iso}_T_$next';
  }

  Future<String> generateChurchCode(String country) async {
    final iso = countryToISO(country);
    final next = await _nextSequence('church_code');
    return '$brandPrefix-${iso}_CH_$next';
  }

  Future<String> generateBookshopCode(String country) async {
    final iso = countryToISO(country);
    final next = await _nextSequence('bookshop_code');
    return '$brandPrefix-${iso}_BS_$next';
  }

  // ─── User ──────────────────────────────────────────────────

  Future<String> generateUserCode(String country) async {
    final iso = countryToISO(country);
    final rand = _randomAlphaNum(6);
    final body = '$brandPrefix-${iso}_U_$rand';
    return '$body${_checksumChar(body)}';
  }

  // ─── Tithe Card ────────────────────────────────────────────

  Future<String> generateTitheCardNumber(String country) async {
    final iso = countryToISO(country);
    final year = DateTime.now().year.toString();
    final next = await _nextSequence('tithe_card');
    return '$brandPrefix-$iso-TC-$year-${next.padLeft(6, '0')}';
  }

  Future<String> generateReferralCode(String country) async {
    final iso = countryToISO(country);
    final rand = _randomAlphaNum(6);
    final body = '$brandPrefix-$iso-REF-$rand';
    return '$body${_checksumChar(body)}';
  }

  // ─── Partner Voucher ───────────────────────────────────────

  Future<String> generateVoucherCode(String country) async {
    final iso = countryToISO(country);
    final rand = _randomAlphaNum(6);
    final body = '$brandPrefix-$iso-VOUCH-$rand';
    return '$body${_checksumChar(body)}';
  }

  // ─── Wallet ────────────────────────────────────────────────

  Future<String> generateWalletId(String country) async {
    final iso = countryToISO(country);
    final rand = _randomAlphaNum(6);
    final body = '$brandPrefix-$iso-W-$rand';
    return '$body${_checksumChar(body)}';
  }

  // ─── Membership ────────────────────────────────────────────

  Future<String> generateMembershipId(String country) async {
    final iso = countryToISO(country);
    final next = await _nextSequence('membership_id');
    return '$brandPrefix-$iso-MEM-${next.padLeft(6, '0')}';
  }

  // ─── Event Ticket ──────────────────────────────────────────

  Future<String> generateTicketId() async {
    final year = DateTime.now().year.toString();
    final rand = _randomAlphaNum(6);
    return '$brandPrefix-TKT-$year-$rand';
  }

  // ─── Payment Reference ─────────────────────────────────────

  Future<String> generatePaymentRef() async {
    final year = DateTime.now().year.toString();
    final rand = _randomAlphaNum(6);
    return '$brandPrefix-TXN-$year-$rand';
  }

  Future<List<String>> generateBulkUserCodes(String country, int count) async {
    final codes = <String>[];
    for (int i = 0; i < count; i++) {
      codes.add(await generateUserCode(country));
    }
    return codes;
  }

  // ─── Church Slug ───────────────────────────────────────────

  Future<String> generateChurchSlug(String churchName, String country) async {
    final iso = countryToISO(country).toLowerCase();
    final base = churchName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .trim()
        .replaceAll(RegExp(r'^-|-$'), '');
    final next = await _nextSequence('church_slug');
    return '${iso}_${base}_$next';
  }

  // ─── Validation ────────────────────────────────────────────

  static final Map<String, RegExp> _formatPatterns = {
    'tenant': RegExp(r'^COA-[A-Z]{2}_T_\d{4}$'),
    'church': RegExp(r'^COA-[A-Z]{2}_CH_\d{4}$'),
    'bookshop': RegExp(r'^COA-[A-Z]{2}_BS_\d{4}$'),
    'user': RegExp(r'^COA-[A-Z]{2}_U_[A-Z0-9]{6}[A-Z0-9]?$'),
    'tithe_card': RegExp(r'^COA-[A-Z]{2}-TC-\d{4}-\d{6}$'),
    'referral': RegExp(r'^COA-[A-Z]{2}-REF-[A-Z0-9]{6}[A-Z0-9]?$'),
    'wallet': RegExp(r'^COA-[A-Z]{2}-W-[A-Z0-9]{6}[A-Z0-9]?$'),
    'membership': RegExp(r'^COA-[A-Z]{2}-MEM-\d{6}$'),
    'ticket': RegExp(r'^COA-TKT-\d{4}-[A-Z0-9]{6}$'),
    'payment': RegExp(r'^COA-TXN-\d{4}-[A-Z0-9]{6}$'),
  };

  bool isValidFormat(String code) {
    return _formatPatterns.values.any((p) => p.hasMatch(code));
  }

  String? detectType(String code) {
    for (final entry in _formatPatterns.entries) {
      if (entry.value.hasMatch(code)) return entry.key;
    }
    return null;
  }

  String? extractCountryIso(String code) {
    final match = RegExp(r'^COA-([A-Z]{2})').firstMatch(code);
    return match?.group(1);
  }

  static String _checksumChar(String body) {
    int sum = 0;
    for (int i = 0; i < body.length; i++) {
      sum += body.codeUnitAt(i) * (i + 1);
    }
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return chars[sum % chars.length];
  }

  static bool validateCode(String code) {
    for (final entry in _formatPatterns.entries) {
      if (entry.value.hasMatch(code)) return true;
    }
    return false;
  }

  // ─── Code Registry ─────────────────────────────────────────

  Future<void> registerCode({
    required String codeType,
    required String codeValue,
    required String countryIso,
    String? userId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _client.from('generated_codes').insert({
        'code_type': codeType,
        'code_value': codeValue,
        'country_iso': countryIso,
        'user_id': userId,
        'metadata': metadata,
      });
    } catch (e) {
      debugPrint('CodeGenerator: registerCode failed: $e');
    }
  }

  Future<Map<String, dynamic>?> lookupCode(String code) async {
    try {
      final result = await _client
          .from('generated_codes')
          .select('code_type, code_value, user_id, country_iso, metadata, created_at')
          .eq('code_value', code)
          .maybeSingle();
      return result;
    } catch (e) {
      debugPrint('CodeGenerator: lookupCode failed: $e');
      return null;
    }
  }

  Future<bool> isCodeTaken(String code) async {
    try {
      final result = await _client
          .from('generated_codes')
          .select('id')
          .eq('code_value', code)
          .maybeSingle();
      return result != null;
    } catch (_) {
      return false;
    }
  }

  // ─── Sequence Engine ───────────────────────────────────────

  Future<String> _nextSequence(String name) async {
    try {
      final res = await _client.rpc('next_id_sequence', params: {
        'seq_name': name,
      });
      if (res != null) return res.toString().padLeft(4, '0');
    } catch (e) {
      debugPrint('CodeGenerator: RPC next_id_sequence failed, using local fallback: $e');
    }
    return _localFallback(name);
  }

  final Map<String, int> _localCounters = {};

  String _localFallback(String name) {
    _localCounters[name] = (_localCounters[name] ?? DateTime.now().millisecondsSinceEpoch % 900000) + 1;
    return _localCounters[name]!.toString().padLeft(4, '0');
  }

  String _randomAlphaNum(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    final buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(chars[rng.nextInt(chars.length)]);
    }
    return buffer.toString();
  }
}

final codeGeneratorProvider = Provider<CodeGeneratorService>((ref) {
  final client = Supabase.instance.client;
  return CodeGeneratorService(client);
});
