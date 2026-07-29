import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/env.dart';

class SupabaseService {
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
  }

  SupabaseClient get client => Supabase.instance.client;

  // Stream of church coins for a specific user
  Stream<List<Map<String, dynamic>>> getCoinStream(String userId) {
    return client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId);
  }
}

final supabaseServiceProvider = Provider((ref) => SupabaseService());

