import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/env.dart';

class SupabaseService {
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
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

  // Fetch mock user for prototype
  Future<Map<String, dynamic>?> getMockUser() async {
    // For now, returning mock data to keep the UI alive
    return {
      'name': 'Believer',
      'church_coins': 2450,
      'is_faithful': true,
    };
  }
}

final supabaseServiceProvider = Provider((ref) => SupabaseService());

