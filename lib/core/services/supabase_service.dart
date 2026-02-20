import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SupabaseService {
  static const String supabaseUrl = 'https://db.churchonapp.com';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwicmVmIjoic3RyZWFtLWNvcmUiLCJpYXQiOjE3NzA5MDI0MTAsImV4cCI6MjA4NjQ3ODQxMH0.pADzepoU8o3c2-dggmyyFLwLDYR7pfd2BlYWdQK7lMQ';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
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
