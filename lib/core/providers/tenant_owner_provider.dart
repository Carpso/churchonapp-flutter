import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';

/// Is the signed-in user part of their tenancy's OWNER TIER?
///
/// Owner tier = pastor, bishop, apostle, prophet, general secretary, general
/// treasurer, treasurer (local church treasurer) plus custom delegates a pastor
/// or bishop has added (see `grant_tenant_owner`).
///
/// Only owner-tier people ever see a payment prompt — they are never charged
/// for themselves, their single purpose is to keep the tenancy paid up.
/// Members, assistant pastors/bishops and every other role must never be asked
/// to pay.
final isTenantOwnerProvider = FutureProvider<bool>((ref) async {
  try {
    final client = ref.watch(supabaseServiceProvider).client;
    final res = await client.rpc('am_i_tenant_owner');
    return res == true;
  } catch (_) {
    // Fail closed: never show a payment prompt to someone we cannot verify.
    return false;
  }
});
