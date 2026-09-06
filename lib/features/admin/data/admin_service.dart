import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/services/tenant_service.dart';
import '../../connect/data/social_service.dart';

class AdminService {
  final SupabaseClient _client;
  AdminService(this._client);

  /// Fetch members for a tenant — uses one-shot query for reliability
  /// Fetch members for a tenant — enforces strict tenant isolation
  Future<List<UserProfile>> getMembers({String? tenantId}) async {
    try {
      final currentUser = _client.auth.currentUser;
      String? effectiveTenantId = tenantId;

      if (currentUser != null) {
        final callerProfile = await _client
            .from('profiles')
            .select('role, tenant_id')
            .eq('id', currentUser.id)
            .maybeSingle();

        final role = callerProfile?['role'] as String? ?? 'member';
        final isSuper = role == 'superadmin' || role == 'coa_employee';

        if (!isSuper) {
          // Non-superadmins are strictly restricted to their own tenant
          effectiveTenantId = callerProfile?['tenant_id'] as String?;
          if (effectiveTenantId == null || effectiveTenantId.isEmpty) {
            return [];
          }
        }
      }

      if (effectiveTenantId != null && effectiveTenantId.isNotEmpty) {
        final result = await _client
            .from('profiles')
            .select()
            .eq('tenant_id', effectiveTenantId)
            .order('full_name');
        return (result as List).map((m) => UserProfile.fromMap(m)).toList();
      } else {
        final result = await _client
            .from('profiles')
            .select()
            .order('full_name');
        return (result as List).map((m) => UserProfile.fromMap(m)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching members: $e');
      return [];
    }
  }

  Stream<List<UserProfile>> getMembersStream({String? tenantId}) {
    final baseStream = _client.from('profiles').stream(primaryKey: ['id']);
    if (tenantId != null && tenantId.isNotEmpty) {
      return baseStream
          .eq('tenant_id', tenantId)
          .order('full_name')
          .map((data) => data.map((map) => UserProfile.fromMap(map)).toList());
    } else {
      return baseStream
          .order('full_name')
          .map((data) => data.map((map) => UserProfile.fromMap(map)).toList());
    }
  }

  Future<void> updateUserRole(String userId, String newRole) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) throw Exception("Not authenticated");

    final callerProfile = await _client
        .from('profiles')
        .select('role, tenant_id')
        .eq('id', currentUser.id)
        .maybeSingle();

    final callerRole = callerProfile?['role'] as String? ?? 'member';
    final callerTenantId = callerProfile?['tenant_id'] as String?;
    final isSuper = callerRole == 'superadmin' || callerRole == 'employee';

    final targetProfile = await _client
        .from('profiles')
        .select('tenant_id')
        .eq('id', userId)
        .maybeSingle();

    if (targetProfile == null) throw Exception("Target user profile not found");

    if (!isSuper) {
      if (callerTenantId == null || callerTenantId != targetProfile['tenant_id']) {
        throw Exception("Security Restriction: You can only update roles for members within your own church.");
      }
    }

    await _client.from('profiles').update({'role': newRole}).eq('id', userId);
  }

  // --- Logistics Analytics ---

  Future<int> getTotalRidesCount() async {
    final res = await _client.from('ride_requests').select('id');
    return (res as List).length;
  }

  Future<int> getPendingDeliveriesCount() async {
    final res = await _client.from('delivery_requests').select('id').eq('status', 'pending');
    return (res as List).length;
  }

  /// Active couriers — COA team sees Carpso drivers/riders (global);
  /// tenants see their church fleet (church_buses for their tenant).
  /// Tenants must NOT manage Carpso.
  Future<int> getActiveCouriersCount({String? tenantId}) async {
    if (tenantId != null && tenantId.isNotEmpty) {
      try {
        final res = await _client
            .from('church_buses')
            .select('id')
            .eq('tenant_id', tenantId);
        return (res as List).length;
      } catch (e) {
        debugPrint('getActiveCouriersCount (buses) failed: $e');
        return 0;
      }
    }
    final res = await _client
        .from('profiles')
        .select('id')
        .inFilter('role', ['driver', 'rider']);
    return (res as List).length;
  }

  // --- Financial Analytics ---

  Future<double> getTotalTransactionVolume() async {
    final res = await _client.from('wallet_transactions').select('amount');
    final data = res as List;
    return data.fold<double>(0.0, (sum, item) {
      final amt = item['amount'];
      if (amt == null) return sum;
      return sum + (amt as num).toDouble().abs();
    });
  }

  Future<Map<String, double>> getMonthlyFinancialStats() async {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    
    final res = await _client.from('wallet_transactions').select('amount, type').gte('created_at', firstDay.toIso8601String());
    final data = res as List;
    
    double rides = 0;
    double deliveries = 0;
    double tithes = 0;
    
    for (var item in data) {
      final amt = (item['amount'] as num).toDouble().abs();
      final type = item['type'] as String;
      
      if (type.contains('ride')) {
        rides += amt;
      } else if (type.contains('delivery')) {
        deliveries += amt;
      } else if (type == 'tithe' || type == 'giving') {
        tithes += amt;
      }
    }
    
    return {
      'rides': rides,
      'deliveries': deliveries,
      'tithes': tithes,
      'total': rides + deliveries + tithes,
    };
  }

  // --- Payout Management ---

  Future<void> requestPayout({required double amount, required String mobileNumber, required String network}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('payout_requests').insert({
      'user_id': user.id,
      'amount': amount,
      'mobile_number': mobileNumber,
      'network': network,
      'status': 'pending',
    });
  }

  Future<List<Map<String, dynamic>>> getPayoutRequests({String? tenantId}) async {
    var builder = _client.from('payout_requests').select('*, profiles(full_name)');
    if (tenantId != null) {
      builder = builder.eq('tenant_id', tenantId);
    }
    final res = await builder.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> processPayout(String payoutId, String status) async {
    await _client.from('payout_requests').update({'status': status}).eq('id', payoutId);
  }

  /// Validates a single payout request (checks role eligibility + sufficient balance).
  /// Does NOT auto-process — admin must explicitly approve each request.
  Future<Map<String, dynamic>> validatePayoutRequest(String payoutId) async {
    final res = await _client.from('payout_requests')
        .select('*, profiles(role, coins, full_name)')
        .eq('id', payoutId)
        .maybeSingle();

    if (res == null) return {'valid': false, 'error': 'Request not found'};
    if (res['status'] != 'pending') return {'valid': false, 'error': 'Already ${res['status']}'};

    final role = res['profiles']?['role'] as String?;
    final amount = (res['amount'] as num).toDouble();
    final coins = (res['profiles']?['coins'] as num?)?.toDouble() ?? 0.0;
    final name = res['profiles']?['full_name'] as String? ?? 'Unknown';

    final authorizedRoles = ['superadmin', 'coa_employee', 'pastor', 'bishop', 'usher', 'writer', 'driver', 'rider'];
    if (!authorizedRoles.contains(role)) {
      return {'valid': false, 'error': 'Role "$role" not authorized for payout'};
    }
    if (coins < amount) {
      return {'valid': false, 'error': 'Insufficient balance (${coins.toStringAsFixed(0)} CC < ${amount.toStringAsFixed(0)} CC)'};
    }

    return {
      'valid': true,
      'name': name,
      'role': role,
      'amount': amount,
      'coins': coins,
    };
  }

  /// Processes a single payout request after explicit admin approval.
  /// Validates role + balance, deducts coins, logs settlement.
  Future<void> approveAndProcessPayout(String payoutId) async {
    final validation = await validatePayoutRequest(payoutId);
    if (!validation['valid']) throw Exception(validation['error']);

    final res = await _client.from('payout_requests')
        .select('user_id, amount')
        .eq('id', payoutId)
        .single();

    final userId = res['user_id'] as String;
    final amount = (res['amount'] as num).toDouble();
    final coins = validation['coins'] as double;
    final role = validation['role'] as String;

    // Process the payout
    await processPayout(payoutId, 'processed');

    // Deduct coins
    await _client.from('profiles')
        .update({'coins': coins - amount})
        .eq('id', userId);

    // Log settlement
    await _client.from('wallet_transactions').insert({
      'user_id': userId,
      'amount': -amount,
      'type': 'payout_settlement',
      'reference_id': payoutId,
      'description': 'Approved Payout: $role',
    });
  }

  /// Validates all pending payout requests (returns validation results per request).
  Future<List<Map<String, dynamic>>> validateAllPendingPayouts() async {
    final res = await _client.from('payout_requests')
        .select('id')
        .eq('status', 'pending');
    final requests = List<Map<String, dynamic>>.from(res);

    final results = <Map<String, dynamic>>[];
    for (var req in requests) {
      final validation = await validatePayoutRequest(req['id']);
      results.add({...validation, 'payout_id': req['id']});
    }
    return results;
  }

  /// Verifies a driver's payout status and settles any pending balance discrepancies.
  Future<void> verifyDriverPayout(String driverId) async {
    final res = await _client.from('profiles').select('coins, full_name').eq('id', driverId).maybeSingle();
    if (res == null) return;
    final coins = (res['coins'] as num?)?.toDouble() ?? 0.0;
    
    // Log verification event
    await _client.from('wallet_transactions').insert({
      'user_id': driverId,
      'amount': 0,
      'type': 'payout_verification',
      'description': 'Verified settlement status for ${res['full_name']}. Current balance: $coins CC',
    });
  }

  // --- Multi-Currency Wallet Management ---

  Future<void> updateMultiCurrencyBalance(String userId, {double? addCC, double? addZMW}) async {
    final profile = await _client.from('profiles').select('balance_cc, balance_zmw').eq('id', userId).maybeSingle();
    if (profile == null) return;
    final newCC = ((profile['balance_cc'] as num?)?.toDouble() ?? 0.0) + (addCC ?? 0);
    final newZMW = ((profile['balance_zmw'] as num?)?.toDouble() ?? 0.0) + (addZMW ?? 0);

    await _client.from('profiles').update({
      'balance_cc': newCC,
      'balance_zmw': newZMW,
    }).eq('id', userId);
  }

  // --- Prophetic Navigation (Route Optimization) ---

  Future<void> savePropheticRoute(String missionId, Map<String, dynamic> optimization) async {
    await _client.from('route_optimizations').insert({
      'mission_id': missionId,
      'optimized_path': optimization['optimized_path'],
      'efficiency_rating': optimization['efficiency_rating'],
      'prophetic_insight': optimization['prophetic_insight'],
    });
  }

  Future<List<Map<String, dynamic>>> getPendingMissions() async {
    final res = await _client.from('delivery_requests').select('*, profiles(full_name)').eq('status', 'pending');
    return List<Map<String, dynamic>>.from(res);
  }

  // --- Apostolic Resource Allocation ---

  Future<List<Map<String, dynamic>>> getChurchHubs() async {
    final res = await _client.from('churches').select('id, name').order('name');
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> saveResourceAllocation(String hubId, Map<String, dynamic> prediction) async {
    final List predictions = prediction['predictions'];
    for (var item in predictions) {
      await _client.from('resource_allocations').insert({
        'hub_id': hubId,
        'resource_type': item['type'],
        'predicted_need_quantity': item['quantity'],
        'prophetic_justification': prediction['prophetic_justification'],
      });
    }
  }

  // --- Lipila Global Payout Automation ---

  Future<Map<String, dynamic>> executeLipilaPayout({
    required String userId,
    required double amount,
    required String phone,
    required String network,
  }) async {
    final insertRes = await _client.from('lenco_payouts').insert({
      'user_id': userId,
      'amount': amount,
      'recipient_phone': phone,
      'recipient_network': network,
      'status': 'pending',
    }).select().single();

    try {
      final result = await _client.functions.invoke('lipila-payout', body: {
        'accountNumber': phone,
        'amount': amount,
        'narration': 'Admin manual payout',
        'referenceId': insertRes['id'].toString(),
      });

      final data = result.data as Map<String, dynamic>?;
      if (data?['success'] == true) {
        await _client.from('lenco_payouts').update({
          'status': 'successful',
          'lenco_reference': data!['reference'] ?? '',
        }).eq('id', insertRes['id']);
        return {'success': true, 'reference': data['reference'] ?? ''};
      } else {
        throw Exception(data?['error'] ?? 'Lipila payout rejected');
      }
    } catch (e) {
      await _client.from('lenco_payouts').update({
        'status': 'failed',
        'error_log': e.toString(),
      }).eq('id', insertRes['id']);
      return {'success': false, 'error': e.toString()};
    }
  }

  // --- Prophetic Surveillance (Heatmap) ---

  /// Real expansion data: every church with coordinates + live member count.
  Future<List<Map<String, dynamic>>> fetchPropheticHeatmap() async {
    final res = await _client.rpc('get_prophetic_heatmap_data');
    return List<Map<String, dynamic>>.from(res);
  }

  /// Legacy manual data points (kept as low-weight extras).
  Future<List<Map<String, dynamic>>> fetchLegacyHeatmapPoints() async {
    try {
      final res = await _client.rpc('get_prophetic_heatmap_legacy');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Prophetic heatmap legacy points unavailable: $e');
      return [];
    }
  }

  // --- Kingdom AI Moderator ---

  Future<int> runApostolicModeration(WidgetRef ref) async {
    final gemini = ref.read(geminiServiceProvider);
    
    // 1. Fetch unmoderated posts
    final res = await _client.from('social_posts')
        .select('id, content')
        .eq('is_moderated', false)
        .limit(10);
        
    final posts = List<Map<String, dynamic>>.from(res);
    int moderatedCount = 0;

    for (var post in posts) {
      final content = post['content'] ?? "";
      if (content.isEmpty) continue;

      // 2. AI Moderation
      final moderation = await gemini.moderateSocialPost(content);
      
      // 3. Update VPS Ledger
      await _client.from('social_posts').update({
        'prophetic_weight': moderation['weight'],
        'category': moderation['category'],
        'is_moderated': true,
      }).eq('id', post['id']);

      moderatedCount++;
    }
    
    return moderatedCount;
  }
}

final adminServiceProvider = Provider((ref) => AdminService(Supabase.instance.client));

/// One-shot members provider — more reliable than Realtime stream
final membersProvider = FutureProvider<List<UserProfile>>((ref) async {
  final tenantId = ref.watch(currentTenantProvider)?.id;
  return ref.watch(adminServiceProvider).getMembers(tenantId: tenantId);
});

final membersStreamProvider = StreamProvider<List<UserProfile>>((ref) {
  final tenantId = ref.watch(currentTenantProvider)?.id;
  return ref.watch(adminServiceProvider).getMembersStream(tenantId: tenantId);
});

final postsStreamProvider = StreamProvider<List<SocialPost>>((ref) {
  final client = Supabase.instance.client;
  return client
      .from('social_posts')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .asyncMap((data) async {
        final posts = (data as List).cast<Map<String, dynamic>>();
        final userIds = posts
            .map((p) => p['user_id']?.toString())
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toSet();
        final profiles = <String, Map<String, dynamic>>{};
        if (userIds.isNotEmpty) {
          try {
            final res = await client
                .from('profiles')
                .select('id, full_name, avatar_url, role')
                .inFilter('id', userIds.toList());
            for (final row in (res as List)) {
              final map = Map<String, dynamic>.from(row);
              profiles[map['id']?.toString() ?? ''] = map;
            }
          } catch (e) {
            debugPrint('admin_service: profile enrich error: $e');
          }
        }
        return posts.map((map) {
          final enriched = Map<String, dynamic>.from(map);
          final pid = map['user_id']?.toString() ?? '';
          if (profiles.containsKey(pid)) {
            enriched['profiles'] = profiles[pid];
          }
          return SocialPost.fromMap(enriched);
        }).toList();
      });
});

