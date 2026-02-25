import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ExpansionService {
  final SupabaseClient _client;
  ExpansionService(this._client);

  Future<void> trackChurchInterest({
    required String churchName,
    required String location,
    String type = 'notify_on_registration',
  }) async {
    final user = _client.auth.currentUser;
    // We can track even if not logged in if we want, but for now assuming some context
    await _client.from('expansion_leads').insert({
      if (user != null) 'user_id': user.id,
      'church_name': churchName,
      'location': location,
      'interest_type': type,
    });
  }
}

final expansionServiceProvider = Provider((ref) => ExpansionService(Supabase.instance.client));
